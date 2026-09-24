-- 0025_family_subscription.sql — اشتراك العيلة (قرار المالك، تعليق المختبِر ٣).
--
-- اشتراك **واحد** على المريض بيغطّيه ولحد خمس ناس بيتابعوه. أي حد في
-- الدائرة يقدر يشتريه له. الصف بيتكتب **بالتريجر** (تجربة عند إنشاء
-- المريض) **وبالـEdge Function `verify-purchase` بمفتاح الخدمة** بعد ما
-- المتجر يأكّد — العميل ما بيكتبش فيه أبداً (مفيش insert/update لأي حد).
--
-- **القاعدة اللي ما بتتنازلش**: تذكير المريض بدواه ما له علاقة بالجدول
-- ده. الجدول بيحكم `private.due_escalations` (تنبيهات المتابعين) وبس؛
-- والمزايا اللي بتتقفل على الموبايل مكتوبة في `domain/billing/family_plan.dart`.
--
-- كل حاجة `if not exists` / `create or replace`، فالسلسلة تعيد التشغيل بأمان.

-- ============================================================ ١) الأرقام (مرآة دارت)

-- `SubscriptionConfig.trialDays` — الاختبار بيقرا الرقمين ويقارن.
create or replace function private.trial_days() returns integer
language sql immutable set search_path = '' as $$ select 14; $$;

-- المرضى الموجودين وقت الترحيل — `SubscriptionConfig.migrationTrialDays`.
create or replace function private.migration_trial_days() returns integer
language sql immutable set search_path = '' as $$ select 30; $$;

-- مهلة بعد الانتهاء المكتوب — `SubscriptionConfig.graceDays`.
create or replace function private.subscription_grace_days() returns integer
language sql immutable set search_path = '' as $$ select 3; $$;

-- سقف الدائرة — `SubscriptionConfig.followerCap`.
create or replace function private.follower_cap() returns integer
language sql immutable set search_path = '' as $$ select 5; $$;

revoke execute on function private.trial_days(), private.migration_trial_days(),
                           private.subscription_grace_days(), private.follower_cap()
  from anon, public;

-- ============================================================ ٢) الجدول

create table if not exists public.family_subscriptions (
  patient_uuid     uuid primary key references public.patients (uuid) on delete cascade,
  status           text not null default 'trial' check (status in ('trial', 'active', 'expired')),
  trial_ends_at    timestamptz not null,
  expires_at       timestamptz,
  store            text check (store in ('apple', 'google')),
  product_id       text,
  purchaser_id     uuid references auth.users (id) on delete set null,
  last_verified_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create extension if not exists moddatetime;
drop trigger if exists set_updated_at on public.family_subscriptions;
create trigger set_updated_at before update on public.family_subscriptions
  for each row execute procedure moddatetime (updated_at);

alter table public.family_subscriptions enable row level security;
revoke all on public.family_subscriptions from anon, public;
grant select on public.family_subscriptions to authenticated;

-- الدائرة كلها بتقرا الحالة (عشان الابن يعرف ليه التنبيه واقف، ويقدر
-- يشتري). **مفيش insert/update لأي عميل**: الكتابة بالتريجر وبمفتاح الخدمة.
drop policy if exists family_subscriptions_select on public.family_subscriptions;
create policy family_subscriptions_select on public.family_subscriptions
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

-- ============================================================ ٣) التجربة تبدأ مع المريض

create or replace function private.start_family_trial()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.family_subscriptions (patient_uuid, status, trial_ends_at)
  values (new.uuid, 'trial', now() + make_interval(days => private.trial_days()))
  on conflict (patient_uuid) do nothing;
  return new;
end;
$$;

drop trigger if exists start_family_trial on public.patients;
create trigger start_family_trial after insert on public.patients
  for each row execute function private.start_family_trial();

-- المرضى الموجودين: ٣٠ يوم من تاريخ الترحيل، ومفيش صف بيتكتب مرتين.
insert into public.family_subscriptions (patient_uuid, status, trial_ends_at)
select p.uuid, 'trial', now() + make_interval(days => private.migration_trial_days())
from public.patients p
on conflict (patient_uuid) do nothing;

