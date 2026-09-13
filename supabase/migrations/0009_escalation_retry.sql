-- 0009_escalation_retry.sql — محاولة مقطوعة نصّها ما تضيعش الجرعة.
--
-- ------------------------------------------------------------------ العطل
--
-- الدالة السحابية بتحجز الصف **قبل** ما تبعت: `insert` في `escalations`،
-- وبعدين FCM، وبعدين بتكتب النتيجة. لو ماتت بين الحجز والكتابة — انتهت
-- مهلتها، اتعمل لها recycle، اتظبطت نشرة جديدة — الصف بيفضل عند
-- `delivery_status = 'claimed'` للأبد.
--
-- و`due_escalations` كانت بتستبعد **أي** صف موجود. يعني الجرعة دي عمرها
-- ما هتتنبّه عليها تاني، ولا مرة، من غير أي أثر في أي لوج. الحالة اللي
-- المنتج كله اتبنى عشانها بتعدّي في صمت.
--
-- ده مش احتمال نظري: Edge Functions بيتعمل لها recycle، و`SCAN_LIMIT`
-- مية وميتين هدف بتتبعت **بالدور**، كل واحد رحلة لـFCM.
--
-- --------------------------------------------------------------- العلاج
--
-- صف لسه `claimed` وعدّى عليه أكتر من [escalation_retry_after] بيرجع
-- مستحق تاني. والحجز بقى عملية واحدة ذرّية بتاخد الصف البايت أو بترفض —
-- مش `insert` بيقع بـ409 (اللي كان هيخلّي الإصلاح ده بلا معنى: الدالة
-- كانت هتشوف التعارض وتعدّي).
--
-- `'sent'` و`'no_token'` و`'failed'` **بتفضل مستبعدة زي ما هي بالظبط**.
-- دول قرارات اتكتبت، مش محاولات اتقطعت.
--
-- ================================================================ الحكم
--
-- **لو الدالة ماتت بعد ما FCM قبل الرسالة وقبل ما تكتب 'sent'، إعادة
-- المحاولة بتبعت الإشعار مرتين.** ده مش أثر جانبي غفلنا عنه — ده
-- الاختيار.
--
-- ابن بيوصله نفس التنبيه مرتين: إزعاج. ثانية من الحيرة وبعدين بيطمن على
-- أبوه.
--
-- ابن **ما يتقالش** إن أبوه ما أخدش الدوا: ده الفشل اللي المنتج كله
-- موجود عشان يمنعه. المكالمات الصوتية اتلغت، فالإشعار ده آخر درجة في
-- السلّم ومفيش تحتها حاجة.
--
-- بنختار التكرار. عن قصد، ومكتوبة هنا عشان اللي هيقرا الكود بعد سنة
-- يعرف إنها قرار، مش سهو يستاهل «إصلاح».
--
-- (ملاحظة: التكرار ده مختلف تماماً عن نداء «never mind» اللي القاعدة
-- الخامسة بتمنعه. هناك بنصرف قناة لازم تفضل ليها معنى عشان نلغي كلام
-- قلناه. هنا بنقول نفس الكلام الصح مرتين.)

-- ====================================================== ١) مهلة إعادة الحجز
--
-- **لازم تكون أطول من أقصى عمر للدالة السحابية.** لو قصّرناها، إرسال
-- بطيء **وهو لسه عايش** بياخد حجز تاني من تشغيلة جاية، والابن بيتنبّه
-- مرتين من غير ما يموت حد — يعني بنصنع التكرار اللي فوق بإيدينا في
-- الحالة العادية بدل ما يفضل حالة نادرة وقت الأعطال.
--
-- Edge Function عمرها بالثواني مش بالدقايق، فخمس دقايق فيها مساحة واسعة
-- وبرضه بتخلّي الجرعة تتنبّه عليها في نفس الساعة. **ما تقصّرهاش لدقيقة**
-- عشان «الرد أسرع» — الرقم ده مش عن السرعة، هو عن التأكد إن اللي
-- بنستبدله ميّت فعلاً.
create or replace function private.escalation_retry_after()
returns interval
language sql immutable
set search_path = ''
as $$ select interval '5 minutes' $$;

