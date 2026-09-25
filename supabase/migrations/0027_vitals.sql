-- 0027_vitals.sql — القياسات الحيوية: الضغط والنبض والوزن والأكسجين والحرارة
-- (٢٥ سبتمبر ٢٠٢٦).
--
-- **ملف بس — ما اتطبّقش.** بعد 0026.
--
-- جدول لوحده جنب `readings` (السكر) — مش توسيع ليه: السكر ليه سياقه
-- وجدوله وشاشاته من ٠٠١٢، وتوسيعه كان هيغيّر شكل جدول شغّال عشان أعمدة
-- مالهاش معنى للسكر. نفس شكل `readings` بالظبط في كل حاجة تانية:
--   * المفتاح uuid اللي الموبايل عمله، و`patient_uuid` بمسح متتالي.
--   * `updated_at` من السيرفر (moddatetime **من غير سكيما** — درس ٠٠٢٠).
--   * RLS: المالك بس بيكتب، والدائرة كلها (عيلة وممرض) بتقرا عن طريق
--     `private.can_access_patient`. السياسات بتقرا `patient_uuid` بتاع الصف
--     نفسه — قاعدة ٠٠٠٥.
--   * **مفيش عمود حكم**: لا «طبيعي» ولا مدى مرجعي. رقم ووقت وبس.
--
-- كله idempotent.

create table if not exists public.vitals (
  uuid         uuid primary key,
  patient_uuid uuid not null references public.patients (uuid) on delete cascade,
  kind         text not null check (kind in ('bloodPressure', 'pulse', 'weight', 'spo2', 'temperature')),
  value        double precision not null,
  -- الانبساطي — للضغط بس
  value2       double precision,
  -- نبض اختياري مع الضغط
  pulse        integer,
  measured_at  timestamptz not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (kind = 'bloodPressure' or (value2 is null and pulse is null))
);
create index if not exists vitals_patient_idx on public.vitals (patient_uuid, measured_at desc);

drop trigger if exists set_updated_at on public.vitals;
create trigger set_updated_at before update on public.vitals
  for each row execute procedure moddatetime (updated_at);

alter table public.vitals enable row level security;
revoke all on public.vitals from anon, public;
grant select, insert, update, delete on public.vitals to authenticated;

drop policy if exists vitals_select on public.vitals;
create policy vitals_select on public.vitals
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

drop policy if exists vitals_insert on public.vitals;
create policy vitals_insert on public.vitals
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

drop policy if exists vitals_update on public.vitals;
create policy vitals_update on public.vitals
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

drop policy if exists vitals_delete on public.vitals;
create policy vitals_delete on public.vitals
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- ============================================================ فحص ذاتي
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_row      uuid := gen_random_uuid();
  v_back     uuid;
  v_n        integer;
  v_denied   boolean;
begin
  if to_regclass('public.vitals') is null then
    raise exception 'FAIL 0027: vitals مش موجود';
  end if;

  begin
    -- المالك في auth.users **قبل** المريض — درس ٠٠١٦
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0027.check'),
      (v_son,      'son-'      || v_son      || '@0027.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0027.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0027.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0027');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted'), (v_pat, v_nurse, 'accepted');
    -- الممرض بدوره لو ٠٠٢٣ اتشغّلت (العمود موجود)
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'care_relationships' and column_name = 'role') then
      execute 'update public.care_relationships set role = ''nurse'' where caregiver_id = $1' using v_nurse;
    end if;

    -- ١) المالك بيكتب — **بـRETURNING** زي التطبيق (درس ٠٠٠٥)
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into public.vitals (uuid, patient_uuid, kind, value, value2, pulse, measured_at)
      values (v_row, v_pat, 'bloodPressure', 130, 85, 72, now())
      returning uuid into v_back;
    if v_back is distinct from v_row then raise exception 'FAIL 0027: المالك ما كتبش'; end if;
    execute 'reset role';

    -- ٢) الابن والممرض بيقروا
    foreach v_back in array array[v_son, v_nurse] loop
      perform set_config('request.jwt.claims', json_build_object('sub', v_back)::text, true);
      execute 'set local role authenticated';
      select count(*) into v_n from public.vitals where patient_uuid = v_pat;
      if v_n <> 1 then raise exception 'FAIL 0027: الدائرة مش شايفة القياس (%)', v_n; end if;
      -- ٣) وما بيكتبوش
      v_denied := false;
      begin
        insert into public.vitals (uuid, patient_uuid, kind, value, measured_at)
          values (gen_random_uuid(), v_pat, 'pulse', 80, now());
      exception when insufficient_privilege then v_denied := true;
      end;
      if not v_denied then raise exception 'FAIL 0027: حد من الدائرة كتب قياس'; end if;
      update public.vitals set value = 1 where uuid = v_row;  -- RLS: صفر صف
      execute 'reset role';
    end loop;
    if (select value from public.vitals where uuid = v_row) <> 130 then
      raise exception 'FAIL 0027: حد من الدائرة عدّل قياس';
    end if;

    -- ٤) الغريب ما بيشوفش
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.vitals where patient_uuid = v_pat;
    if v_n <> 0 then raise exception 'FAIL 0027: غريب شاف القياسات (%)', v_n; end if;
    execute 'reset role';

    -- ٥) الانبساطي والنبض للضغط بس
    v_denied := false;
    begin
      insert into public.vitals (uuid, patient_uuid, kind, value, value2, measured_at)
        values (gen_random_uuid(), v_pat, 'weight', 72.5, 3, now());
    exception when check_violation then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0027: وزن برقم تاني عدّى'; end if;

    raise exception '0027_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0027_ROLLBACK' then raise; end if;
  end;

  raise notice '0027 OK — المالك بيكتب بـRETURNING، الابن والممرض بيقروا ومش بيكتبوا، والغريب ما بيشوفش';
end $$;
