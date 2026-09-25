-- 0028_medication_stock.sql — مخزون الأدوية («قرب يخلص») (٢٥ سبتمبر ٢٠٢٦).
--
-- **ملف بس — ما اتطبّقش.** بعد 0027.
--
-- **جدول لوحده، مش عمودين على `medications`.** المخزون بيتغيّر مع كل جرعة
-- بتتأكّد؛ عمود على صف الدوا كان هيرفع الصف كله مع كل جرعة، وكان هيحرّك
-- `updated_at` بتاعه — و«تعديل الأب المحلي بيكسب» في طلبات الممرض (٠٠٢٤)
-- بيقارن بالوقت ده بالظبط، يعني أي جرعة اتاخدت كانت هترمي طلب الممرض
-- المعلّق كتعارض. صف لكل دوا عنده مخزون؛ مفيش صف = المريض ما كتبش مخزون.
--
--   * المالك بس بيكتب (موبايله هو اللي بيعدّ)، والدائرة كلها بتقرا.
--   * الممرض اللي معاه `can_edit_meds` بيبعت «اشتريت علبة جديدة» كطلب
--     معلّق (`medication_changes.kind = 'restock'`) — موبايل المريض بيزوّده.
--   * مفيش حساب ولا حكم هنا: الكمية وحد التنبيه بالأيام، وبس.
--
-- كله idempotent.

