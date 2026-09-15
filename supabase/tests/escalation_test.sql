-- escalation_test.sql — استعلام الاختيار مُثبَتاً **قبل** وجود أي كود إرسال.
--
-- الترتيب ده مقصود. لو الدالة السحابية اتكتبت الأول، الاختبار الوحيد
-- المتاح بيبقى «شغّلها وشوف»، والفشل بيظهر كإنذار كاذب على موبايل ابن —
-- مش كخط أحمر في محرر SQL. كل قرار «مين يستاهل تنبيه» بيتقفل هنا وبس.
--
-- الاختبار بينادي `private.due_escalations()` نفسها اللي الكرون والدالة
-- السحابية بينادوها. مفيش نسخة من الاستعلام متكتوبة بالإيد هنا — لأن
-- ده بالظبط اللي خلّى `rls_test.sql` يعدّي على باج ٠٠٠٥: أثبت جملة
-- التطبيق عمره ما شغّلها.
--
-- التشغيل: محرر SQL في Supabase (دور postgres). البيانات بتتحط بدور
-- postgres عن قصد — RLS شغل `rls_test.sql`، والملف ده عن **الاختيار**.
-- بيطبع ALL ESCALATION TESTS PASSED أو بيقف عند أول فشل. ROLLBACK في
-- الآخر، فمفيش أثر.
--
-- ملاحظة عن الوقت: `now()` جوّه معاملة = لحظة بدايتها، ثابتة لحد
-- ROLLBACK. فكل المعادات تحت نسبية ليها والاختبار حتمي مش مرهون بسرعة
-- التنفيذ.

begin;

-- ==================================================== ١) الناس والبيانات
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'father-owner@esc.test'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'son@esc.test'),
  ('cccccccc-0000-0000-0000-00000000000c', 'lonely-owner@esc.test'),
  ('dddddddd-0000-0000-0000-00000000000d', 'second-son@esc.test');

-- مريض ١: ابنه مربوط ومقبول — الحالة الطبيعية
insert into public.patients (uuid, owner_id, name) values
  ('11111111-1111-1111-1111-111111111111',
   'aaaaaaaa-0000-0000-0000-00000000000a', 'الحاج أحمد'),
-- مريض ٢: مالكه مالوش ابن مربوط خالص
  ('22222222-2222-2222-2222-222222222222',
   'cccccccc-0000-0000-0000-00000000000c', 'الحاج سيد'),
-- مريض ٣: فيه علاقة بس لسه pending مش accepted
  ('33333333-3333-3333-3333-333333333333',
   'aaaaaaaa-0000-0000-0000-00000000000a', 'الحاجة فاطمة');

insert into public.care_relationships (patient_uuid, caregiver_id, status) values
  ('11111111-1111-1111-1111-111111111111',
   'bbbbbbbb-0000-0000-0000-00000000000b', 'accepted'),
  ('33333333-3333-3333-3333-333333333333',
   'bbbbbbbb-0000-0000-0000-00000000000b', 'pending');

