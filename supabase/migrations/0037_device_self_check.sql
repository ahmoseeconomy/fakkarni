-- ============================================================================
-- 0037 — الفحص الذاتي: حالة الجهاز وأكواده، سياسة الصف بصاحبه، والساكت
--        (ملف بس — ما اتطبّقش. المالك بيراجع وبيطبّق بإيده.)
-- ============================================================================
-- الموبايل بيفحص نفسه لوحده (فتحة باردة، رجوع للمقدمة، بعد أي تغيير جدول)،
-- بيصلّح اللي يتصلّح في صمت، وبيرفع صف واحد لكل (مريض، تنزيلة) على
-- `device_health` (0018). الملف ده بيزوّد على الصف:
--
-- ١) `status` كلمة واحدة: ok / healed / needs_user / broken — واللي السيرفر
--    بيكتبه بنفسه: silent (فيه جداول شغّالة ومفيش نبضة من ٤٨ ساعة).
--    و`codes` jsonb **أكواد بس** — ولا اسم دوا ولا أي بيان صحي (نفس عقد 0018).
--    و`status_since`: من إمتى الحالة دي (تريجر — بيتحرّك لما الحالة تتغيّر).
-- ٢) **42501 على النبضة**: سياسات 0018 كانت بتعدّي على `private.owns_patient`،
--    يعني صف المريض لازم يكون في السحابة **وبتاع الجلسة دي** — وأي جلسة
--    مجهولة جديدة على نفس الموبايل (الدين ٢) أو ابن بيبلّغ عن موبايله كانوا
--    بيترفضوا. دلوقتي الصف ليه `user_id` بتاع الجلسة اللي كتبته، والسياسات
--    بتقارنه بـ`auth.uid()` **على أعمدة الصف نفسه** (قاعدة 0005):
--      - القراية والمسح: صفوفي وبس (`user_id = auth.uid()`) — مفيش قراية لصفوف حد تاني.
--      - الإدخال: `user_id = auth.uid()` **و**المريض في دايرتي (`can_access_patient`
--        بتوصل جداول تانية بس) — عشان صاحب مفتاح عرف uuid مريض ما يرميش صفوف.
--      - التعديل: المريض في دايرتي (نفس الموبايل بعد جلسة جديدة بيكمّل على
--        صفه — `install_id` ثابت على الموبايل)، والصف الجديد لازم يبقى باسمي.
--    ولا grant لـanon. `admin_devices()` (0022) وdefiner، ما اتلمستش.
-- ٣) مهمة cron كل ساعة: `private.mark_silent_devices()` بتعلّم 'silent' على
--    أي جهاز ليه جداول جرعات شغّالة ومفيش نبضة منه من ٤٨ ساعة.
-- ٤) `private.admin_device_health` — **view في `private`**: مش مكشوفة لـPostgREST
--    أصلاً (السكيما مش في API)، ومسحوبة من anon/authenticated كمان؛ المالك
--    بيقراها من لوحة Supabase وبس. الأجهزة اللي فيها مشكلة: الحالة، الأكواد،
--    من إمتى، النسخة، المنصة، آخر ظهور.
--
-- الترتيب: بعد 0035 (0036 محجوز لـPRN). idempotent. الفحص الذاتي آخر جملة.
-- من غير الملف ده: الموبايل بيبعت الصف من غير `status`/`codes`/`user_id`
-- (PGRST204 → إعادة من غيرهم)، والسياسات القديمة زي ما هي.

-- ---------------------------------------------------------------- ١) الأعمدة

alter table public.device_health add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.device_health add column if not exists status text not null default 'ok';
alter table public.device_health add column if not exists codes jsonb not null default '[]'::jsonb;
alter table public.device_health add column if not exists status_since timestamptz not null default now();

alter table public.device_health drop constraint if exists device_health_status_check;
alter table public.device_health
  add constraint device_health_status_check
  check (status in ('ok', 'healed', 'needs_user', 'broken', 'silent'));