create table if not exists public.medication_stock (
  uuid            uuid primary key,
  medication_uuid uuid not null unique references public.medications (uuid) on delete cascade,
  patient_uuid    uuid not null references public.patients (uuid) on delete cascade,
  quantity        double precision not null check (quantity >= 0),
  warn_days       integer check (warn_days between 1 and 60),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists medication_stock_patient_idx on public.medication_stock (patient_uuid);

drop trigger if exists set_updated_at on public.medication_stock;
create trigger set_updated_at before update on public.medication_stock
  for each row execute procedure moddatetime (updated_at);

alter table public.medication_stock enable row level security;
revoke all on public.medication_stock from anon, public;
grant select, insert, update, delete on public.medication_stock to authenticated;

drop policy if exists medication_stock_select on public.medication_stock;
create policy medication_stock_select on public.medication_stock
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

-- الكتابة للمالك، **والدوا لازم يبقى بتاع نفس المريض** — وإلا مالك يقدر
-- يلزّق مخزون على uuid دوا حد تاني.
drop policy if exists medication_stock_insert on public.medication_stock;
create policy medication_stock_insert on public.medication_stock
  for insert to authenticated
  with check (
    private.owns_patient(patient_uuid)
    and exists (select 1 from public.medications m
                where m.uuid = medication_uuid and m.patient_uuid = medication_stock.patient_uuid)
  );

drop policy if exists medication_stock_update on public.medication_stock;
create policy medication_stock_update on public.medication_stock
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (
    private.owns_patient(patient_uuid)
    and exists (select 1 from public.medications m
                where m.uuid = medication_uuid and m.patient_uuid = medication_stock.patient_uuid)
  );

drop policy if exists medication_stock_delete on public.medication_stock;
create policy medication_stock_delete on public.medication_stock
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- «اشتريت علبة جديدة» من الممرض — نفس جدول الطلبات المعلّقة
alter table public.medication_changes drop constraint if exists medication_changes_kind_check;
alter table public.medication_changes
  add constraint medication_changes_kind_check
  check (kind in ('add', 'stop', 'amount', 'record', 'appointment', 'restock'));

-- ============================================================ فحص ذاتي
-- **كله من خلال الجداول وRLS** — ولا نداء مباشر لدوال private تحت
-- `set local role authenticated` (مالوش USAGE على السكيما — 3f74e5c).
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_other    uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_other_med uuid := gen_random_uuid();
  v_stock    uuid := gen_random_uuid();
  v_back     uuid;
  v_who      uuid;
  v_n        integer;
  v_denied   boolean;
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'care_relationships'
                   and column_name = 'can_edit_meds') then
    raise exception 'FAIL 0028: شغّل 0023 الأول';
  end if;
  if to_regclass('public.family_subscriptions') is null then
    raise exception 'FAIL 0028: شغّل 0025 الأول';
  end if;

  begin
    -- المالك في auth.users **قبل** المريض — درس ٠٠١٦
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0028.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0028.check'),
      (v_son,      'son-'      || v_son      || '@0028.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0028.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0028');
    insert into public.patients (uuid, owner_id, name) values (v_other, v_stranger, '0028-other');
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.medications (uuid, patient_uuid, name) values (v_other_med, v_other, 'Other');
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
      values (v_pat, v_nurse, 'accepted', 'nurse', true, true),
             (v_pat, v_son,   'accepted', 'follower', false, false);

    -- ١) المالك بيكتب المخزون — بـRETURNING زي التطبيق (درس ٠٠٠٥)
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into public.medication_stock (uuid, medication_uuid, patient_uuid, quantity, warn_days)
      values (v_stock, v_med, v_pat, 20, 5)
      returning uuid into v_back;
    if v_back is distinct from v_stock then raise exception 'FAIL 0028: المالك ما كتبش المخزون'; end if;
    -- ومش على دوا مريض تاني
    v_denied := false;
    begin
      insert into public.medication_stock (uuid, medication_uuid, patient_uuid, quantity)
        values (gen_random_uuid(), v_other_med, v_pat, 5);
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0028: مخزون اتلزّق على دوا مريض تاني'; end if;
    execute 'reset role';

    -- ٢) الممرض والابن بيقروا، وما بيعدّلوش
    foreach v_who in array array[v_nurse, v_son] loop
      perform set_config('request.jwt.claims', json_build_object('sub', v_who)::text, true);
      execute 'set local role authenticated';
      select count(*) into v_n from public.medication_stock where patient_uuid = v_pat;
      if v_n <> 1 then raise exception 'FAIL 0028: الدائرة مش شايفة المخزون (%)', v_n; end if;
      update public.medication_stock set quantity = 999 where uuid = v_stock;  -- RLS: صفر صف
      execute 'reset role';
    end loop;
    if (select quantity from public.medication_stock where uuid = v_stock) <> 20 then
      raise exception 'FAIL 0028: حد من الدائرة عدّل المخزون';
    end if;

    -- ٣) الممرض بصلاحية التعديل بيبعت «علبة جديدة»، والابن لأ
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    insert into public.medication_changes (patient_uuid, actor_id, kind, medication_uuid, payload)
      values (v_pat, v_nurse, 'restock', v_med, '{"quantity":30}'::jsonb);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      insert into public.medication_changes (patient_uuid, actor_id, kind, medication_uuid, payload)
        values (v_pat, v_son, 'restock', v_med, '{"quantity":30}'::jsonb);
    exception when insufficient_privilege then v_denied := true;
    end;
    execute 'reset role';
    if not v_denied then raise exception 'FAIL 0028: المتابع بعت علبة جديدة'; end if;

    -- ٤) الغريب ما بيشوفش
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medication_stock where patient_uuid = v_pat;
    execute 'reset role';
    if v_n <> 0 then raise exception 'FAIL 0028: غريب شاف المخزون (%)', v_n; end if;

    -- ٥) المخزون عمره ما بيبقى سالب
    v_denied := false;
    begin
      update public.medication_stock set quantity = -1 where uuid = v_stock;
    exception when check_violation then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0028: مخزون سالب عدّى'; end if;

    raise exception '0028_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0028_ROLLBACK' then raise; end if;
  end;

  raise notice '0028 OK — المالك بيكتب المخزون، الدائرة بتقرا وما بتعدّلش، الممرض بيبعت علبة جديدة والابن لأ، والغريب ما بيشوفش';
end $$;
