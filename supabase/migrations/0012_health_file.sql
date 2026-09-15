-- 0012_health_file.sql — الملف الصحي في السحابة (D5.1).
--
-- ليه: شاشة الابن اتبنت على medications وdose_events بس. السجلات والقياسات
-- والتحاليل وأسئلة الدكتور وبيانات الطوارئ كانت جداول محلية على موبايل
-- الأب — مفيش ليها مكان هنا، فالابن مستحيل يشوفها (design/PHASE_D5.md).
-- الملف ده الجداول والسياسات بس؛ الدفع في SyncService، والواجهة في D5.2.
--
-- القواعد اللي ماشي عليها:
--   * RLS على كل جدول، و`anon` مالوش ولا امتياز.
--   * كل قراءة بتمرّ من `private.can_access_patient` — نقطة تحقّق واحدة.
--   * الكتابة للمالك بس (`private.owns_patient`). الابن مالوش سطر كتابة.
--   * **سياسة جدول ما تنادي دالة بتقرا نفس الجدول** (درس 0005): سياسات
--     `records` بتقارن `patient_uuid` بتاعها مباشرة؛ `patient_of_record`
--     بتستعملها `lab_results` بس.
--
-- اللي **مش** هنا عن قصد:
--   * `emergency_profile.contacts_json` — أسماء وأرقام تليفونات. السيرفر لسه
--     ما بيشيلش ولا رقم تليفون (CLAUDE.md)، والابن محتاج فصيلة الدم
--     والحساسية بس. رفع الأرقام قرار خصوصية لوحده.
--   * `records.attachment_path` — مسار ملف على موبايل الأب، مالوش معنى هنا.
--     الصور بتيجي في D5.3 بمفتاح تخزين.
--
-- **الحذف الناعم وعده ٣٠ يوم — هنا كمان.** الشاشة بتقول «هيتمسح نهائي بعد
-- ٣٠ يوم». المسح المحلي ما بيوصلش السحابة (المزامنة مفيهاش مسح)، فمن غير
-- القسم ٥ الصف بمحتواه كان هيفضل هنا للأبد والوعد يبقى كدب للمريض المربوط.
-- `private.record_retention()` مرآة `RecordsRepository.retentionDays` في
-- دارت، و`test/data/sync/record_retention_sql_test.dart` بيقع لو واحد اتحرك.
--
-- متكرر بأمان: `if not exists` / `create or replace` / `drop ... if exists`،
-- والتأكيد في الآخر ما بيسيبش أثر.

