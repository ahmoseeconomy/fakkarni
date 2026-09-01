-- rls_test.sql — إثبات المنع قبل السماح. يعمل داخل معاملة ويُرجَع كله
-- في النهاية (ROLLBACK) — قابل للإعادة، لا يترك أثراً.
--
-- التشغيل: محرر SQL في Supabase (بدور postgres). كل تأكيد داخل DO يرمي
-- استثناءً عند الفشل، فالسكربت إمّا يطبع ALL RLS TESTS PASSED أو يقف.

begin;

-- ------------------------------------------------ مستخدمان مؤقتان مباشرة
insert into auth.users (id, email)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'user-a@rls.test'),
       ('bbbbbbbb-0000-0000-0000-000000000002', 'user-b@rls.test');

-- محاكاة عميل PostgREST: دور authenticated + مطالبات JWT فيها sub
create or replace procedure pg_temp.act_as(user_id text)
language plpgsql
as $$
begin
  execute 'set local role authenticated';
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

-- ------------------------------------------------ «أ» ينشئ بياناته كعميل
call pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');

insert into public.patients (uuid, owner_id, name)
values ('11111111-1111-1111-1111-111111111111',
        'aaaaaaaa-0000-0000-0000-000000000001', 'الحاج أحمد');

insert into public.day_routines
  (uuid, patient_uuid, wake_minutes, breakfast_minutes, lunch_minutes,
   dinner_minutes, sleep_minutes)
values ('22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111', 420, 450, 870, 1200, 1410);

insert into public.medications (uuid, patient_uuid, name, amount_label)
values ('33333333-3333-3333-3333-333333333333',
        '11111111-1111-1111-1111-111111111111', 'Concor 5mg', 'قرص واحد');

