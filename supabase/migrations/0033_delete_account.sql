-- ============================================================================
-- 0033 — مسح الحساب (Apple 5.1.1(v)) — ملف بس، ما اتطبّقش
-- ============================================================================
-- دالة الحافة `delete-account` بتنده الدالتين هنا بمفتاح الخدمة، والتطبيق
-- عمره ما بيناديهم: EXECUTE لـ`service_role` لوحده.
--
--   ١) `account_deletion_objects_for_service(p_user)` — الصور اللي لازم تتمسح
--      من الباكت **قبل** أي صف. المسح المباشر من `storage.objects` ممنوع في
--      Supabase، فالدالة بتقول الأسماء والدالة بتمسحها من Storage API.
--   ٢) `delete_account_for_service(p_user)` — كل الصفوف في معاملة واحدة:
--      * مالك مريض → صف المريض بيتمسح وكل حاجة تحته بالـcascade (الأدوية،
--        الجداول، الجرعات، الملف الصحي، القياسات، المخزون، الطوارئ، الأكواد،
--        العلاقات، الاشتراك، أكواد السلامة، التأكيدات والطلبات).
--      * متابع/ممرض → علاقاته وتفضيلاته وتنبيهاته وتوكنه **وبس**. بيانات
--        المريض بتاعة المريض. سطر «فلان خرج من الدايرة» بيتكتب في
--        `circle_departures` قبل ما العلاقة تتشال.
--      * تأكيد نيابةً أو طلب تعديل كتبه ممرض بيفضلوا (الجرعة اتاخدت فعلاً،
--        والسيرفر بيعتبرها مؤكَّدة)، **من غير اسمه ولا معرّفه**.
--      * عدّاد مجهول واحد في `private.account_deletions` (اليوم والنوع —
--        ولا اسم ولا معرّف) عشان لوحة الأدمن تعدّ.
--   ٣) بعدها الدالة بتمسح المستخدم من Auth.
--
-- وتلات مفاتيح أجنبية كانت هتمنع مسح المستخدم أو تمسح حاجة مش بتاعته:
--   * `invite_codes.used_by` — من غير `on delete` خالص: أي حد استبدل كود
--     كان مسحه من Auth هيقع. بقت `set null`.
--   * `proxy_confirmations.actor_id` و`medication_changes.actor_id` — كانوا
--     `cascade`: ممرض يمسح حسابه، فتأكيده يتشال، و`due_escalations` يرجع
--     يشوف الجرعة مفتوحة وينبّه الابن عن حباية اتاخدت. بقوا `set null`.
--
-- `due_escalations` ما اتلمستش. الترتيب: بعد 0032. idempotent.
--
-- **تنبيه للفرع `wip/prn-round3`**: الملف ده خد الرقم 0033؛ هجرة
-- «عند اللزوم» لازم تبقى 0034.

-- ============================================================ ١) المفاتيح

do $$
declare
  r record;
  v_con text;
begin
  for r in
    select * from (values
      ('invite_codes',        'used_by'),
      ('proxy_confirmations', 'actor_id'),
      ('medication_changes',  'actor_id')
    ) as t(tbl, col)
  loop
    select c.conname into v_con
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      join pg_attribute a on a.attrelid = t.oid and a.attnum = any (c.conkey)
     where n.nspname = 'public' and t.relname = r.tbl and a.attname = r.col
       and c.contype = 'f'
     limit 1;
    if v_con is not null then
      execute format('alter table public.%I drop constraint %I', r.tbl, v_con);
    end if;
    execute format('alter table public.%I alter column %I drop not null', r.tbl, r.col);
    execute format(
      'alter table public.%I add constraint %I foreign key (%I) references auth.users (id) on delete set null',
      r.tbl, r.tbl || '_' || r.col || '_fkey', r.col);
  end loop;
end $$;

-- ============================================================ ٢) «خرج من الدايرة»

create table if not exists public.circle_departures (
  uuid         uuid primary key default gen_random_uuid(),
  patient_uuid uuid not null references public.patients (uuid) on delete cascade,
  -- اللي هو كتبه عن نفسه في «بياناتك وتنبيهاتك» — null لو ما كتبش
  display_name text,
  relation     text check (relation in ('son', 'daughter', 'other')),
  role         text not null default 'follower' check (role in ('follower', 'nurse')),
  left_at      timestamptz not null default now()
);