insert into public.medications (uuid, patient_uuid, name, amount_label, stopped_at) values
  ('a1000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'Concor 5mg', 'قرص', null),
  -- دوا وقّفه إنسان بإيده
  ('a2000000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'Augmentin', 'قرص', now() - interval '1 day'),
  ('a3000000-0000-0000-0000-000000000003',
   '22222222-2222-2222-2222-222222222222', 'Glucophage', 'قرص', null),
  ('a4000000-0000-0000-0000-000000000004',
   '33333333-3333-3333-3333-333333333333', 'Aspocid', 'قرص', null);

-- جدول لكل حالة: مفتاح dose_events هو (schedule, routine_day)، فلو كل
-- الحالات على جدول واحد هتتصادم بدل ما تتقاس.
insert into public.dose_schedules
  (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
select v.uuid, v.med, 'anchor', 'breakfast', -30, 'daily', current_date - 7
from (values
  ('51000000-0000-0000-0000-000000000001'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-000000000002'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-000000000003'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-000000000004'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-000000000005'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-000000000006'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-000000000007'::uuid, 'a2000000-0000-0000-0000-000000000002'::uuid),
  ('51000000-0000-0000-0000-000000000008'::uuid, 'a3000000-0000-0000-0000-000000000003'::uuid),
  ('51000000-0000-0000-0000-000000000009'::uuid, 'a4000000-0000-0000-0000-000000000004'::uuid),
  ('51000000-0000-0000-0000-00000000000a'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-00000000000b'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-00000000000c'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid),
  ('51000000-0000-0000-0000-00000000000d'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid)
) as v(uuid, med);

-- --------------------------------------------------------- أحداث الجرعات
-- واحد بس من دول المفروض يتختار. الباقي كله أسباب مختلفة للرفض.
insert into public.dose_events
  (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
values
  -- ✔ مستحق: pending، عدّى ٦١ دقيقة، وابنه مربوط
  ('e1000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001',
   current_date, now() - interval '61 minutes', 'pending'),
  -- ✘ عدّى ٥٠ دقيقة بس — مهلة الجهاز (٤٥) خلصت، مهلة السيرفر (٦٠) لأ.
  --   الربع ساعة دي ميزانية السلك، مش تأخير للمريض.
  ('e2000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000002',
   current_date, now() - interval '50 minutes', 'pending'),
  -- ✘ الأب قال «أخدته» — القاعدة الخامسة، مفيش تنبيه بعد التأكيد
  ('e3000000-0000-0000-0000-000000000003', '51000000-0000-0000-0000-000000000003',
   current_date, now() - interval '61 minutes', 'taken'),
  -- ✘ من تلات أيام — بره نافذة الفحص المحدودة (تغطية السحابة يومين)
  ('e4000000-0000-0000-0000-000000000004', '51000000-0000-0000-0000-000000000004',
   current_date - 3, now() - interval '3 days', 'pending'),
  -- ✔ مستحق (0011): الجهاز علّمها «اتنست» عند +٤٥ واتزامنت قبل +٦٠. ده
  --   الغالب مش النادر — الموبايل في إيد صاحبه. pending وmissed الاتنين
  --   «ما اتأخدتش»؛ الفرق مين علّم الصف. (كان هنا ✘ «القرار اتاخد» — غلط:
  --   السلّم كان بيسكت في أكتر حالة بيحصل فيها.)
  ('e5000000-0000-0000-0000-000000000005', '51000000-0000-0000-0000-000000000005',
   current_date, now() - interval '61 minutes', 'missed'),
  -- ✘ «مش هاخده» — قرار إنسان، مش نسيان
  ('eb000000-0000-0000-0000-00000000000b', '51000000-0000-0000-0000-00000000000b',
   current_date, now() - interval '61 minutes', 'skipped'),
  -- ✘ الجهاز كتب «اتغيّرت القاعدة» (0010) — التوقيت اتعدّل والجرعة دي
  --   ما بقتش موجودة. تنبيه عليها إنذار كاذب عن حاجة اتشالت.
  ('ea000000-0000-0000-0000-00000000000a', '51000000-0000-0000-0000-00000000000a',
   current_date, now() - interval '61 minutes', 'superseded'),
  -- ✘ دوا متوقّف بقرار إنسان — تنبيه عليه إنذار كاذب بحكم التعريف
  ('e7000000-0000-0000-0000-000000000007', '51000000-0000-0000-0000-000000000007',
   current_date, now() - interval '61 minutes', 'pending'),
  -- ✘ مريض مالوش ابن مربوط — مفيش حد يتنبّه أصلاً
  ('e8000000-0000-0000-0000-000000000008', '51000000-0000-0000-0000-000000000008',
   current_date, now() - interval '61 minutes', 'pending'),
  -- ✘ العلاقة pending مش accepted — كود الدعوة ما اتستبدلش
  ('e9000000-0000-0000-0000-000000000009', '51000000-0000-0000-0000-000000000009',
   current_date, now() - interval '61 minutes', 'pending');

-- ============================ ٢) الاختيار: اتنين بالظبط، وبالسبب الصح
-- e1 (pending) وe5 (missed) — ولا حاجة تانية.
do $$
declare
  v_count integer;
  v_event uuid;
  v_care  uuid;
  v_name  text;
  v_med   text;
begin
  select count(*) into v_count from private.due_escalations();
  if v_count <> 2 then
    raise exception 'FAIL: المفروض صفين مستحقين (pending + missed)، جه %', v_count;
  end if;
  if exists (select 1 from private.due_escalations() d
             where d.dose_event_uuid not in ('e1000000-0000-0000-0000-000000000001',
                                             'e5000000-0000-0000-0000-000000000005')) then
    raise exception 'FAIL: اتختار حدث غير e1 وe5';
  end if;
  if not exists (select 1 from private.due_escalations() d
                 where d.dose_event_uuid = 'e5000000-0000-0000-0000-000000000005') then
    raise exception 'FAIL: صف missed ما اتصعّدش — السلّم ساكت في الحالة الغالبة';
  end if;

  select dose_event_uuid, caregiver_id, patient_name, medication_name
    into v_event, v_care, v_name, v_med
    from private.due_escalations() d
   where d.dose_event_uuid = 'e1000000-0000-0000-0000-000000000001';

  if v_event is null then
    raise exception 'FAIL: e1 (pending) ما اتختارش';
  end if;
  if v_care <> 'bbbbbbbb-0000-0000-0000-00000000000b' then
    raise exception 'FAIL: اتختار مقدّم رعاية غلط: %', v_care;
  end if;
  -- الاسمين دول بيروحوا في نص الإشعار لابنه؛ لو فاضيين الرسالة تبقى بلا معنى
  if v_name <> 'الحاج أحمد' or v_med <> 'Concor 5mg' then
    raise exception 'FAIL: الأسماء اللي هتتبعت غلط: % / %', v_name, v_med;
  end if;
end $$;

-- كل سبب رفض على حدة، عشان لو واحد اتكسر نعرف أنهي واحد
do $$
declare r record;
begin
  for r in
    select * from (values
      ('e2000000-0000-0000-0000-000000000002'::uuid, 'عدّى ٥٠ دقيقة بس'),
      ('e3000000-0000-0000-0000-000000000003'::uuid, 'الأب أكّد إنه أخدها'),
      ('e4000000-0000-0000-0000-000000000004'::uuid, 'بره نافذة اليومين'),
      ('eb000000-0000-0000-0000-00000000000b'::uuid, '«مش هاخده» قرار إنسان'),
      ('ea000000-0000-0000-0000-00000000000a'::uuid, 'القاعدة اتغيّرت'),
      ('e7000000-0000-0000-0000-000000000007'::uuid, 'دوا متوقّف'),
      ('e8000000-0000-0000-0000-000000000008'::uuid, 'مريض من غير ابن مربوط'),
      ('e9000000-0000-0000-0000-000000000009'::uuid, 'علاقة لسه pending')
    ) as t(uuid, why)
  loop
    if exists (select 1 from private.due_escalations() d
               where d.dose_event_uuid = r.uuid) then
      raise exception 'FAIL: اتختار وما كانش المفروض (%): %', r.why, r.uuid;
    end if;
  end loop;
end $$;

-- ================== ٢ب) missed بيتصعّد مرة واحدة بس (0011) — مفيش تكرار
-- التنبيه مربوط بـuuid الحدث، والمزامنة بتحدّث نفس الصف لما يتقلب من
-- pending لـmissed. فالـunique + شرط الحجز هما اللي بيمنعوا مرة تانية.
insert into public.dose_events
  (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
values
  -- اتعلّم missed عند +٥٠ — قبل مهلة السيرفر
  ('ec000000-0000-0000-0000-00000000000c', '51000000-0000-0000-0000-00000000000c',
   current_date, now() - interval '50 minutes', 'pending'),
  -- اتنبّه عليه وهو pending، وبعدين الجهاز علّمه missed
  ('ed000000-0000-0000-0000-00000000000d', '51000000-0000-0000-0000-00000000000d',
   current_date, now() - interval '61 minutes', 'pending');

do $$
declare v_count integer; v_first uuid; v_second uuid;
begin
  -- (أ) الجهاز علّمه missed عند +٥٠: لسه مش مستحق
  update public.dose_events set state = 'missed'
   where uuid = 'ec000000-0000-0000-0000-00000000000c';
  if exists (select 1 from private.due_escalations() d
             where d.dose_event_uuid = 'ec000000-0000-0000-0000-00000000000c') then
    raise exception 'FAIL: missed اتصعّد قبل مهلة السيرفر';
  end if;

  -- الوقت عدّى +٦٠: مستحق **مرة واحدة** للابن
  update public.dose_events set scheduled_at = now() - interval '61 minutes'
   where uuid = 'ec000000-0000-0000-0000-00000000000c';
  select count(*) into v_count from private.due_escalations() d
   where d.dose_event_uuid = 'ec000000-0000-0000-0000-00000000000c';
  if v_count <> 1 then
    raise exception 'FAIL: missed بعد +٦٠ المفروض صف واحد، جه %', v_count;
  end if;

  -- الدالة السحابية بتحجز — والاستعلام متنادي مرتين بعدها
  v_first := public.claim_escalation_for_service(
    'ec000000-0000-0000-0000-00000000000c', 'bbbbbbbb-0000-0000-0000-00000000000b');
  if v_first is null then
    raise exception 'FAIL: حجز missed ما اتاخدش';
  end if;
  for i in 1..2 loop
    if exists (select 1 from private.due_escalations() d
               where d.dose_event_uuid = 'ec000000-0000-0000-0000-00000000000c') then
      raise exception 'FAIL: missed اتصعّد تاني في النداء رقم % — التنبيه هيتكرر', i;
    end if;
  end loop;
  v_second := public.claim_escalation_for_service(
    'ec000000-0000-0000-0000-00000000000c', 'bbbbbbbb-0000-0000-0000-00000000000b');
  if v_second is not null then
    raise exception 'FAIL: missed اتحجز مرتين';
  end if;

  -- (ب) اتنبّه عليه وهو pending (اتبعت)، وبعدين اتقلب missed: ما يرجعش
  v_first := public.claim_escalation_for_service(
    'ed000000-0000-0000-0000-00000000000d', 'bbbbbbbb-0000-0000-0000-00000000000b');
  if v_first is null then
    raise exception 'FAIL: حجز pending ما اتاخدش';
  end if;
  update public.escalations set delivery_status = 'sent', sent_at = now()
   where dose_event_uuid = 'ed000000-0000-0000-0000-00000000000d';
  update public.dose_events set state = 'missed'
   where uuid = 'ed000000-0000-0000-0000-00000000000d';
  for i in 1..2 loop
    if exists (select 1 from private.due_escalations() d
               where d.dose_event_uuid = 'ed000000-0000-0000-0000-00000000000d') then
      raise exception 'FAIL: صف اتنبّه عليه وهو pending رجع مستحق لما بقى missed (نداء %)', i;
    end if;
  end loop;
  if public.claim_escalation_for_service(
       'ed000000-0000-0000-0000-00000000000d', 'bbbbbbbb-0000-0000-0000-00000000000b') is not null then
    raise exception 'FAIL: pending→missed اتحجز تاني بعد ما اتبعت';
  end if;
end $$;

-- الأقسام اللي جاية بتعدّ على e1 لوحده (الحجز، البايت، الأخ التاني) —
-- حالات missed اتثبتت فوق، فبتتشال هنا (التنبيهات بتتمسح معاها cascade).
delete from public.dose_events
 where uuid in ('e5000000-0000-0000-0000-000000000005',
                'ec000000-0000-0000-0000-00000000000c',
                'ed000000-0000-0000-0000-00000000000d');

-- ================================= ٣) الحدّ بالظبط: ٦٠ دقيقة = مستحقة
-- زي `isPastGrace` في دارت: عند الـ٤٥ بالظبط المهلة خلصت. نفس المنطق
-- هنا عند الـ٦٠ — الحدّ مش منطقة رمادية، وده مكتوب عشان محدش يقلب
-- `<=` لـ`<` وهو فاكر إنه بيظبّط حاجة.
insert into public.dose_events
  (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
values
  ('e6000000-0000-0000-0000-000000000006', '51000000-0000-0000-0000-000000000006',
   current_date, now() - interval '60 minutes', 'pending');

do $$
begin
  if not exists (select 1 from private.due_escalations() d
                 where d.dose_event_uuid = 'e6000000-0000-0000-0000-000000000006') then
    raise exception 'FAIL: الستين دقيقة بالظبط المفروض تبقى مستحقة';
  end if;
end $$;

delete from public.dose_events where uuid = 'e6000000-0000-0000-0000-000000000006';

-- ======================== ٤) التشغيلة التانية فاضية — الـunique هو الدليل
-- الدالة السحابية بتحجز التنبيه بإدخال الصف **قبل** ما تبعت. الإدخال ده
-- بالظبط هو اللي بيخرّج الحدث من الاختيار.
insert into public.escalations (dose_event_uuid, caregiver_id)
values ('e1000000-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-00000000000b');

do $$
declare v_count integer;
begin
  select count(*) into v_count from private.due_escalations();
  if v_count <> 0 then
    raise exception 'FAIL: التشغيلة التانية اختارت % صف — التنبيه هيتكرر', v_count;
  end if;
end $$;

-- ولو كرونان اتسابقوا على نفس الصف في نفس اللحظة، الـunique بيمسك
do $$
begin
  insert into public.escalations (dose_event_uuid, caregiver_id)
  values ('e1000000-0000-0000-0000-000000000001',
          'bbbbbbbb-0000-0000-0000-00000000000b');
  raise exception 'FAIL: اتكتب تنبيه مكرر لنفس (الحدث، الابن، الدرجة)';
exception when unique_violation then null;
end $$;

-- ===================== ٤ب) محاولة اتقطعت بترجع، وقرار اتكتب ما بيرجعش
-- الدالة السحابية بتحجز قبل ما تبعت. لو ماتت بين الاتنين، الصف بيفضل
-- `claimed` — ومن غير القسم ده الجرعة دي عمرها ما تتنبّه عليها تاني.
do $$
declare v_count integer;
begin
  -- حجز عمره دقيقتين: الدالة ممكن تكون **لسه شغّالة**. سيبها.
  update public.escalations set created_at = now() - interval '2 minutes'
   where dose_event_uuid = 'e1000000-0000-0000-0000-000000000001';
  select count(*) into v_count from private.due_escalations();
  if v_count <> 0 then
    raise exception 'FAIL: حجز عمره دقيقتين اتاخد تاني — ممكن يبعت مرتين وهو عايش';
  end if;

  -- حجز عمره ٦ دقايق: أطول من أقصى عمر للدالة. اللي ماسكه ميّت.
  update public.escalations set created_at = now() - interval '6 minutes'
   where dose_event_uuid = 'e1000000-0000-0000-0000-000000000001';
  select count(*) into v_count from private.due_escalations();
  if v_count <> 1 then
    raise exception 'FAIL: حجز بايت ما رجعش مستحق — الجرعة دي ضاعت للأبد';
  end if;
end $$;

do $$
declare r record; v_count integer;
begin
  for r in select unnest(array['sent', 'no_token', 'failed']) as st loop
    update public.escalations
       set delivery_status = r.st, created_at = now() - interval '6 minutes'
     where dose_event_uuid = 'e1000000-0000-0000-0000-000000000001';
    select count(*) into v_count from private.due_escalations();
    if v_count <> 0 then
      raise exception 'FAIL: صف حالته % اتاخد تاني — ده قرار اتكتب مش محاولة اتقطعت', r.st;
    end if;
  end loop;

  -- رجّعه حجز بايت عشان نختبر الأخد نفسه
  update public.escalations
     set delivery_status = 'claimed', created_at = now() - interval '6 minutes'
   where dose_event_uuid = 'e1000000-0000-0000-0000-000000000001';
end $$;

-- الأخد ذرّي: بيرجّع الصف لو بقى بتاعنا، وnull لو حد ماسكه بحجز طازة
do $$
declare v_first uuid; v_second uuid; v_count integer;
begin
  v_first := public.claim_escalation_for_service(
    'e1000000-0000-0000-0000-000000000001',
    'bbbbbbbb-0000-0000-0000-00000000000b');
  if v_first is null then
    raise exception 'FAIL: الحجز البايت ما اتاخدش';
  end if;

  -- الأخد بيصفّر العدّاد، فالصف بقى طازة تاني
  select count(*) into v_count from private.due_escalations();
  if v_count <> 0 then
    raise exception 'FAIL: بعد الأخد الصف لسه مستحق — تشغيلتين هياخدوه';
  end if;

  v_second := public.claim_escalation_for_service(
    'e1000000-0000-0000-0000-000000000001',
    'bbbbbbbb-0000-0000-0000-00000000000b');
  if v_second is not null then
    raise exception 'FAIL: اتاخد مرتين — السباق بين كرونين مش متأمّن';
  end if;
end $$;

-- ============================ ٥) التنبيه لكل ابن على حدة، مش لكل جرعة
-- عيلة فيها أخوين مربوطين: إن أخوه اتنبّه ما يمنعش تنبيهه هو. ده معنى
-- `unique (dose_event_uuid, caregiver_id, rung)` — العمود التاني جزء من
-- المفتاح مش زينة.
insert into public.care_relationships (patient_uuid, caregiver_id, status)
values ('11111111-1111-1111-1111-111111111111',
        'dddddddd-0000-0000-0000-00000000000d', 'accepted');

