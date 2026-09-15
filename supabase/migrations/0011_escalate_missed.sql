-- 0011_escalate_missed.sql — السيرفر بيصعّد على «اتنست» زي «لسه».
--
-- ------------------------------------------------------------------ العطل
--
-- `private.due_escalations` (0006، ثم 0009) كانت بتختار `state = 'pending'`
-- بس، على أساس إن «اتنست» قرار اتكتب خلاص. بس الجهاز هو اللي بيكتبه:
-- `sweepMissed` بيعلّم الجرعة `missed` عند +٤٥ في أي صحوة — المريض فتح
-- التطبيق، أو داس على إشعار جرعة تانية — والمزامنة بتطلّعه للسحابة في
-- ثواني. عند +٦٠ السيرفر ما بيلاقيش صف `pending`، ومحدش بيبلّغ الابن.
--
-- ودي مش حالة نادرة: الموبايل في إيد صاحبه، فالصحوة بين +٤٥ و+٦٠ هي
-- الغالبة. يعني سلّم التصعيد كله كان بيسكت في أكتر حالة بيحصل فيها.
--
-- --------------------------------------------------------------- العلاج
--
-- `pending` و`missed` الاتنين معناهم «ما اتأخدتش». الفرق بينهم مين علّم
-- الصف (محدش لسه / الجهاز بعد مهلته)، مش حالة مختلفة. فالاختيار بياخد
-- الاتنين. التعليقات في 0006 و0009 اللي بتقول غير كده **اتلغى معناها
-- بالملف ده** — ما اتعدّلتش لأن ملفات الترحيل تاريخ.
--
-- `taken` و`skipped` و`superseded` مستبعدين زي ما هم: الأولى تأكيد
-- (القاعدة الخامسة)، والتانية قرار إنسان مش نسيان، والتالتة جرعة القاعدة
-- بتاعتها اتغيّرت (0010).
--
-- التكرار متغطّي من غير أي تغيير هنا: التنبيه مربوط بـ`dose_event_uuid`،
-- والمزامنة بتحدّث نفس الصف (upsert على uuid) لما يتقلب من pending لـmissed.
-- فـ`unique (dose_event_uuid, caregiver_id, rung)` + شرط
-- `claim_escalation_for_service` (بياخد صف `claimed` بايت بس) بيمنعوا
-- إرسال تاني. `tests/escalation_test.sql` بيثبت ده.
--
-- **التعريف تحت هو نص 0009 بالحرف** — التغيير الوحيد سطر الحالة.
-- `claim_escalation_for_service` و`escalation_retry_after` والغلاف العام
-- `due_escalations_for_service` (0007، بينادي دي) ما اتلمسوش.
--
-- متكرر بأمان: `create or replace`، والتأكيد في الآخر ما بيسيبش أثر.

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
  -- 0011: «ما اتأخدتش» ليها اسمين. pending = لسه محدش علّمه؛ missed = الجهاز
  -- علّمه بعد مهلته (+٤٥). نفس الواقعة، والفرق مين كتب الصف.
  where ev.state in ('pending', 'missed')
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

-- `create or replace` بيحافظ على الصلاحيات؛ بنأكّدها برضه عشان الملف
-- يبقى صحيح لوحده.
revoke execute on function private.due_escalations(integer) from anon, public, authenticated;
grant  execute on function private.due_escalations(integer) to service_role;

-- ================================================================ تأكيد
-- بيانات مؤقتة جوّه sub-transaction: `missed` مستحق، والتلاتة التانيين لأ.
-- في الآخر بنرمي استثناء مقصود عشان كل الإدخالات تترجع؛ أي FAIL بيعدّي.
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_son   uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_med   uuid := gen_random_uuid();
  r record;
  v_sched uuid;
  v_event uuid;
  v_due   boolean;
begin
  begin
    insert into auth.users (id, email) values
      (v_owner, 'owner-' || v_owner || '@0011.check'),
      (v_son,   'son-'   || v_son   || '@0011.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0011');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, '0011');

    for r in
      select * from (values
        ('missed', true), ('pending', true),
        ('taken', false), ('skipped', false), ('superseded', false)
      ) as t(st, should_be_due)
    loop
      v_sched := gen_random_uuid();
      v_event := gen_random_uuid();
      insert into public.dose_schedules
        (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
        values (v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date - 7);
      insert into public.dose_events
        (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
        values (v_event, v_sched, current_date, now() - interval '61 minutes', r.st);
      v_due := exists (select 1 from private.due_escalations(100000) d
                       where d.dose_event_uuid = v_event);
      if v_due <> r.should_be_due then
        raise exception 'FAIL 0011: صف % — مستحق=% والمفروض %', r.st, v_due, r.should_be_due;
      end if;
    end loop;

    raise exception '0011_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0011_ROLLBACK' then
      raise;
    end if;
  end;
  raise notice '0011 OK — missed بيتصعّد، وtaken/skipped/superseded لأ';
end $$;