create index if not exists circle_departures_patient_idx
  on public.circle_departures (patient_uuid, left_at desc);

alter table public.circle_departures enable row level security;
revoke all on public.circle_departures from anon, public;
grant select on public.circle_departures to authenticated;

-- الدائرة بتقرا (المريض ومين فاضل بيتابعه). **مفيش سياسة إدخال ولا تعديل
-- ولا مسح لأي حد** — الصف بيتكتب من الدالة بمفتاح الخدمة وبس.
drop policy if exists circle_departures_select on public.circle_departures;
create policy circle_departures_select on public.circle_departures
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

-- ============================================================ ٣) العدّاد المجهول

create table if not exists private.account_deletions (
  id         bigserial primary key,
  deleted_on date not null default current_date,
  kind       text not null check (kind in ('patient', 'follower', 'nurse'))
);
revoke all on private.account_deletions from anon, authenticated, public;

-- ============================================================ ٤) الصور

create or replace function public.account_deletion_objects_for_service(p_user uuid)
returns table (bucket_id text, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select o.bucket_id, o.name
    from storage.objects o
   where o.bucket_id = 'patient-papers'
     and (
       -- كل حاجة تحت مريض بيملكه: الورق، وصور الأدوية، والمستني
       split_part(o.name, '/', 1) in (
         select p.uuid::text from public.patients p where p.owner_id = p_user)
       -- وأي حاجة رفعها هو بنفسه على مريض تاني (صورة ممرض مستنية)
       or o.owner = p_user
     );
$$;

-- ============================================================ ٥) الصفوف

create or replace function public.delete_account_for_service(p_user uuid)
returns table (kind text, removed_patients integer, removed_links integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_patients integer := 0;
  v_links    integer := 0;
  v_nurse    boolean;
  v_kind     text;
begin
  if p_user is null then
    raise exception 'no user';
  end if;

  select exists (
    select 1 from public.care_relationships
     where caregiver_id = p_user and role = 'nurse' and status = 'accepted'
  ) into v_nurse;

  -- «فلان خرج من الدايرة» — قبل ما العلاقة تتشال، ومش على مريض هو مالكه
  insert into public.circle_departures (patient_uuid, display_name, relation, role)
  select cr.patient_uuid,
         nullif(btrim(cp.display_name), ''),
         cp.relation,
         cr.role
    from public.care_relationships cr
    left join public.caregiver_preferences cp
      on cp.caregiver_id = cr.caregiver_id and cp.patient_uuid = cr.patient_uuid
   where cr.caregiver_id = p_user
     and cr.status = 'accepted'
     and not exists (
       select 1 from public.patients p where p.uuid = cr.patient_uuid and p.owner_id = p_user);

  delete from public.care_relationships where caregiver_id = p_user;
  get diagnostics v_links = row_count;

  delete from public.caregiver_preferences where caregiver_id = p_user;
  delete from public.escalations          where caregiver_id = p_user;
  delete from public.device_tokens        where user_id = p_user;
  delete from public.invite_codes         where created_by = p_user;
  update public.invite_codes         set used_by = null where used_by = p_user;
  update public.family_subscriptions set purchaser_id = null where purchaser_id = p_user;
  -- الجرعة اتاخدت فعلاً — الحقيقة بتفضل، هو اللي بيمشي
  update public.proxy_confirmations set actor_id = null, actor_name = null where actor_id = p_user;
  update public.medication_changes  set actor_id = null, actor_name = null where actor_id = p_user;
  if to_regclass('public.ai_reads') is not null then
    execute 'delete from public.ai_reads where user_id = $1' using p_user;
  end if;

  -- مريضه — وكل اللي تحته بالـcascade
  delete from public.patients where owner_id = p_user;
  get diagnostics v_patients = row_count;

  -- «خرج من الدايرة» سطر بيتقري وبيعدّي، مش أرشيف
  delete from public.circle_departures where left_at < now() - interval '30 days';

  v_kind := case
    when v_patients > 0 then 'patient'
    when v_links > 0 and v_nurse then 'nurse'
    when v_links > 0 then 'follower'
  end;
  -- إعادة المحاولة بعد نجاح جزئي ما بتعدّش مرتين: المرة التانية مفيش حاجة
  if v_kind is not null then
    insert into private.account_deletions (kind) values (v_kind);
  end if;

  return query select coalesce(v_kind, 'empty'), v_patients, v_links;
end;
$$;

revoke all on function public.account_deletion_objects_for_service(uuid) from anon, authenticated, public;
revoke all on function public.delete_account_for_service(uuid)           from anon, authenticated, public;
grant execute on function public.account_deletion_objects_for_service(uuid) to service_role;
grant execute on function public.delete_account_for_service(uuid)           to service_role;

-- ============================================================ ٦) لوحة الأدمن
--
-- نفس الأرقام الأربعة بالحرف (0021)، وعمودين مجهولين: كام حساب اتمسح.
-- نوع الرجوع اتغيّر، فلازم `drop` الأول.