-- ============================================================ ٤) السيم

-- اشتراك العيلة شغّال للمريض ده؟ التجربة لحد نهايتها، والنشط لحد انتهائه
-- + المهلة. **مفيش صف = شغّال** (مريض من قبل التريجر): مفيش قفل بسبب نقص.
create or replace function private.family_subscription_active(p_patient uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select case fs.status
             when 'trial'  then fs.trial_ends_at > now()
             when 'active' then fs.expires_at is null
                             or fs.expires_at + make_interval(days => private.subscription_grace_days()) > now()
             else false
           end
    from public.family_subscriptions fs
    where fs.patient_uuid = p_patient
  ), true);
$$;

-- السيم اللي 0020 حطّته: بقى بيسأل عن اشتراك **المريض**، مش المتابع.
-- التوقيع القديم (متابع بس) فاضل بيرجّع true عشان أي نداء قديم ما يقعش.
create or replace function private.follower_subscription_active(p_caregiver uuid, p_patient uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.family_subscription_active(p_patient);
$$;

revoke execute on function private.family_subscription_active(uuid),
                           private.follower_subscription_active(uuid, uuid)
  from anon, public, authenticated;
grant  execute on function private.family_subscription_active(uuid),
                           private.follower_subscription_active(uuid, uuid)
  to service_role;

-- ============================================================ ٥) الاختيار (نفس 0023 + السيم بالمريض)

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
  where ev.state in ('pending', 'missed')
    and ev.scheduled_at <= now() - private.server_grace_window()
    and ev.scheduled_at >  now() - interval '2 days'
    and m.stopped_at is null
    and m.removed_at is null
    and s.stopped_at is null
    -- 0025: اشتراك العيلة على المريض — تجربة أو نشط (+ مهلة)
    and private.follower_subscription_active(cr.caregiver_id, p.uuid)
    and not exists (
      select 1 from public.proxy_confirmations pc
      where pc.dose_event_uuid = ev.uuid
    )
    and not exists (
      select 1
      from public.escalations e
      where e.dose_event_uuid = ev.uuid
        and e.caregiver_id    = cr.caregiver_id
        and e.rung            = 'caregiver'
        and (
          e.delivery_status <> 'claimed'
          or e.created_at > now() - private.escalation_retry_after()
        )
    )
  order by ev.scheduled_at
  limit p_limit;
$$;

revoke execute on function private.due_escalations(integer) from anon, public, authenticated;
grant  execute on function private.due_escalations(integer) to service_role;

-- ============================================================ ٦) السقف: خمسة في الدائرة