-- ================================================ ٢) الاختيار بيشوف البايت
-- نفس التعريف الواحد، بشرط واحد اتوسّع: الصف بيمنع التنبيه لو حالته
-- نهائية، **أو** لو الحجز لسه طازة. حجز بايت ما بقاش بيمنع.
create or replace function private.due_escalations(p_limit integer default 200)
returns table (
  dose_event_uuid uuid,
  patient_uuid    uuid,
  patient_name    text,
  medication_name text,
  scheduled_at    timestamptz,
  caregiver_id    uuid
)
language sql stable security definer
set search_path = ''
as $$
  select ev.uuid,
         p.uuid,
         p.name,
         m.name,
         ev.scheduled_at,
         cr.caregiver_id
  from public.dose_events ev
  join public.dose_schedules s on s.uuid = ev.dose_schedule_uuid
  join public.medications    m on m.uuid = s.medication_uuid
  join public.patients       p on p.uuid = m.patient_uuid
  join public.care_relationships cr
       on cr.patient_uuid = p.uuid
      and cr.status = 'accepted'
  where ev.state = 'pending'
    and ev.scheduled_at <= now() - private.server_grace_window()
    and ev.scheduled_at >  now() - interval '2 days'
    and m.stopped_at is null
    and not exists (
      select 1
      from public.escalations e
      where e.dose_event_uuid = ev.uuid
        and e.caregiver_id    = cr.caregiver_id
        and e.rung            = 'caregiver'
        and (
          -- قرار اتكتب — مش بنلمسه تاني مهما طال الزمن
          e.delivery_status <> 'claimed'
          -- أو حجز لسه شغّال، سيبه لصاحبه
          or e.created_at > now() - private.escalation_retry_after()
        )
    )
  order by ev.scheduled_at
  limit p_limit;
$$;

-- ================================================== ٣) الحجز عملية واحدة
--
-- ليه دالة بدل `insert` عادي: الدالة السحابية كانت بتحجز بـinsert
-- وبتعتبر 409 «اتنبّه خلاص» وتعدّي. مع إعادة المحاولة ده كان هيخلّي
-- الإصلاح كله بلا أثر — الصف البايت يترشّح، والـinsert يقع، والدالة
-- تعدّي عليه زي ما كانت.
--
-- `on conflict ... do update ... where` بيخلّي الأخد ذرّي: تشغيلتين
-- بيتسابقوا، واحدة بس بتخرج بصف، والتانية بترجع فاضية وبتعدّي. مفيش
-- قراءة قبل كتابة، فمفيش فُرجة بينهم.
--
-- بترجّع uuid الصف لو الحجز بقى بتاعنا، وnull لو حد تاني ماسكه بحجز
-- لسه طازة.
create or replace function public.claim_escalation_for_service(
  p_dose_event_uuid uuid,
  p_caregiver_id    uuid
)
returns uuid
language sql
security definer
set search_path = ''
as $$
  insert into public.escalations (dose_event_uuid, caregiver_id)
  values (p_dose_event_uuid, p_caregiver_id)
  on conflict (dose_event_uuid, caregiver_id, rung) do update
     set created_at      = now(),
         delivery_status = 'claimed',
         sent_at         = null,
         fcm_status      = null,
         fcm_response    = null
   where public.escalations.delivery_status = 'claimed'
     and public.escalations.created_at
         <= now() - private.escalation_retry_after()
  returning uuid;
$$;

revoke execute on function public.claim_escalation_for_service(uuid, uuid)
  from anon, authenticated, public;
grant  execute on function public.claim_escalation_for_service(uuid, uuid)
  to service_role;