-- الأكواد قايمة نصوص قصيرة وبس — مفيش كائن ولا رقم ولا نص طويل (يعني مفيش
-- مكان لاسم دوا ولا جملة). الحدود: ٢٠ عنصر، وكل عنصر نص طوله ٤٠ حرف بالكتير.
-- دالة مساعدة لأن CHECK ما بيقبلش استعلام فرعي، و`.size()` في jsonpath
-- بيعدّ عناصر مش حروف. `device_health_sql_test` بيقرا الرقمين دول ويتأكد إن
-- قايمة `HealthCode` في دارت (كلها لو كلها مكسورة) وأطول اسم فيها جوّه الحد.
create or replace function private.health_codes_ok(p_codes jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p_codes) = 'array'
     and jsonb_array_length(p_codes) <= 20
     and not exists (
       select 1
         from jsonb_array_elements(p_codes) as e(v)
        where jsonb_typeof(e.v) <> 'string'
           or char_length(e.v #>> '{}') > 40)
$$;

-- القيد بيتنفّذ بصلاحية اللي بيكتب (authenticated) — فمحتاج EXECUTE صريح
revoke all on function private.health_codes_ok(jsonb) from anon, public;
grant execute on function private.health_codes_ok(jsonb) to authenticated;

alter table public.device_health drop constraint if exists device_health_codes_check;
alter table public.device_health
  add constraint device_health_codes_check
  check (private.health_codes_ok(codes));

-- الصفوف اللي قبل الملف ده: صاحبها هو صاحب المريض (السياسة القديمة كانت
-- بتضمن ده)، وحالتها من أكوادها القديمة
update public.device_health h
   set user_id = p.owner_id
  from public.patients p
 where p.uuid = h.patient_uuid and h.user_id is null;

update public.device_health
   set codes  = to_jsonb(failing_codes),
       status = case when cardinality(failing_codes) = 0 then 'ok' else 'broken' end
 where codes = '[]'::jsonb and cardinality(failing_codes) > 0;

create index if not exists device_health_user_idx   on public.device_health (user_id);
create index if not exists device_health_status_idx on public.device_health (status) where status <> 'ok';

-- `status_since` بيتحرّك لما الحالة تتغيّر — مش مع كل نبضة
create or replace function private.device_health_status_since()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    new.status_since := now();
  end if;
  return new;
end;
$$;

drop trigger if exists device_health_status_since on public.device_health;
create trigger device_health_status_since before update on public.device_health
  for each row execute function private.device_health_status_since();

-- ---------------------------------------------------------------- ٢) السياسات

drop policy if exists device_health_select on public.device_health;
create policy device_health_select on public.device_health
  for select to authenticated
  -- صفّي أنا، أو صفوف مريض أنا صاحبه. **لازم تبقى بعرض USING بتاع التعديل**:
  -- `INSERT … ON CONFLICT DO UPDATE` بيفحص الصف الموجود بـSELECT كمان، فجلسة
  -- جديدة على نفس الموبايل (الدين ٢) كانت بترجع 42501 وهي بتكمّل على صفها —
  -- ده اللي وقّع الفحص الذاتي على المشروع الحقيقي. صاحب المريض بيشوف صف
  -- موبايل ابنه كمان (أكواد سلامة بس — مقبول).
  using (user_id = (select auth.uid()) or private.owns_patient(patient_uuid));

drop policy if exists device_health_insert on public.device_health;
create policy device_health_insert on public.device_health
  for insert to authenticated
  with check (user_id = (select auth.uid()) and private.can_access_patient(patient_uuid));

drop policy if exists device_health_update on public.device_health;
create policy device_health_update on public.device_health
  for update to authenticated
  -- صفّي أنا، أو صف على مريض أنا صاحبه (جلسة جديدة على نفس الموبايل بعد
  -- إعادة الربط — الدين ٢). **مش** can_access_patient: ابن أو ممرض كان
  -- هيقدر يكتب فوق صف موبايل أبوه (يقلب الحالة لـok أو ياخد user_id).
  using (user_id = (select auth.uid()) or private.owns_patient(patient_uuid))
  with check (user_id = (select auth.uid()));

drop policy if exists device_health_delete on public.device_health;
create policy device_health_delete on public.device_health
  for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.device_health from anon, public;

-- ---------------------------------------------------------------- ٣) الساكت

-- نافذة السكوت — ٤٨ ساعة: يومين تغطية سحابة (الدين ٠) هما اللي بيخلّوا
-- «مفيش نبضة» معناها «الموبايل ده مش بيقول عن نفسه»، مش «مش فاتح التطبيق».
create or replace function private.device_silent_after()
returns interval
language sql immutable
set search_path = ''
as $$ select interval '48 hours' $$;