create or replace function public.redeem_invite(p_code text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_invite record;
  v_uid uuid := (select auth.uid());
begin
  select * into v_invite
    from public.invite_codes
   where code = p_code
     and used_at is null
     and expires_at > now();

  if not found then
    raise exception 'invalid_code';
  end if;

  if exists (select 1 from public.patients p
              where p.uuid = v_invite.patient_uuid and p.owner_id = v_uid) then
    raise exception 'own_code';
  end if;

  if exists (select 1 from public.care_relationships cr
              where cr.patient_uuid = v_invite.patient_uuid
                and cr.caregiver_id = v_uid
                and cr.status = 'accepted') then
    raise exception 'already_linked';
  end if;

  -- 0025: الاشتراك الواحد بيغطّي لحد خمسة — السادس بيتقال له كده
  if (select count(*) from public.care_relationships cr
       where cr.patient_uuid = v_invite.patient_uuid and cr.status = 'accepted')
     >= private.follower_cap() then
    raise exception 'circle_full';
  end if;

  insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
  values (v_invite.patient_uuid, v_uid, 'accepted', v_invite.role, v_invite.role = 'nurse', false)
  on conflict (patient_uuid, caregiver_id)
    do update set status = 'accepted',
                  role = excluded.role,
                  can_confirm = excluded.can_confirm;

  update public.invite_codes
     set used_by = v_uid, used_at = now()
   where code = p_code;

  return v_invite.patient_uuid;
end;
$$;

-- ============================================================ فحص ذاتي
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_sched    uuid := gen_random_uuid();
  v_event    uuid := gen_random_uuid();
  v_n        integer;
  v_ends     timestamptz;
begin
  if to_regclass('public.family_subscriptions') is null then
    raise exception 'FAIL 0025: family_subscriptions مش موجود';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0025.check'),
      (v_son,      'son-'      || v_son      || '@0025.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0025.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0025');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');

    -- ١) التريجر عمل تجربة ١٤ يوم
    select trial_ends_at into v_ends from public.family_subscriptions where patient_uuid = v_pat;
    if v_ends is null then raise exception 'FAIL 0025: التريجر ما عملش تجربة'; end if;
    if v_ends < now() + interval '13 days' or v_ends > now() + interval '15 days' then
      raise exception 'FAIL 0025: التجربة مش ١٤ يوم (%)', v_ends;
    end if;
    if not private.family_subscription_active(v_pat) then
      raise exception 'FAIL 0025: التجربة مش شغّالة';
    end if;

    -- ٢) الدائرة بتقرا، والغريب لأ، وولا حد بيكتب
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.family_subscriptions where patient_uuid = v_pat;
    if v_n <> 1 then raise exception 'FAIL 0025: الابن مش شايف الحالة (%)', v_n; end if;
    begin
      update public.family_subscriptions set status = 'active' where patient_uuid = v_pat;
      -- RLS من غير سياسة update = صفر صف، من غير خطأ — نتأكد إن مفيش كتابة
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if (select status from public.family_subscriptions where patient_uuid = v_pat) <> 'trial' then
      raise exception 'FAIL 0025: عميل كتب في الاشتراك';
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.family_subscriptions where patient_uuid = v_pat;
    if v_n <> 0 then raise exception 'FAIL 0025: غريب شاف الاشتراك (%)', v_n; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);

    -- ٣) التصعيد بيمشي مع التجربة، وبيسكت لما تخلص، وبيرجع مع النشط
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
      values (v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date);
    insert into public.dose_events (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
      values (v_event, v_sched, current_date, now() - interval '90 minutes', 'pending');
    select count(*) into v_n from private.due_escalations() d where d.dose_event_uuid = v_event;
    if v_n <> 1 then raise exception 'FAIL 0025: التجربة ما بتصعّدش (%)', v_n; end if;

    update public.family_subscriptions set status = 'expired' where patient_uuid = v_pat;
    select count(*) into v_n from private.due_escalations() d where d.dose_event_uuid = v_event;
    if v_n <> 0 then raise exception 'FAIL 0025: المنتهي لسه بيصعّد'; end if;

    -- نشط انتهى امبارح بس جوّه المهلة → لسه بيمشي
    update public.family_subscriptions
       set status = 'active', expires_at = now() - interval '1 day' where patient_uuid = v_pat;
    select count(*) into v_n from private.due_escalations() d where d.dose_event_uuid = v_event;
    if v_n <> 1 then raise exception 'FAIL 0025: المهلة مش شغّالة'; end if;
    update public.family_subscriptions set expires_at = now() - interval '10 days' where patient_uuid = v_pat;
    select count(*) into v_n from private.due_escalations() d where d.dose_event_uuid = v_event;
    if v_n <> 0 then raise exception 'FAIL 0025: بعد المهلة لسه بيصعّد'; end if;

    -- ٤) مريض من غير صف (قبل التريجر) = شغّال — مفيش قفل بسبب نقص
    if not private.family_subscription_active(gen_random_uuid()) then
      raise exception 'FAIL 0025: مريض من غير صف اتقفل';
    end if;

    raise exception '0025_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0025_ROLLBACK' then raise; end if;
  end;

  raise notice '0025 OK — تجربة مع كل مريض، الدائرة بتقرا وما بتكتبش، والتصعيد بيمشي مع التجربة/النشط (+مهلة) وبس';
end $$;
