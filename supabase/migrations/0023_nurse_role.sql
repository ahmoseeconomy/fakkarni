-- 0023_nurse_role.sql — الممرض/المرافق: دور وصلاحيات على علاقة الرعاية،
-- وتأكيد الجرعة نيابةً عن المريض.
--
-- **قرار المالك (تعليق المختبِر ٧):** الممرض علاقة رعاية ليها دور وصلاحيات،
-- مش دخول مشترك. الأدوار: `follower` (متابع: بيشوف وبيتنبّه) و`nurse`
-- (ممرض/مرافق: مرآة). الصلاحيات على العلاقة: `can_confirm` (للممرض
-- افتراضياً) و`can_edit_meds` (مقفولة لحد ما المريض يفتحها).
-- **الافتراضيات بتسيب كل متابع موجود زي ما هو بالظبط.**
--
-- **التأكيد نيابةً = صف في `proxy_confirmations`، مش تعديل على
-- `dose_events`.** صف الجرعة ملك موبايل الأب (سياسات ٠٠٠٢: الكتابة للمالك
-- حصراً)، وموبايله هو اللي بيسحب التأكيد ويكتب `taken` محلياً ويرفعه.
-- السيرفر بيعتبرها مؤكَّدة من لحظة الصف: `private.due_escalations` بتستبعد
-- أي حدث عليه تأكيد نيابةً. السلّم ومهلة الـ٦٠ دقيقة وتنبيه الابن ما اتلمسوش.
--
-- **ولا تغيير على `create_invite` غير الدور**: البوابة الوحيدة في الحيطة
-- لسه للمالك بس (`private.owns_patient`)، والكود بيشيل دوره معاه.
--
-- كل حاجة `if not exists` / `create or replace`، فالسلسلة تعيد التشغيل بأمان.

-- ============================================================ ١) الأعمدة

alter table public.care_relationships
  add column if not exists role          text    not null default 'follower',
  add column if not exists can_confirm   boolean not null default false,
  add column if not exists can_edit_meds boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'care_relationships_role_check') then
    alter table public.care_relationships
      add constraint care_relationships_role_check check (role in ('follower', 'nurse'));
  end if;
end $$;

alter table public.invite_codes
  add column if not exists role text not null default 'follower';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'invite_codes_role_check') then
    alter table public.invite_codes
      add constraint invite_codes_role_check check (role in ('follower', 'nurse'));
  end if;
end $$;

-- ============================================================ ٢) الدعوة بدور

-- التوقيع القديم (uuid) بيتشال عشان نداء PostgREST بـp_patient_uuid بس
-- ما يبقاش غامضاً بين الاتنين. الافتراضي `follower` = نفس السلوك القديم.
drop function if exists public.create_invite(uuid);

create or replace function public.create_invite(p_patient_uuid uuid, p_role text default 'follower')
returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if not private.owns_patient(p_patient_uuid) then
    raise exception 'not_owner';
  end if;
  if p_role not in ('follower', 'nurse') then
    raise exception 'bad_role';
  end if;

  update public.invite_codes
     set expires_at = now()
   where patient_uuid = p_patient_uuid
     and created_by = (select auth.uid())
     and used_at is null
     and expires_at > now();

  delete from public.invite_codes
   where expires_at < now() - interval '1 day' and used_at is null;

  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    begin
      insert into public.invite_codes (code, patient_uuid, created_by, expires_at, role)
      values (v_code, p_patient_uuid, (select auth.uid()),
              now() + interval '15 minutes', p_role);
      exit;
    exception when unique_violation then
      -- تصادم مع كود قائم — جرّب رقماً آخر
    end;
  end loop;

  return v_code;
end;
$$;

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

  -- كود جديد من الأب = موافقة جديدة بدوره الجديد: الممرض بيقدر يأكّد
  -- افتراضياً، والمتابع لأ. تعديل الأدوية مقفول للاتنين لحد ما الأب يفتحه.
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

revoke execute on function public.create_invite(uuid, text), public.redeem_invite(text)
  from anon, public;
grant execute on function public.create_invite(uuid, text), public.redeem_invite(text)
  to authenticated;

-- ============================================================ ٣) الصلاحيات

-- بيقدر يأكّد نيابةً عن المريض ده؟ — علاقة مقبولة و`can_confirm`.
create or replace function private.can_confirm_for(p_patient uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.care_relationships cr
    where cr.patient_uuid = p_patient
      and cr.caregiver_id = (select auth.uid())
      and cr.status = 'accepted'
      and cr.can_confirm
  );