-- بتعلّم 'silent' على جهاز ليه جداول جرعات شغّالة (دوا مش متشال ولا موقوف،
-- وجدول مش موقوف) ومفيش نبضة منه من [device_silent_after]. بترجّع عدد
-- اللي اتعلّموا في المرة دي. اللي رجع بعت نبضة بيكتب حالته بنفسه فوقها.
-- **موبايل المريض بس** (الصف كاتبه صاحب المريض — موبايل ابن أو ممرض عمره
-- ما يبقى «ساكت»)، **وأحدث تنزيلة بس** لكل مريض (تنزيلة قديمة بعد إعادة
-- التنصيب ما تفضلش ساكتة للأبد).
create or replace function private.mark_silent_devices()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  with marked as (
    update public.device_health h
       set status = 'silent'
     where h.status <> 'silent'
       and h.checked_at < now() - private.device_silent_after()
       and exists (
         select 1 from public.patients p
          where p.uuid = h.patient_uuid
            and p.owner_id = h.user_id)
       and not exists (
         select 1 from public.device_health h2
           join public.patients p2 on p2.uuid = h2.patient_uuid
          where h2.patient_uuid = h.patient_uuid
            and h2.user_id = p2.owner_id
            and h2.install_id <> h.install_id
            and h2.checked_at > h.checked_at)
       and exists (
         select 1
           from public.medications m
           join public.dose_schedules s on s.medication_uuid = m.uuid
          where m.patient_uuid = h.patient_uuid
            and m.removed_at is null
            and m.stopped_at is null
            and s.stopped_at is null)
    returning 1)
  select count(*) into v_n from marked;
  return v_n;
end;
$$;

revoke all on function private.device_silent_after() from anon, authenticated, public;
revoke all on function private.mark_silent_devices() from anon, authenticated, public;

select cron.unschedule('fakkarni-device-silent')
where exists (select 1 from cron.job where jobname = 'fakkarni-device-silent');

select cron.schedule(
  'fakkarni-device-silent',
  '7 * * * *',
  $job$select private.mark_silent_devices()$job$
);

-- ---------------------------------------------------------------- ٤) للمالك

-- security_invoker مقفول (الافتراضي): الـview بتقرا بصلاحية صاحبها (postgres)،
-- فالمالك من لوحة Supabase بيشوف كل الأجهزة. ومسحوبة من كل الأدوار.
drop view if exists private.admin_device_health;
create view private.admin_device_health
  with (security_invoker = false)
as
  select
    h.install_id    as device_id,
    h.patient_uuid  as patient_id,
    h.status,
    h.codes,
    h.status_since  as since,
    h.app_version,
    h.platform,
    h.checked_at    as last_seen
  from public.device_health h
  where h.status <> 'ok'
  order by h.status_since desc;

revoke all on private.admin_device_health from anon, authenticated, public;

-- ================================================================ فحص ذاتي
--
-- (آخر جملة في الملف — بعد كل create/alter/grant.) بيكتب جوّه معاملة
-- وبيرجّعها: صاحب مريض بيبعت نبضة، جلسة تانية على نفس الموبايل بتكمّل
-- على نفس الصف، غريب ما بيقراش ولا بيكتب، الابن بيبلّغ عن موبايله، الساكت
-- بيتعلّم لما فيه جدول شغّال وبس، والـview بتجيب اللي فيه مشكلة.
--
-- **Live DB has real rows — never assert global counts.** المشروع الحقيقي
-- فيه صفوف حقيقية (الفحص وقع مرة لأن `mark_silent_devices()` علّمت صف حقيقي
-- قديم كمان ورجّعت ٢). كل عدّ هنا متقيّد بصفوف الفحص نفسه
-- (`patient_uuid in (v_pat, v_pat2)`)، وكل قراية لحالة صف بمفتاحه الكامل.
-- `device_health_sql_test` بيوقع على أي `count(*)` من غير القيد ده.
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_owner2   uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_pat2     uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_sched    uuid := gen_random_uuid();
  v_n        integer;
  v_silent   integer;
  v_status   text;