insert into public.dose_schedules
  (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
values ('44444444-4444-4444-4444-444444444444',
        '33333333-3333-3333-3333-333333333333',
        'anchor', 'breakfast', -30, 'daily', '2026-08-31');

insert into public.dose_events
  (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
values ('55555555-5555-5555-5555-555555555555',
        '44444444-4444-4444-4444-444444444444',
        '2026-08-31', '2026-08-31 07:00+02', 'taken');

-- «أ» يرى بياناته — لو السياسات كتمت المالك نفسه، نعرف حالاً
do $$
begin
  if (select count(*) from public.patients)    <> 1 or
     (select count(*) from public.medications) <> 1 or
     (select count(*) from public.dose_events) <> 1 then
    raise exception 'FAIL: المالك نفسه لا يرى بياناته';
  end if;
end $$;

-- ------------------------------------------------ «ب» غريب: صفر في كل شيء
call pg_temp.act_as('bbbbbbbb-0000-0000-0000-000000000002');

do $$
begin
  if (select count(*) from public.patients)           <> 0 then raise exception 'FAIL: ب يرى مرضى أ'; end if;
  if (select count(*) from public.day_routines)       <> 0 then raise exception 'FAIL: ب يرى روتين أ'; end if;
  if (select count(*) from public.medications)        <> 0 then raise exception 'FAIL: ب يرى أدوية أ'; end if;
  if (select count(*) from public.dose_schedules)     <> 0 then raise exception 'FAIL: ب يرى جداول أ'; end if;
  if (select count(*) from public.dose_events)        <> 0 then raise exception 'FAIL: ب يرى أحداث أ'; end if;
  if (select count(*) from public.care_relationships) <> 0 then raise exception 'FAIL: ب يرى علاقات ليست له'; end if;
end $$;

-- «ب» يحاول UPDATE/DELETE على صفوف «أ» → صفر صفوف متأثرة
do $$
declare n integer;
begin
  update public.medications set name = 'HACKED' where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: ب عدّل أدوية أ (% صف)', n; end if;

  delete from public.dose_events where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: ب حذف أحداث أ (% صف)', n; end if;

  update public.patients set name = 'HACKED' where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: ب عدّل مريض أ'; end if;
end $$;

-- «ب» يحاول إدخال دواء تحت مريض «أ» → ترفضه WITH CHECK (SQLSTATE 42501)
do $$
begin
  insert into public.medications (uuid, patient_uuid, name)
  values (gen_random_uuid(),
          '11111111-1111-1111-1111-111111111111', 'Poison');
  raise exception 'FAIL: إدخال ب تحت مريض أ كان يجب أن يُرفض';
exception
  when insufficient_privilege then null;  -- المطلوب بالظبط
end $$;

-- ------------------------------------------------ anon: لا شيء في أي مكان
-- الامتيازات نفسها مسحوبة من anon، فالمحاولة ترمي permission denied —
-- أقوى من «صفر صفوف»، وكلاهما نجاح هنا.
reset role;
set local role anon;

do $$
declare n integer;
begin
  begin
    select count(*) into n from public.patients;
    if n <> 0 then raise exception 'FAIL: anon يرى مرضى'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into n from public.medications;
    if n <> 0 then raise exception 'FAIL: anon يرى أدوية'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into n from public.dose_events;
    if n <> 0 then raise exception 'FAIL: anon يرى أحداث'; end if;
  exception when insufficient_privilege then null;
  end;
end $$;

-- ------------------------------- علاقة رعاية accepted: قراءة نعم، كتابة لا
-- لا توجد سياسة INSERT على care_relationships هذه الجولة، فنزرعها كمشرف
reset role;
insert into public.care_relationships (patient_uuid, caregiver_id, status)
values ('11111111-1111-1111-1111-111111111111',
        'bbbbbbbb-0000-0000-0000-000000000002', 'accepted');

call pg_temp.act_as('bbbbbbbb-0000-0000-0000-000000000002');

do $$
declare n integer;
begin
  if (select count(*) from public.patients)    <> 1 then raise exception 'FAIL: مقدّم الرعاية accepted لا يقرأ المريض'; end if;
  if (select count(*) from public.medications) <> 1 then raise exception 'FAIL: accepted لا يقرأ الأدوية'; end if;
  if (select count(*) from public.dose_events) <> 1 then raise exception 'FAIL: accepted لا يقرأ الأحداث'; end if;
  if (select count(*) from public.care_relationships) <> 1 then raise exception 'FAIL: accepted لا يرى علاقته'; end if;

  -- وما زال ممنوعاً من الكتابة — قراءة فقط هذه الجولة
  update public.medications set name = 'HACKED' where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: accepted عدّل أدوية'; end if;

  update public.care_relationships set status = 'accepted' where true;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: مقدّم الرعاية عدّل status — هذا حق المالك وحده'; end if;
end $$;

do $$
begin
  insert into public.dose_events (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
  values (gen_random_uuid(), '44444444-4444-4444-4444-444444444444',
          '2026-09-01', '2026-09-01 07:00+02', 'taken');
  raise exception 'FAIL: accepted أدخل حدث جرعة — الكتابة تأتي مع التصعيد فقط';
exception when insufficient_privilege then null;
end $$;

-- pending ثم revoked → يرجع صفراً
reset role;
update public.care_relationships set status = 'pending'
where caregiver_id = 'bbbbbbbb-0000-0000-0000-000000000002';

call pg_temp.act_as('bbbbbbbb-0000-0000-0000-000000000002');
do $$
begin
  if (select count(*) from public.patients)    <> 0 then raise exception 'FAIL: pending يقرأ المريض'; end if;
  if (select count(*) from public.medications) <> 0 then raise exception 'FAIL: pending يقرأ الأدوية'; end if;
end $$;

reset role;
update public.care_relationships set status = 'revoked'
where caregiver_id = 'bbbbbbbb-0000-0000-0000-000000000002';

call pg_temp.act_as('bbbbbbbb-0000-0000-0000-000000000002');
do $$
begin
  if (select count(*) from public.patients)    <> 0 then raise exception 'FAIL: revoked يقرأ المريض'; end if;
  if (select count(*) from public.dose_events) <> 0 then raise exception 'FAIL: revoked يقرأ الأحداث'; end if;
end $$;

reset role;
select 'ALL RLS TESTS PASSED';

rollback;