$$;

-- الحدث ده بتاع المريض ده، ولسه مش مؤكَّد، وميعاده جه (أو فات)؟
-- **الميعاد شرط**: تأكيد جرعة لسه ما جاش وقتها مش تأكيد.
create or replace function private.dose_confirmable(p_event uuid, p_patient uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.dose_events ev
    join public.dose_schedules s on s.uuid = ev.dose_schedule_uuid
    join public.medications    m on m.uuid = s.medication_uuid
    where ev.uuid = p_event
      and m.patient_uuid = p_patient
      and ev.state in ('pending', 'missed')
      and ev.scheduled_at <= now() + interval '5 minutes'
  );
$$;

revoke execute on function private.can_confirm_for(uuid), private.dose_confirmable(uuid, uuid)
  from anon, public;
grant execute on function private.can_confirm_for(uuid), private.dose_confirmable(uuid, uuid)
  to authenticated;

-- ============================================================ ٤) التأكيد نيابةً

create table if not exists public.proxy_confirmations (
  uuid            uuid primary key default gen_random_uuid(),
  dose_event_uuid uuid not null references public.dose_events (uuid) on delete cascade,
  patient_uuid    uuid not null references public.patients (uuid) on delete cascade,
  actor_id        uuid not null references auth.users (id) on delete cascade,
  actor_name      text,
  confirmed_at    timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  -- تأكيد واحد لكل حدث — التاني بيتقابل بخطأ، مش بصف تاني
  unique (dose_event_uuid)
);

create index if not exists proxy_confirmations_patient_idx
  on public.proxy_confirmations (patient_uuid, confirmed_at desc);

alter table public.proxy_confirmations enable row level security;
revoke all on public.proxy_confirmations from anon, public;
grant select, insert on public.proxy_confirmations to authenticated;

-- الدائرة كلها بتشوفه (المريض بيسحبه، والباقي بيشوف مين أكّد).
drop policy if exists proxy_confirmations_select on public.proxy_confirmations;
create policy proxy_confirmations_select on public.proxy_confirmations
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

-- الإدخال للممرض المسموح له، على حدث مستحق لنفس المريض، وباسمه هو.
-- **مفيش update ولا delete لحد**: التأكيد قرار اتسجّل بصاحبه ووقته.
drop policy if exists proxy_confirmations_insert on public.proxy_confirmations;
create policy proxy_confirmations_insert on public.proxy_confirmations
  for insert to authenticated
  with check (
    actor_id = (select auth.uid())
    and private.can_confirm_for(patient_uuid)
    and private.dose_confirmable(dose_event_uuid, patient_uuid)
  );

-- ============================================================ ٥) الاختيار
--
-- نفس ٠٠٢٠ بالحرف + شرط واحد: حدث عليه تأكيد نيابةً مش «ما اتأخدتش».
-- التعريف الوحيد لـ«مين يستاهل تنبيه» — مفيش نسخة تانية في أي مكان.
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
    and private.follower_subscription_active(cr.caregiver_id)
    -- 0023: أكّدها ممرض بداله = اتأخدت، حتى لو موبايل الأب لسه ما سحبش
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

-- ============================================================ ٦) إدارة الدائرة (للمالك)