-- ================================================================ ١) الجداول
create table if not exists public.records (
  uuid                uuid primary key,
  patient_uuid        uuid not null references public.patients (uuid) on delete cascade,
  kind                text not null check (kind in ('imaging', 'visit', 'lab', 'prescription', 'booking')),
  title               text not null check (char_length(title) between 1 and 200),
  happened_at         timestamptz not null,
  doctor              text,
  place               text,
  notes               text,
  -- الحذف الناعم بيتدفع: الابن بيفلتره، والقسم ٥ بيمسحه بعد ٣٠ يوم
  deleted_at          timestamptz,
  checkup_stage       integer check (checkup_stage between 1 and 7),
  fasting_reminder_at timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists records_patient_idx on public.records (patient_uuid);

create table if not exists public.readings (
  uuid         uuid primary key,
  patient_uuid uuid not null references public.patients (uuid) on delete cascade,
  value_mg_dl  integer not null,
  measured_at  timestamptz not null,
  context      text not null check (context in ('fasting', 'afterMeal')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists readings_patient_idx on public.readings (patient_uuid);

create table if not exists public.lab_results (
  uuid        uuid primary key,
  record_uuid uuid not null references public.records (uuid) on delete cascade,
  test_name   text not null check (char_length(test_name) between 1 and 120),
  value       double precision not null,
  unit        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists lab_results_record_idx on public.lab_results (record_uuid);

create table if not exists public.visit_questions (
  uuid          uuid primary key,
  patient_uuid  uuid not null references public.patients (uuid) on delete cascade,
  body          text not null check (char_length(body) between 1 and 500),
  -- لحظة ما السؤال اتكتب على موبايل الأب (`created_at` المحلي) — بيانات،
  -- مش وقت الوصول. اسمه مختلف عشان `created_at` هنا بتاع السيرفر.
  written_at    timestamptz not null,
  asked         boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists visit_questions_patient_idx on public.visit_questions (patient_uuid);

create table if not exists public.emergency_profile (
  uuid               uuid primary key,
  patient_uuid       uuid not null unique references public.patients (uuid) on delete cascade,
  -- null = «لسه ما اتملاش» — مفيش فصيلة افتراضية هنا كمان
  blood_type         text check (blood_type in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  allergies          text,
  chronic_conditions text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- updated_at من السيرفر زي 0004 — «الجديد» عند الابن بيترتّب بلحظة الوصول
create extension if not exists moddatetime;
drop trigger if exists set_updated_at on public.records;
create trigger set_updated_at before update on public.records for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.readings;
create trigger set_updated_at before update on public.readings for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.lab_results;
create trigger set_updated_at before update on public.lab_results for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.visit_questions;
create trigger set_updated_at before update on public.visit_questions for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.emergency_profile;
create trigger set_updated_at before update on public.emergency_profile for each row execute procedure moddatetime (updated_at);

-- ==================================================================== ٢) RLS
alter table public.records           enable row level security;
alter table public.readings          enable row level security;
alter table public.lab_results       enable row level security;
alter table public.visit_questions   enable row level security;
alter table public.emergency_profile enable row level security;

revoke all on public.records,
              public.readings,
              public.lab_results,
              public.visit_questions,
              public.emergency_profile
  from anon, public;

-- ============================================================ ٣) المُصعِّد
-- سطر التحليل مالوش patient_uuid — بيتوصل لمريضه من سجله. نفس شكل
-- patient_of_medication بالظبط.
create or replace function private.patient_of_record(r_uuid uuid)
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select r.patient_uuid from public.records r where r.uuid = r_uuid;
$$;

revoke execute on function private.patient_of_record(uuid) from anon, public;
grant  execute on function private.patient_of_record(uuid) to authenticated;

-- ============================================================ ٤) السياسات
-- ------------------------------------------------------------------ records
drop policy if exists records_select on public.records;
create policy records_select on public.records
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

drop policy if exists records_insert on public.records;
create policy records_insert on public.records
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

drop policy if exists records_update on public.records;
create policy records_update on public.records
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

drop policy if exists records_delete on public.records;
create policy records_delete on public.records
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- ----------------------------------------------------------------- readings
drop policy if exists readings_select on public.readings;
create policy readings_select on public.readings
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

drop policy if exists readings_insert on public.readings;
create policy readings_insert on public.readings
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

drop policy if exists readings_update on public.readings;
create policy readings_update on public.readings
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

drop policy if exists readings_delete on public.readings;
create policy readings_delete on public.readings
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- -------------------------------------------------------------- lab_results
drop policy if exists lab_results_select on public.lab_results;
create policy lab_results_select on public.lab_results
  for select to authenticated
  using (private.can_access_patient(private.patient_of_record(record_uuid)));

drop policy if exists lab_results_insert on public.lab_results;
create policy lab_results_insert on public.lab_results
  for insert to authenticated
  with check (private.owns_patient(private.patient_of_record(record_uuid)));

drop policy if exists lab_results_update on public.lab_results;
create policy lab_results_update on public.lab_results
  for update to authenticated
  using (private.owns_patient(private.patient_of_record(record_uuid)))
  with check (private.owns_patient(private.patient_of_record(record_uuid)));

drop policy if exists lab_results_delete on public.lab_results;
create policy lab_results_delete on public.lab_results
  for delete to authenticated
  using (private.owns_patient(private.patient_of_record(record_uuid)));

-- ---------------------------------------------------------- visit_questions
drop policy if exists visit_questions_select on public.visit_questions;
create policy visit_questions_select on public.visit_questions
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

drop policy if exists visit_questions_insert on public.visit_questions;
create policy visit_questions_insert on public.visit_questions
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

drop policy if exists visit_questions_update on public.visit_questions;
create policy visit_questions_update on public.visit_questions
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

drop policy if exists visit_questions_delete on public.visit_questions;
create policy visit_questions_delete on public.visit_questions
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- -------------------------------------------------------- emergency_profile
drop policy if exists emergency_profile_select on public.emergency_profile;
create policy emergency_profile_select on public.emergency_profile
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

drop policy if exists emergency_profile_insert on public.emergency_profile;
create policy emergency_profile_insert on public.emergency_profile
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

drop policy if exists emergency_profile_update on public.emergency_profile;
create policy emergency_profile_update on public.emergency_profile
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

drop policy if exists emergency_profile_delete on public.emergency_profile;
create policy emergency_profile_delete on public.emergency_profile
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- ================================================ ٥) وعد الـ٣٠ يوم في السحابة
-- المكان الوحيد اللي فيه الـ٣٠ في SQL — مرآة retentionDays في دارت.
create or replace function private.record_retention()
returns interval
language sql immutable
set search_path = ''
as $$ select interval '30 days' $$;

-- سجل اتمسح ناعم من أكتر من ٣٠ يوم بيتمسح نهائي، وسطور تحاليله معاه
-- (cascade). نفس اللي `purgeDeleted` بيعمله على موبايل الأب.
create or replace function private.purge_deleted_records()
returns integer
language plpgsql security definer
set search_path = ''
as $$
declare v_count integer;
begin
  delete from public.records
   where deleted_at is not null
     and deleted_at < now() - private.record_retention();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function private.record_retention(),
                           private.purge_deleted_records()
  from anon, public, authenticated;

select cron.unschedule('fakkarni-purge-records')
where exists (select 1 from cron.job where jobname = 'fakkarni-purge-records');

select cron.schedule(
  'fakkarni-purge-records',
  '17 3 * * *',
  $job$select private.purge_deleted_records()$job$
);

-- ================================================================ ٦) تأكيد
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود بيرجّع كل
-- حاجة. أي FAIL بيعدّي لبرّه.
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_rec      uuid := gen_random_uuid();
  v_old      uuid := gen_random_uuid();
  v_recent   uuid := gen_random_uuid();
  v_lab      uuid := gen_random_uuid();
  v_count    integer;
  t          text;
begin
  -- الهيكل: RLS شغّال على الخمسة، وأربع سياسات لكل واحد
  foreach t in array array['records', 'readings', 'lab_results', 'visit_questions', 'emergency_profile'] loop
    if not (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname = t) then
      raise exception 'FAIL 0012: RLS مش شغّال على %', t;
    end if;
    select count(*) into v_count from pg_policies where schemaname = 'public' and tablename = t;
    if v_count <> 4 then
      raise exception 'FAIL 0012: % عليه % سياسات والمفروض ٤', t, v_count;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'emergency_profile'
               and column_name = 'contacts_json') then
    raise exception 'FAIL 0012: أرقام تليفونات الطوارئ ليها عمود في السحابة';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'records'
               and column_name = 'attachment_path') then
    raise exception 'FAIL 0012: مسار ملف محلي ليه عمود في السحابة';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0012.check'),
      (v_son,      'son-'      || v_son      || '@0012.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0012.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0012');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');
    insert into public.records (uuid, patient_uuid, kind, title, happened_at, deleted_at) values
      (v_rec,    v_pat, 'lab', 'CBC',   now(), null),
      (v_old,    v_pat, 'visit', 'قديم', now(), now() - interval '31 days'),
      (v_recent, v_pat, 'visit', 'قريب', now(), now() - interval '29 days');
    insert into public.lab_results (uuid, record_uuid, test_name, value, unit)
      values (v_lab, v_old, 'HbA1c', 7.1, '%');

    if private.patient_of_record(v_rec) <> v_pat then
      raise exception 'FAIL 0012: patient_of_record ما وصلش للمريض';
    end if;

    -- الابن بيقرا (سجل + سطر تحليل عبر المُصعِّد)، والغريب لأ، والابن ما بيكتبش
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_son, 'role', 'authenticated')::text, true);
    select count(*) into v_count from public.records where patient_uuid = v_pat;
    if v_count <> 3 then
      raise exception 'FAIL 0012: الابن شاف % سجلات والمفروض ٣', v_count;
    end if;
    if not exists (select 1 from public.lab_results where uuid = v_lab) then
      raise exception 'FAIL 0012: الابن ما شافش سطر التحليل';
    end if;
    update public.records set title = 'الابن عدّل' where uuid = v_rec;
    get diagnostics v_count = row_count;
    if v_count <> 0 then
      raise exception 'FAIL 0012: الابن قدر يعدّل سجل أبوه';
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger, 'role', 'authenticated')::text, true);
    select count(*) into v_count from public.records where patient_uuid = v_pat;
    if v_count <> 0 then
      raise exception 'FAIL 0012: غريب شاف % سجلات', v_count;
    end if;
    reset role;

    -- الـ٣٠ يوم: ٣١ بيتمسح (وسطر تحليله معاه)، ٢٩ بيفضل، واللي مش ممسوح بيفضل
    perform private.purge_deleted_records();
    if exists (select 1 from public.records where uuid = v_old) then
      raise exception 'FAIL 0012: سجل ممسوح من ٣١ يوم لسه موجود';
    end if;
    if exists (select 1 from public.lab_results where uuid = v_lab) then
      raise exception 'FAIL 0012: سطر تحليل سجل ممسوح لسه موجود';
    end if;
    if not exists (select 1 from public.records where uuid = v_recent)
       or not exists (select 1 from public.records where uuid = v_rec) then
      raise exception 'FAIL 0012: المسح شال سجل لسه في مهلته';
    end if;

    raise exception '0012_ROLLBACK';
  exception when raise_exception then
    reset role;
    if sqlerrm <> '0012_ROLLBACK' then
      raise;
    end if;
  end;

  if not exists (select 1 from cron.job where jobname = 'fakkarni-purge-records') then
    raise exception 'FAIL 0012: مهمة المسح اليومية مش متجدولة';
  end if;
  raise notice '0012 OK — الملف الصحي في السحابة، الابن بيقرا بس، والـ٣٠ يوم متجدولة';
end $$;