begin
  begin
    -- المالك الأول: patients.owner_id بيشاور على auth.users
    insert into auth.users (id, email) values (v_owner,    'owner-'    || v_owner    || '@0037.check');
    insert into auth.users (id, email) values (v_owner2,   'owner2-'   || v_owner2   || '@0037.check');
    insert into auth.users (id, email) values (v_son,      'son-'      || v_son      || '@0037.check');
    insert into auth.users (id, email) values (v_stranger, 'stranger-' || v_stranger || '@0037.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat,  v_owner,  'تأكيد 0037');
    insert into public.patients (uuid, owner_id, name) values (v_pat2, v_owner2, 'تأكيد 0037 ب');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');
    -- جدول شغّال للمريض الأول بس
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, repeat, start_date)
      values (v_sched, v_med, 'fixed', 'daily', current_date);

    -- ١) صاحب المريض بيبعت نبضة بحالتها وأكوادها — زي الموبايل بالظبط (upsert)
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into public.device_health
      (patient_uuid, install_id, user_id, platform, checked_at, status, codes, failing_codes)
      values (v_pat, 'install-a', v_owner, 'ios', now(), 'broken', '["pushToken"]'::jsonb, array['pushToken'])
    on conflict (patient_uuid, install_id) do update
      set user_id = excluded.user_id, checked_at = excluded.checked_at,
          status = excluded.status, codes = excluded.codes, failing_codes = excluded.failing_codes;
    select count(*) into v_n from public.device_health where patient_uuid = v_pat;
    if v_n <> 1 then raise exception 'FAIL 0037: صاحب المريض مش شايف صفه (%)', v_n; end if;

    -- ٢) نفس الموبايل بجلسة تانية (مجهول جديد — الدين ٢) بيكمّل على نفس الصف
    execute 'reset role';
    update public.patients set owner_id = v_owner2 where uuid = v_pat;   -- الربط اتعاد بالجلسة الجديدة
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner2)::text, true);
    execute 'set local role authenticated';
    insert into public.device_health
      (patient_uuid, install_id, user_id, platform, checked_at, status, codes, failing_codes)
      values (v_pat, 'install-a', v_owner2, 'ios', now(), 'healed', '[]'::jsonb, '{}')
    on conflict (patient_uuid, install_id) do update
      set user_id = excluded.user_id, checked_at = excluded.checked_at,
          status = excluded.status, codes = excluded.codes, failing_codes = excluded.failing_codes;
    execute 'reset role';
    select count(*) into v_n from public.device_health where patient_uuid = v_pat;
    if v_n <> 1 then raise exception 'FAIL 0037: الجلسة الجديدة عملت صف تاني بدل ما تكمّل (%)', v_n; end if;
    select status into v_status from public.device_health where patient_uuid = v_pat and install_id = 'install-a';
    if v_status <> 'healed' then raise exception 'FAIL 0037: الحالة ما اتكتبتش (%)', v_status; end if;
    -- والحالة اتغيّرت → status_since اتحرّك (التريجر)
    if not exists (select 1 from public.device_health
                    where patient_uuid = v_pat and install_id = 'install-a'
                      and status_since >= now() - interval '1 minute') then
      raise exception 'FAIL 0037: status_since ما اتحرّكش مع تغيير الحالة';
    end if;

    -- ٣) الجلسة القديمة مابقتش تشوف الصف (user_id بقى للجديدة)
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.device_health where patient_uuid = v_pat;
    if v_n <> 0 then raise exception 'FAIL 0037: جلسة قديمة شافت صف مش بتاعها (%)', v_n; end if;

    -- ٤) غريب: ولا قراية ولا كتابة (42501)
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.device_health where patient_uuid in (v_pat, v_pat2);
    if v_n <> 0 then raise exception 'FAIL 0037: غريب قرا صفوف (%)', v_n; end if;
    begin
      insert into public.device_health (patient_uuid, install_id, user_id, platform, checked_at)
        values (v_pat, 'install-x', v_stranger, 'android', now());
      raise exception 'FAIL 0037: غريب كتب صف على مريض مش في دايرته';
    exception when insufficient_privilege then
      null; -- المطلوب
    end;
    -- ولا يكتب باسم حد تاني
    begin
      insert into public.device_health (patient_uuid, install_id, user_id, platform, checked_at)
        values (v_pat, 'install-y', v_owner2, 'android', now());
      raise exception 'FAIL 0037: غريب كتب صف باسم حد تاني';
    exception when insufficient_privilege then
      null;
    end;

    -- ٥) الابن (علاقة مقبولة) بيبلّغ عن موبايله هو
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    insert into public.device_health (patient_uuid, install_id, user_id, platform, checked_at, status, codes)
      values (v_pat, 'install-son', v_son, 'android', now(), 'ok', '[]'::jsonb);
    select count(*) into v_n from public.device_health where patient_uuid in (v_pat, v_pat2);
    if v_n <> 1 then raise exception 'FAIL 0037: الابن شايف غير صفه (%)', v_n; end if;
    -- والتعديل على صفّه هو شغّال (upsert — سكّة الموبايل)
    insert into public.device_health (patient_uuid, install_id, user_id, platform, checked_at, status, codes)
      values (v_pat, 'install-son', v_son, 'android', now(), 'healed', '[]'::jsonb)
    on conflict (patient_uuid, install_id) do update
      set checked_at = excluded.checked_at, status = excluded.status;
    if (select status from public.device_health where patient_uuid = v_pat and install_id = 'install-son') <> 'healed' then
      raise exception 'FAIL 0037: الابن مقدرش يحدّث صفّه هو';
    end if;
    -- ٥ب) الابن ما يكتبش فوق صف موبايل أبوه: UPDATE = صفر صفوف…
    update public.device_health set status = 'ok', user_id = v_son
      where patient_uuid = v_pat and install_id = 'install-a';
    get diagnostics v_n = row_count;
    if v_n <> 0 then raise exception 'FAIL 0037: الابن عدّل صف موبايل أبوه (%)', v_n; end if;
    -- …والـupsert على نفس المفتاح بيترفض (ON CONFLICT بيرمي لما USING يرفض)
    begin
      insert into public.device_health (patient_uuid, install_id, user_id, platform, checked_at, status)
        values (v_pat, 'install-a', v_son, 'ios', now(), 'ok')
      on conflict (patient_uuid, install_id) do update
        set user_id = excluded.user_id, status = excluded.status;
      raise exception 'FAIL 0037: الابن خد صف موبايل أبوه بالـupsert';
    exception when insufficient_privilege then
      null; -- المطلوب
    end;
    execute 'reset role';
    if (select user_id from public.device_health where patient_uuid = v_pat and install_id = 'install-a') <> v_owner2
       or (select status from public.device_health where patient_uuid = v_pat and install_id = 'install-a') <> 'healed' then
      raise exception 'FAIL 0037: صف موبايل الأب اتغيّر من الابن';
    end if;
    -- ٥ج) صاحب المريض بيشوف صف موبايله وصف موبايل الابن (أكواد بس)
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner2)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.device_health
      where patient_uuid = v_pat and install_id in ('install-a', 'install-son');
    if v_n <> 2 then raise exception 'FAIL 0037: صاحب المريض مش شايف صفوف مريضه (%)', v_n; end if;
    execute 'reset role';
    -- والابن لسه شايف صفّه هو بس
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.device_health where patient_uuid in (v_pat, v_pat2);
    if v_n <> 1 then raise exception 'FAIL 0037: الابن شايف صف غير صفّه (%)', v_n; end if;
    execute 'reset role';

    -- ٦) الساكت: جدول شغّال + ٣ أيام سكوت → silent؛ مريض من غير جداول → لأ
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    insert into public.device_health (patient_uuid, install_id, user_id, platform, checked_at, status)
      values (v_pat2, 'install-b', v_owner2, 'ios', now() - interval '3 days', 'ok');
    update public.device_health set checked_at = now() - interval '3 days'
      where patient_uuid = v_pat and install_id = 'install-a';
    -- موبايل الابن ساكت ٣ أيام — مش «ساكت» (مش موبايل المريض)
    update public.device_health set checked_at = now() - interval '3 days'
      where patient_uuid = v_pat and install_id = 'install-son';
    -- تنزيلة قديمة لنفس المريض (قبل إعادة التنصيب)، أقدم من install-a — مش «ساكتة»
    insert into public.device_health (patient_uuid, install_id, user_id, platform, checked_at, status)
      values (v_pat, 'install-old', v_owner2, 'ios', now() - interval '5 days', 'ok');
    -- الرقم الراجع عام (صفوف حقيقية ممكن تتعلّم معانا) — ≥ ١ وبس؛ الحكم
    -- الحقيقي على حالات صفوف الفحص تحت
    select private.mark_silent_devices() into v_n;
    if v_n < 1 then raise exception 'FAIL 0037: الساكت ما اتعلّمش خالص (%)', v_n; end if;
    if (select status from public.device_health where patient_uuid = v_pat and install_id = 'install-son') = 'silent' then
      raise exception 'FAIL 0037: موبايل الابن اتعلّم ساكت';
    end if;
    if (select status from public.device_health where patient_uuid = v_pat and install_id = 'install-old') = 'silent' then
      raise exception 'FAIL 0037: تنزيلة قديمة اتعلّمت ساكتة وفيه أحدث منها';
    end if;
    if (select status from public.device_health where patient_uuid = v_pat and install_id = 'install-a') <> 'silent' then
      raise exception 'FAIL 0037: الجهاز الساكت ما اتعلّمش';
    end if;
    if (select status from public.device_health where patient_uuid = v_pat2) <> 'ok' then
      raise exception 'FAIL 0037: مريض من غير جداول اتعلّم ساكت';
    end if;
    -- تاني مرة مفيش جديد — على صفوف الفحص (الرقم الراجع عام)
    select count(*) into v_silent from public.device_health
      where patient_uuid in (v_pat, v_pat2) and status = 'silent';
    if v_silent <> 1 then raise exception 'FAIL 0037: صفوف الفحص الساكتة المفروض واحد (%)', v_silent; end if;
    perform private.mark_silent_devices();
    select count(*) into v_n from public.device_health
      where patient_uuid in (v_pat, v_pat2) and status = 'silent';
    if v_n <> v_silent then raise exception 'FAIL 0037: الساكت اتعلّم مرتين (% ← %)', v_silent, v_n; end if;

    -- ٧) الـview: الساكت موجود، والـok لأ، وبأعمدتها
    select count(*) into v_n from private.admin_device_health
      where device_id = 'install-a' and patient_id = v_pat and status = 'silent';
    if v_n <> 1 then raise exception 'FAIL 0037: الـview ما جابتش الساكت'; end if;
    select count(*) into v_n from private.admin_device_health
      where patient_id in (v_pat, v_pat2) and device_id in ('install-b', 'install-old');
    if v_n <> 0 then raise exception 'FAIL 0037: الـview جابت جهاز تمام'; end if;

    -- ٨) قيود الحالة والأكواد
    begin
      update public.device_health set status = 'weird' where patient_uuid = v_pat and install_id = 'install-son';
      raise exception 'FAIL 0037: حالة برّه القيد اتقبلت';
    exception when check_violation then null;
    end;
    begin
      update public.device_health set codes = '{"a":1}'::jsonb where patient_uuid = v_pat and install_id = 'install-son';
      raise exception 'FAIL 0037: أكواد مش قايمة اتقبلت';
    exception when check_violation then null;
    end;
    begin
      update public.device_health set codes = '[1]'::jsonb where patient_uuid = v_pat and install_id = 'install-son';
      raise exception 'FAIL 0037: كود مش نص اتقبل';
    exception when check_violation then null;
    end;
    begin
      update public.device_health set codes = jsonb_build_array('x', repeat('y', 50)) where patient_uuid = v_pat and install_id = 'install-son';
      raise exception 'FAIL 0037: كود طوله ٥٠ حرف اتقبل';
    exception when check_violation then null;
    end;
    begin
      update public.device_health
         set codes = (select jsonb_agg('c' || g) from generate_series(1, 21) g)
       where patient_uuid = v_pat and install_id = 'install-son';
      raise exception 'FAIL 0037: ٢١ كود اتقبلوا';
    exception when check_violation then null;
    end;
    -- والحد نفسه مقبول: ٢٠ كود، أطولهم ٤٠ حرف
    update public.device_health
       set codes = (select jsonb_agg(repeat('z', 40)) from generate_series(1, 20))
     where patient_uuid = v_pat and install_id = 'install-son';

    -- ٩) RLS شغّال، والمهمة متجدولة، وanon ما عندوش حاجة على الجدول ولا الـview
    if not exists (select 1 from pg_class where oid = 'public.device_health'::regclass and relrowsecurity) then
      raise exception 'FAIL 0037: RLS مش مفعّل';
    end if;
    if to_regclass('cron.job') is not null then
      if not exists (select 1 from cron.job where jobname = 'fakkarni-device-silent') then
        raise exception 'FAIL 0037: مهمة الساكت مش متجدولة';
      end if;
    end if;
    if has_table_privilege('anon', 'public.device_health', 'select')
       or has_table_privilege('anon', 'private.admin_device_health', 'select')
       or has_table_privilege('authenticated', 'private.admin_device_health', 'select') then
      raise exception 'FAIL 0037: anon/authenticated عندهم قراية ما كانش المفروض';
    end if;

    raise exception '0037_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0037_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0037 OK — الحالة والأكواد بتتكتب، الصف بصاحبه، الساكت بيتعلّم كل ساعة، والمالك بيقرا اللي فيه مشكلة';
end $$;