drop function if exists public.admin_counts();
create function public.admin_counts()
returns table (
  total_patients      bigint,
  total_followers     bigint,
  active_7d           bigint,
  battery_restricted  bigint,
  deleted_total       bigint,
  deleted_30d         bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'not admin';
  end if;
  return query
    select
      count(*),
      coalesce(sum(r.followers_count), 0)::bigint,
      count(*) filter (where r.last_sync_at > now() - interval '7 days'),
      count(*) filter (where r.battery_state = 'restricted'),
      (select count(*) from private.account_deletions),
      (select count(*) from private.account_deletions d where d.deleted_on > current_date - 30)
    from private.admin_account_rows() r;
end;
$$;

revoke all on function public.admin_counts() from anon, public;
grant execute on function public.admin_counts() to authenticated;

-- ============================================================ فحص ذاتي
--
-- دوال الخدمة بتتنده بدور المالك (زي الدالة بالظبط)، والجداول وRLS بتتقري
-- تحت `set local role authenticated` — ولا نداء private.* في الدور ده.
-- **والمالك بيتعمل في `auth.users` قبل المريض** (درس ٠٠١٦).

do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_sched    uuid := gen_random_uuid();
  v_event    uuid := gen_random_uuid();
  v_before   bigint;
  v_n        integer;
  v_kind     text;
  v_denied   boolean;
begin
  begin
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0033.check'),
      (v_son,      'son-'      || v_son      || '@0033.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0033.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0033.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0033');
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role)
      values (v_pat, v_son, 'accepted', 'follower'), (v_pat, v_nurse, 'accepted', 'nurse');
    insert into public.caregiver_preferences (caregiver_id, patient_uuid, display_name, relation)
      values (v_son, v_pat, 'محمد', 'son');
    insert into public.invite_codes (code, patient_uuid, created_by, used_by, expires_at)
      -- كود عشوائي: كود ثابت ممكن يخبط في كود حقيقي شغّال على المشروع
      values (lpad((floor(random() * 1000000))::int::text, 6, '0'), v_pat, v_owner, v_son,
              now() + interval '15 minutes');
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
      values (v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date);
    insert into public.dose_events (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
      values (v_event, v_sched, current_date, now() - interval '10 minutes', 'pending');
    insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id, actor_name)
      values (v_event, v_pat, v_nurse, 'سارة');
    insert into public.medication_changes (patient_uuid, actor_id, actor_name, kind, medication_uuid, medication_name)
      values (v_pat, v_nurse, 'سارة', 'stop', v_med, 'Concor');
    insert into storage.objects (bucket_id, name, owner)
      values ('patient-papers', v_pat || '/med-photos/' || v_med || '.jpg', v_owner),
             ('patient-papers', v_pat || '/pending/' || gen_random_uuid() || '.jpg', v_nurse);

    select count(*) into v_before from private.account_deletions;

    -- ١) الصور: المالك بياخد كل اللي تحت مريضه، والممرض اللي رفعه بس
    select count(*) into v_n from public.account_deletion_objects_for_service(v_owner);
    if v_n <> 2 then raise exception 'FAIL 0033: صور المالك % مش ٢', v_n; end if;
    select count(*) into v_n from public.account_deletion_objects_for_service(v_nurse);
    if v_n <> 1 then raise exception 'FAIL 0033: صور الممرض % مش ١', v_n; end if;
    select count(*) into v_n from public.account_deletion_objects_for_service(v_stranger);
    if v_n <> 0 then raise exception 'FAIL 0033: غريب طلعله صور'; end if;
    -- (المسح المباشر من storage.objects ممنوع — الـrollback في الآخر هو اللي بيشيلهم)

    -- ٢) المستخدم العادي ما يقدرش ينده دالة الخدمة
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      perform * from public.delete_account_for_service(v_owner);
    exception when insufficient_privilege then v_denied := true;
    end;
    execute 'reset role';
    if not v_denied then raise exception 'FAIL 0033: authenticated نده دالة المسح'; end if;

    -- ٣) الابن يمسح حسابه: علاقته راحت، وسطر «خرج» اتكتب باسمه
    select d.kind into v_kind from public.delete_account_for_service(v_son) d;
    if v_kind <> 'follower' then raise exception 'FAIL 0033: نوع الابن %', v_kind; end if;
    if exists (select 1 from public.care_relationships where caregiver_id = v_son) then
      raise exception 'FAIL 0033: علاقة الابن فضلت';
    end if;
    if exists (select 1 from public.caregiver_preferences where caregiver_id = v_son) then
      raise exception 'FAIL 0033: تفضيلات الابن فضلت';
    end if;
    delete from auth.users where id = v_son;  -- كان بيقع على invite_codes.used_by

    -- ٤) الممرض يمسح حسابه: تأكيده وطلبه فاضلين من غير اسمه
    select d.kind into v_kind from public.delete_account_for_service(v_nurse) d;
    if v_kind <> 'nurse' then raise exception 'FAIL 0033: نوع الممرض %', v_kind; end if;
    delete from auth.users where id = v_nurse;

    -- ٥) المالك بيقرا من الجداول وRLS: «خرج» فيها الابن والممرض، والتأكيد فاضل
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.circle_departures where patient_uuid = v_pat;
    if v_n <> 2 then execute 'reset role'; raise exception 'FAIL 0033: المالك شايف % سطر خروج', v_n; end if;
    select count(*) into v_n from public.circle_departures
     where patient_uuid = v_pat and display_name = 'محمد' and relation = 'son';
    if v_n <> 1 then execute 'reset role'; raise exception 'FAIL 0033: سطر الابن من غير اسمه'; end if;
    select count(*) into v_n from public.proxy_confirmations
     where dose_event_uuid = v_event and actor_id is null and actor_name is null;
    if v_n <> 1 then execute 'reset role'; raise exception 'FAIL 0033: تأكيد الممرض راح أو فضل باسمه'; end if;
    select count(*) into v_n from public.medication_changes
     where patient_uuid = v_pat and actor_id is null and actor_name is null;
    if v_n <> 1 then execute 'reset role'; raise exception 'FAIL 0033: طلب الممرض راح أو فضل باسمه'; end if;
    execute 'reset role';

    -- ٦) الغريب ما بيشوفش سطور الخروج
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.circle_departures where patient_uuid = v_pat;
    execute 'reset role';
    if v_n <> 0 then raise exception 'FAIL 0033: غريب شاف سطور الخروج'; end if;

    -- ٧) المالك يمسح حسابه: المريض وكل اللي تحته راحوا
    select d.kind into v_kind from public.delete_account_for_service(v_owner) d;
    if v_kind <> 'patient' then raise exception 'FAIL 0033: نوع المالك %', v_kind; end if;
    if exists (select 1 from public.patients where uuid = v_pat)
       or exists (select 1 from public.medications where uuid = v_med)
       or exists (select 1 from public.dose_events where uuid = v_event)
       or exists (select 1 from public.circle_departures where patient_uuid = v_pat)
       or exists (select 1 from public.invite_codes where patient_uuid = v_pat) then
      raise exception 'FAIL 0033: بيانات المريض فضلت بعد مسح المالك';
    end if;
    delete from auth.users where id = v_owner;

    -- ٨) إعادة المحاولة ما بتعدّش: التالت مرة «empty»
    select d.kind into v_kind from public.delete_account_for_service(v_owner) d;
    if v_kind <> 'empty' then raise exception 'FAIL 0033: إعادة المحاولة رجّعت %', v_kind; end if;
    select count(*) - v_before into v_n from private.account_deletions;
    if v_n <> 3 then raise exception 'FAIL 0033: العدّاد زاد % مش ٣', v_n; end if;

    raise exception '0033_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0033_ROLLBACK' then raise; end if;
  end;

  raise notice '0033 OK — المسح: الصور بتتحسب صح، الدالة للخدمة بس، المتابع والممرض بيمشوا ويسيبوا سطر «خرج»، التأكيد بيفضل من غير اسم، المالك بيمسح كل حاجة، والعدّاد مجهول ومش بيتكرر';
end $$;