-- المتابعين بأدوارهم وصلاحياتهم — للمالك بس. سياسات بوستجرس على مستوى
-- الصف مش العمود، فدي دالة ترجّع الأعمدة دي وبس (زي `followers_of_patient`).
create or replace function public.followers_with_permissions(p_patient_uuid uuid)
returns table (
  caregiver_id   uuid,
  display_name   text,
  relation       text,
  relation_other text,
  role           text,
  can_confirm    boolean,
  can_edit_meds  boolean,
  linked_at      timestamptz
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.owns_patient(p_patient_uuid) then
    raise exception 'not_owner';
  end if;
  return query
    select cr.caregiver_id, cp.display_name, cp.relation, cp.relation_other,
           cr.role, cr.can_confirm, cr.can_edit_meds, cr.created_at
    from public.care_relationships cr
    left join public.caregiver_preferences cp
      on cp.caregiver_id = cr.caregiver_id and cp.patient_uuid = cr.patient_uuid
    where cr.patient_uuid = p_patient_uuid
      and cr.status = 'accepted'
    order by cr.created_at;
end;
$$;

-- تغيير الدور والصلاحيات — للمالك بس. `can_confirm` بيتبعت صراحةً: تغيير
-- الدور لممرض ما بيفتحش التأكيد لوحده وقت التعديل، القرار للأب.
create or replace function public.set_follower_permissions(
  p_patient_uuid uuid,
  p_caregiver_id uuid,
  p_role text,
  p_can_confirm boolean,
  p_can_edit_meds boolean
)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.owns_patient(p_patient_uuid) then
    raise exception 'not_owner';
  end if;
  if p_role not in ('follower', 'nurse') then
    raise exception 'bad_role';
  end if;
  update public.care_relationships
     set role = p_role, can_confirm = p_can_confirm, can_edit_meds = p_can_edit_meds
   where patient_uuid = p_patient_uuid
     and caregiver_id = p_caregiver_id
     and status = 'accepted';
  if not found then
    raise exception 'not_linked';
  end if;
end;
$$;

-- شيل متابع: العلاقة بتبقى `revoked` (زي ما كانت من ٠٠٠٣)، مش بتتمسح —
-- كود جديد من الأب بيرجّعها.
create or replace function public.remove_follower(p_patient_uuid uuid, p_caregiver_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.owns_patient(p_patient_uuid) then
    raise exception 'not_owner';
  end if;
  update public.care_relationships
     set status = 'revoked', can_confirm = false, can_edit_meds = false
   where patient_uuid = p_patient_uuid
     and caregiver_id = p_caregiver_id;
end;
$$;

revoke execute on function public.followers_with_permissions(uuid),
                           public.set_follower_permissions(uuid, uuid, text, boolean, boolean),
                           public.remove_follower(uuid, uuid)
  from anon, public;
grant execute on function public.followers_with_permissions(uuid),
                          public.set_follower_permissions(uuid, uuid, text, boolean, boolean),
                          public.remove_follower(uuid, uuid)
  to authenticated;

-- ============================================================ فحص ذاتي
--
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله
-- يترجع. **والمالك بيتعمل في `auth.users` الأول** (درس ٠٠١٦).
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_quiet    uuid := gen_random_uuid();   -- ممرض من غير can_confirm
  v_son      uuid := gen_random_uuid();   -- متابع عادي
  v_owner2   uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_pat2     uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_sched    uuid := gen_random_uuid();
  v_due      uuid := gen_random_uuid();   -- مستحق
  v_future   uuid := gen_random_uuid();   -- لسه جاي
  v_med2     uuid := gen_random_uuid();
  v_sched2   uuid := gen_random_uuid();
  v_other    uuid := gen_random_uuid();   -- حدث مريض تاني
  v_n        integer;
  v_denied   boolean;
  v_code     text;
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'care_relationships'
                   and column_name = 'can_confirm') then
    raise exception 'FAIL 0023: care_relationships.can_confirm مش موجود';
  end if;
  if to_regclass('public.proxy_confirmations') is null then
    raise exception 'FAIL 0023: proxy_confirmations مش موجود';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner,  'owner-'  || v_owner  || '@0023.check'),
      (v_owner2, 'owner2-' || v_owner2 || '@0023.check'),
      (v_nurse,  'nurse-'  || v_nurse  || '@0023.check'),
      (v_quiet,  'quiet-'  || v_quiet  || '@0023.check'),
      (v_son,    'son-'    || v_son    || '@0023.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0023'), (v_pat2, v_owner2, '0023b');

    -- المتابع القديم: الافتراضيات بتسيبه زي ما هو
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');
    if (select role from public.care_relationships where caregiver_id = v_son) <> 'follower'
       or (select can_confirm from public.care_relationships where caregiver_id = v_son) then
      raise exception 'FAIL 0023: المتابع الموجود اتغيّر';
    end if;

    -- الممرض بيدخل بكود دوره «ممرض»، والصلاحية بتيجي مع الكود
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    v_code := public.create_invite(v_pat, 'nurse');
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    perform public.redeem_invite(v_code);
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if not exists (select 1 from public.care_relationships
                   where caregiver_id = v_nurse and role = 'nurse' and can_confirm and not can_edit_meds) then
      raise exception 'FAIL 0023: الممرض ما دخلش بدوره وصلاحيته';
    end if;
    -- ممرض تاني اتقفلت منه صلاحية التأكيد
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm)
      values (v_pat, v_quiet, 'accepted', 'nurse', false);

    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor'), (v_med2, v_pat2, 'Other');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
      values (v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date),
             (v_sched2, v_med2, 'anchor', 'breakfast', -30, 'daily', current_date);
    insert into public.dose_events (uuid, dose_schedule_uuid, routine_day, scheduled_at, state) values
      (v_due,    v_sched,  current_date, now() - interval '90 minutes', 'pending'),
      (v_future, v_sched,  current_date, now() + interval '3 hours',    'pending'),
      (v_other,  v_sched2, current_date, now() - interval '90 minutes', 'pending');

    -- قبل التأكيد: الحدث المستحق بيتصعّد
    select count(*) into v_n from private.due_escalations() d where d.dose_event_uuid = v_due;
    if v_n < 1 then raise exception 'FAIL 0023: الحدث المستحق مش في التصعيد قبل التأكيد'; end if;

    -- ١) الممرض المسموح له بيأكّد الحدث المستحق
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id, actor_name)
      values (v_due, v_pat, v_nurse, 'سارة');

    -- ٢) بس مش حدث لسه جاي
    v_denied := false;
    begin
      insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id, actor_name)
        values (v_future, v_pat, v_nurse, 'سارة');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0023: جرعة لسه جاية اتأكّدت'; end if;

    -- ٣) ولا حدث مريض تاني
    v_denied := false;
    begin
      insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id, actor_name)
        values (v_other, v_pat2, v_nurse, 'سارة');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0023: أكّد جرعة مريض تاني'; end if;

    -- ٤) ولا باسم حد تاني
    v_denied := false;
    begin
      insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id, actor_name)
        values (v_other, v_pat, v_son, 'سارة');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0023: كتب باسم حد تاني'; end if;

    -- ٥) الممرض من غير can_confirm مرفوض
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_quiet)::text, true);
    execute 'set local role authenticated';
    delete from public.proxy_confirmations where false; -- لا شيء: الجدول مفيهوش delete أصلاً
    v_denied := false;
    begin
      insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id, actor_name)
        values (v_other, v_pat, v_quiet, 'ممرض');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0023: ممرض من غير صلاحية أكّد'; end if;

    -- ٦) المتابع العادي مرفوض
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id, actor_name)
        values (v_other, v_pat, v_son, 'ابن');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0023: المتابع كتب تأكيد'; end if;
    -- بس بيشوف تأكيد الممرض
    select count(*) into v_n from public.proxy_confirmations where patient_uuid = v_pat;
    if v_n <> 1 then raise exception 'FAIL 0023: المتابع مش شايف التأكيد (%)', v_n; end if;

    -- ٧) المالك بيشوفه (ده اللي موبايله بيسحبه)، والغريب لأ
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.proxy_confirmations where patient_uuid = v_pat;
    if v_n <> 1 then raise exception 'FAIL 0023: الأب مش شايف التأكيد (%)', v_n; end if;
    -- والمالك بيدير الدائرة
    select count(*) into v_n from public.followers_with_permissions(v_pat) f where f.role = 'nurse';
    if v_n <> 2 then raise exception 'FAIL 0023: قايمة الصلاحيات غلط (%)', v_n; end if;
    perform public.set_follower_permissions(v_pat, v_son, 'nurse', true, true);
    if not exists (select 1 from public.care_relationships
                   where caregiver_id = v_son and role = 'nurse' and can_confirm and can_edit_meds) then
      raise exception 'FAIL 0023: تغيير الصلاحيات ما اتكتبش';
    end if;
    perform public.remove_follower(v_pat, v_quiet);
    if (select status from public.care_relationships where caregiver_id = v_quiet) <> 'revoked' then
      raise exception 'FAIL 0023: الشيل ما اتكتبش';
    end if;

    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner2)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.proxy_confirmations where patient_uuid = v_pat;
    if v_n <> 0 then raise exception 'FAIL 0023: مالك تاني شاف تأكيد مش بتاعه (%)', v_n; end if;
    v_denied := false;
    begin
      perform public.set_follower_permissions(v_pat, v_son, 'follower', false, false);
    exception when others then
      if sqlerrm <> 'not_owner' then raise; end if;
      v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0023: غير المالك غيّر صلاحيات'; end if;

    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);

    -- ٨) السيرفر بيعتبرها مؤكَّدة: الحدث خرج من التصعيد
    select count(*) into v_n from private.due_escalations() d where d.dose_event_uuid = v_due;
    if v_n <> 0 then raise exception 'FAIL 0023: التصعيد لسه شايف حدث اتأكّد نيابةً'; end if;

    raise exception '0023_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0023_ROLLBACK' then raise; end if;
  end;

  raise notice '0023 OK — الممرض بيأكّد بداله على المستحق بس، والمتابع والغريب لأ، والتصعيد بيعتبرها مؤكَّدة';
end $$;
