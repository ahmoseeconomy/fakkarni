-- 0024_medication_changes.sql — تغييرات الأدوية اللي بيقترحها الممرض
-- (المرحلة ب من تعليق المختبِر ٧).
--
-- الممرض اللي الأب فتح له `can_edit_meds` بيبعت **تغيير معلّق** (إضافة /
-- إيقاف / تعديل جرعة) — صف هنا، مش كتابة على `medications` (دي ملك موبايل
-- الأب، سياسات ٠٠٠٢). موبايل الأب بيسحب اللي لسه ما اتطبّقش، ويطبّقه
-- بسكّته هو، ويعلّم الصف بالنتيجة: `applied` / `conflict` (تعديل الأب
-- المحلي كسب) / `missing` (الدوا مش موجود). السلّم والتذكير ما اتلمسوش.
--
-- كل حاجة `if not exists` / `create or replace`، فالسلسلة تعيد التشغيل بأمان.

create or replace function private.can_edit_meds_for(p_patient uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.care_relationships cr
    where cr.patient_uuid = p_patient
      and cr.caregiver_id = (select auth.uid())
      and cr.status = 'accepted'
      and cr.can_edit_meds
  );
$$;

revoke execute on function private.can_edit_meds_for(uuid) from anon, public;
grant execute on function private.can_edit_meds_for(uuid) to authenticated;

create table if not exists public.medication_changes (
  uuid            uuid primary key default gen_random_uuid(),
  patient_uuid    uuid not null references public.patients (uuid) on delete cascade,
  actor_id        uuid not null references auth.users (id) on delete cascade,
  actor_name      text,
  kind            text not null check (kind in ('add', 'stop', 'amount')),
  -- الدوا المقصود للإيقاف/الجرعة — null في الإضافة. مش مفتاح أجنبي عن
  -- قصد: الدوا ممكن يتشال قبل ما التغيير يتطبّق، والصف لازم يفضل يقول
  -- إيه اللي كان مطلوب.
  medication_uuid uuid,
  medication_name text,
  payload         jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  applied_at      timestamptz,
  outcome         text check (outcome in ('applied', 'conflict', 'missing'))
);

create index if not exists medication_changes_pending_idx
  on public.medication_changes (patient_uuid, created_at) where applied_at is null;

alter table public.medication_changes enable row level security;
revoke all on public.medication_changes from anon, public;
grant select, insert, update on public.medication_changes to authenticated;

-- الدائرة كلها بتشوف (المريض بيسحب، والممرض بيشوف اللي بعته).
drop policy if exists medication_changes_select on public.medication_changes;
create policy medication_changes_select on public.medication_changes
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

-- الإدخال للي معاه `can_edit_meds` على المريض ده، وباسمه هو.
drop policy if exists medication_changes_insert on public.medication_changes;
create policy medication_changes_insert on public.medication_changes
  for insert to authenticated
  with check (
    actor_id = (select auth.uid())
    and private.can_edit_meds_for(patient_uuid)
  );

-- التعليم بالنتيجة **للمالك بس** — موبايله هو اللي طبّق.
drop policy if exists medication_changes_update on public.medication_changes;
create policy medication_changes_update on public.medication_changes
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

-- ============================================================ فحص ذاتي
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_editor   uuid := gen_random_uuid();   -- ممرض معاه can_edit_meds
  v_nurse    uuid := gen_random_uuid();   -- ممرض من غيرها
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_change   uuid;
  v_n        integer;
  v_denied   boolean;
begin
  if to_regclass('public.medication_changes') is null then
    raise exception 'FAIL 0024: medication_changes مش موجود';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'care_relationships'
                   and column_name = 'can_edit_meds') then
    raise exception 'FAIL 0024: شغّل 0023 الأول';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0024.check'),
      (v_editor,   'editor-'   || v_editor   || '@0024.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0024.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0024.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0024');
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
      values (v_pat, v_editor, 'accepted', 'nurse', true, true),
             (v_pat, v_nurse,  'accepted', 'nurse', true, false);

    -- ١) اللي معاه الصلاحية بيبعت
    perform set_config('request.jwt.claims', json_build_object('sub', v_editor)::text, true);
    execute 'set local role authenticated';
    insert into public.medication_changes (patient_uuid, actor_id, actor_name, kind, payload)
      values (v_pat, v_editor, 'سارة', 'add',
              '{"name":"Concor 5mg","timings":[{"kind":"anchor","anchor":"breakfast","offset":-30}]}'::jsonb)
      returning uuid into v_change;
    -- ومش باسم حد تاني
    v_denied := false;
    begin
      insert into public.medication_changes (patient_uuid, actor_id, kind) values (v_pat, v_nurse, 'stop');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0024: كتب باسم حد تاني'; end if;
    -- ومش بيعلّم بالنتيجة (ده للمالك)
    update public.medication_changes set applied_at = now(), outcome = 'applied' where uuid = v_change;
    if exists (select 1 from public.medication_changes where uuid = v_change and applied_at is not null) then
      raise exception 'FAIL 0024: الممرض علّم التغيير بنفسه';
    end if;

    -- ٢) ممرض من غير الصلاحية مرفوض
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      insert into public.medication_changes (patient_uuid, actor_id, kind) values (v_pat, v_nurse, 'stop');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0024: ممرض من غير can_edit_meds بعت تغيير'; end if;

    -- ٣) المالك بيشوف ويعلّم
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medication_changes where patient_uuid = v_pat and applied_at is null;
    if v_n <> 1 then raise exception 'FAIL 0024: الأب مش شايف المعلّق (%)', v_n; end if;
    update public.medication_changes set applied_at = now(), outcome = 'applied' where uuid = v_change;
    select count(*) into v_n from public.medication_changes where patient_uuid = v_pat and applied_at is null;
    if v_n <> 0 then raise exception 'FAIL 0024: التعليم ما اتكتبش'; end if;

    -- ٤) الغريب مفيش
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medication_changes where patient_uuid = v_pat;
    if v_n <> 0 then raise exception 'FAIL 0024: غريب شاف تغييرات (%)', v_n; end if;

    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    raise exception '0024_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0024_ROLLBACK' then raise; end if;
  end;

  raise notice '0024 OK — اللي معاه «يعدّل الأدوية» بيبعت، وغيره لأ، والمالك بس اللي بيعلّم';
end $$;