do $$
declare v_count integer; v_care uuid;
begin
  select count(*) into v_count from private.due_escalations();
  if v_count <> 1 then
    raise exception 'FAIL: الأخ التاني المفروض يستحق تنبيهه، جه % صف', v_count;
  end if;
  select caregiver_id into v_care from private.due_escalations();
  if v_care <> 'dddddddd-0000-0000-0000-00000000000d' then
    raise exception 'FAIL: المفروض الأخ اللي ما اتنبّهش، جه %', v_care;
  end if;
end $$;

-- =================================== ٦) مهلة السيرفر رقم واحد في مكان واحد
do $$
begin
  if private.server_grace_window() <> interval '60 minutes' then
    raise exception 'FAIL: مهلة السيرفر اتغيّرت في SQL: %',
      private.server_grace_window();
  end if;
end $$;
-- الناحية التانية من المرآة (نفس الرقم في دارت) بيمسكها
-- test/data/sync/server_grace_sql_test.dart — Postgres ما بيقراش دارت.

-- ================== ٧) الغلاف اللي الدالة السحابية بتناديه فعلاً (٠٠٠٧)
-- الدالة السحابية بتكلم PostgREST، و`private` مش مكشوفة ليه — فهي
-- بتنادي `public.due_escalations_for_service`، مش `private.due_escalations`.
-- لو الاختبار فحص الجوّانية بس، يبقى بيثبت جملة الدالة السحابية عمرها
-- ما شغّلتها. نفس درس ٠٠٠٥ بالحرف.
do $$
declare v_inner integer; v_outer integer;
begin
  select count(*) into v_inner from private.due_escalations();
  select count(*) into v_outer from public.due_escalations_for_service();
  if v_inner <> v_outer then
    raise exception 'FAIL: الغلاف والجوّانية بيختلفوا: % مقابل %', v_outer, v_inner;
  end if;
end $$;

-- ومستخدم عادي ما بيقدرش ينادي الغلاف — التصعيد مش حاجة يشغّلها عميل
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', 'bbbbbbbb-0000-0000-0000-00000000000b',
                      'role', 'authenticated')::text, true);
  perform public.due_escalations_for_service();
  reset role;
  raise exception 'FAIL: مستخدم مسجّل نادى استعلام التصعيد';
exception when insufficient_privilege then
  reset role;
end $$;

select 'ALL ESCALATION TESTS PASSED';

rollback;
