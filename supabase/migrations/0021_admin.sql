-- 0021_admin.sql — لوحة الأدمن: قايمة سماح بالإيميل، وأربع دوال قراية بس.
--
-- **اللي الأدمن بيشوفه هو «المنتج شغّال ولا لأ»، مش «المريض بياخد إيه».**
-- ولا دالة هنا بترجّع اسم دوا، ولا سجل، ولا نتيجة تحليل، ولا قياس، ولا
-- بيانات طوارئ، ولا رقم تليفون. قايمة الأعمدة في كل `returns table`
-- **مقفولة** — ودي هي الحدود نفسها، مش تعليق عليها: عمود جديد معناه
-- قرار جديد في ملف جديد بترقيمه.
--
-- **الهوية هنا بالإيميل، مش بـ`auth.uid()`** — وده أول مكان في المشروع
-- بينده `auth.jwt()`. السبب: قايمة السماح دي **قايمة ناس**، مش قايمة
-- معرّفات مستخدمين؛ والدخول المجهول بيولّد مستخدم جديد كل مرة (الدين ٢)،
-- فمعرّف مخزّن كان هيبوظ من غير ما حد يلاحظ. و`is_admin()` بترفض أي جلسة
-- مجهولة حتى لو الإيميل في القايمة.
--
-- **مفيش `updated_at` على `private.admins`، وبالتالي مفيش moddatetime** —
-- قايمة سماح بتتزوّد وبتتشال، ما بتتعدّلش. متكتوب هنا عشان محدش يزوّد
-- تريجر «عشان التناسق».
--
-- كل حاجة `if not exists` / `create or replace`، فالسلسلة تعيد التشغيل
-- بأمان.

-- ============================================================ ١) قايمة السماح

create table if not exists private.admins (
  email      text primary key check (email = lower(email)),
  created_at timestamptz not null default now()
);

-- `private` مش معروضة لـPostgREST أصلاً — ودي الحزام التاني.
alter table private.admins enable row level security;
revoke all on table private.admins from anon, authenticated, public;

-- الملف ده **ما بيزرعش أي إيميل**. الإضافة بالإيد في محرر SQL:
--   insert into private.admins (email) values (lower('OWNER_EMAIL_HERE'))
--   on conflict (email) do nothing;

-- ============================================================ ٢) الحارس

-- أدمن = إيميل في القايمة **و** الجلسة مش مجهولة.
-- الشرطين مطلوبين: جلسة مجهولة ملهاش إيميل غالباً، بس لو claim اتحطّ
-- بإيميل معروف من غير الشرط ده كان هيعدّي.
create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
     and exists (
           select 1 from private.admins a
           where a.email = lower(coalesce(auth.jwt() ->> 'email', ''))
         );
$$;

revoke all on function private.is_admin() from anon, authenticated, public;

-- ============================================================ ٣) الأرقام

-- **تعريف واحد لكل رقم**، خاص ومن غير حارس — الحارس في الغلاف العام.
-- نفس شكل `private.broken_devices()` في ٠٠١٨: محدش بيقدر يناديها إلا
-- الدوال اللي تحت (definer).
create or replace function private.admin_account_rows()
returns table (
  patient_uuid        uuid,
  patient_name        text,
  created_at          timestamptz,
  followers_count     bigint,
  pending_invites     bigint,
  last_sync_at        timestamptz,
  platform            text,
  app_version         text,
  battery_state       text,
  reminder_horizon_ok boolean,
  seen_at             timestamptz,
  missed_doses_24h    bigint,
  pending_escalations bigint,
  escalations_7d      bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  -- آخر نبضة لكل مريض. الجهاز ممكن يكون أكتر من تنزيلة — اللي بيهمّ
  -- الأحدث، لأن السؤال هو «الموبايل اللي شغّال عليه دلوقتي عامل إيه».
  with dev as (
    select distinct on (h.patient_uuid)
           h.patient_uuid as pat,
           h.platform     as platform,
           h.app_version  as app_version,
           h.battery_state as battery_state,
           h.horizon_until as horizon_until,
           h.checked_at    as checked_at
    from public.device_health h
    order by h.patient_uuid, h.checked_at desc
  ),
  -- أحداث الجرعات مربوطة بمريضها — الاسم عمره ما بيتقري من هنا.
  ev as (
    select m.patient_uuid as pat,
           e.uuid         as event_uuid,
           e.state        as state,
           e.scheduled_at as scheduled_at,
           e.updated_at   as updated_at
    from public.dose_events e
    join public.dose_schedules s on s.uuid = e.dose_schedule_uuid
    join public.medications    m on m.uuid = s.medication_uuid
  ),
  esc as (
    select ev.pat            as pat,
           x.created_at      as created_at,
           x.delivery_status as delivery_status,
           ev.state          as state
    from public.escalations x
    join ev on ev.event_uuid = x.dose_event_uuid
  )
  select
    p.uuid,
    p.name,
    p.created_at,
    -- متابع = علاقة مقبولة. `pending` دعوة لسه ما اتقبلتش.
    (select count(*) from public.care_relationships cr
      where cr.patient_uuid = p.uuid and cr.status = 'accepted'),
    -- كود ربط لسه صالح وما اتستعملش
    (select count(*) from public.invite_codes ic
      where ic.patient_uuid = p.uuid
        and ic.used_at is null
        and ic.expires_at > now()),
    -- **آخر مزامنة من ختم السيرفر**، مش من `device_health.last_sync_at`
    -- (دي دعوى الجهاز عن نفسه). `updated_at` بتتحطّ بـmoddatetime.
    greatest(
      p.updated_at,
      (select max(m.updated_at) from public.medications m where m.patient_uuid = p.uuid),
      (select max(e.updated_at) from ev e where e.pat = p.uuid)
    ),
    d.platform,
    d.app_version,
    d.battery_state,
    -- مفيش نبضة = مش تمام. الغياب أخطر من أي كود (قاعدة ٠٠١٨).
    coalesce(d.horizon_until > now(), false),
    d.checked_at,
    -- **نفس اختيار السيرفر بالظبط**: ما اتأكدتش، وعدّى عليها مهلة
    -- السيرفر. لو الرقمين اختلفوا، الأدمن بيقرا دنيا تانية غير الكرون.
    (select count(*) from ev e
      where e.pat = p.uuid
        and e.state in ('pending', 'missed')
        and e.scheduled_at >= now() - interval '24 hours'
        and e.scheduled_at <= now() - private.server_grace_window()),
    -- تنبيه اتقرر (اتبعت/مفيش توكن/فشل) والجرعة لسه مفتوحة.
    -- `claimed` لسه في الطريق — مش قرار (٠٠٠٩).
    (select count(*) from esc x
      where x.pat = p.uuid
        and x.created_at > now() - interval '48 hours'
        and x.delivery_status <> 'claimed'
        and x.state in ('pending', 'missed')),
    (select count(*) from esc x
      where x.pat = p.uuid and x.created_at > now() - interval '7 days')
  from public.patients p
  left join dev d on d.pat = p.uuid
  order by p.created_at desc
$$;

revoke all on function private.admin_account_rows() from anon, authenticated, public;

-- ============================================================ ٤) الأغلفة العامة

-- `private` مش معروضة لـPostgREST (نفس سبب ٠٠٠٧)، فالتطبيق بينده أغلفة
-- في `public`. كل واحدة بتبدأ بالحارس ومفيش غيره.

create or replace function public.admin_accounts()
returns table (
  patient_uuid        uuid,
  patient_name        text,
  created_at          timestamptz,
  followers_count     bigint,
  pending_invites     bigint,
  last_sync_at        timestamptz,
  platform            text,
  app_version         text,
  battery_state       text,
  reminder_horizon_ok boolean,
  seen_at             timestamptz,
  missed_doses_24h    bigint,
  pending_escalations bigint,
  escalations_7d      bigint
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
  return query select * from private.admin_account_rows();
end;
$$;

-- الأرقام الأربعة **محسوبة من نفس الصفوف** — فالشريط والجدول ما يقدروش
-- يختلفوا.
create or replace function public.admin_counts()
returns table (
  total_patients     bigint,
  total_followers    bigint,
  active_7d          bigint,
  battery_restricted bigint
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
      count(*) filter (where r.battery_state = 'restricted')
    from private.admin_account_rows() r;
end;
$$;

-- الاسم والصلة والحالة — **من غير ساعات الهدوء ومن غير نطاق التنبيه**.
-- دول تفضيلات المتابع نفسه (٠٠٢٠)، ومالهمش لازمة في لوحة تشغيل.
create or replace function public.admin_patient_followers(p_patient_uuid uuid)
returns table (
  display_name text,
  relation     text,
  status       text,
  linked_at    timestamptz
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
      cp.display_name,
      case when cp.relation = 'other'
           then coalesce(nullif(btrim(cp.relation_other), ''), 'other')
           else cp.relation end,
      cr.status,
      cr.created_at
    from public.care_relationships cr
    left join public.caregiver_preferences cp
      on cp.caregiver_id = cr.caregiver_id
     and cp.patient_uuid = cr.patient_uuid
    where cr.patient_uuid = p_patient_uuid
    order by cr.created_at desc;
end;
$$;

-- حالة التسليم بس. الجرعة بتتوصل بالانضمام عشان وقتها، **ومفيش عمود
-- دوا في الاختيار**.
create or replace function public.admin_patient_escalations(
  p_patient_uuid uuid,
  p_limit        integer default 20
)
returns table (
  scheduled_at    timestamptz,
  rung            text,
  delivery_status text,
  created_at      timestamptz
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
    select e.scheduled_at, x.rung, x.delivery_status, x.created_at
    from public.escalations x
    join public.dose_events    e on e.uuid = x.dose_event_uuid
    join public.dose_schedules s on s.uuid = e.dose_schedule_uuid
    join public.medications    m on m.uuid = s.medication_uuid
    where m.patient_uuid = p_patient_uuid
    order by x.created_at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

revoke all on function public.admin_accounts()                     from anon, public;
revoke all on function public.admin_counts()                       from anon, public;
revoke all on function public.admin_patient_followers(uuid)        from anon, public;
revoke all on function public.admin_patient_escalations(uuid, integer) from anon, public;

grant execute on function public.admin_accounts()                     to authenticated;
grant execute on function public.admin_counts()                       to authenticated;
grant execute on function public.admin_patient_followers(uuid)        to authenticated;
grant execute on function public.admin_patient_escalations(uuid, integer) to authenticated;

-- ============================================================ فحص ذاتي
--
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله
-- يترجع. **والمالك بيتعمل في `auth.users` الأول** — `patients.owner_id`
-- مفتاح أجنبي عليه (درس ٠٠١٦).
do $$
declare
  v_owner  uuid := gen_random_uuid();
  v_admin  uuid := gen_random_uuid();
  v_son    uuid := gen_random_uuid();
  v_pat    uuid := gen_random_uuid();
  v_med    uuid := gen_random_uuid();
  v_sched  uuid := gen_random_uuid();
  v_event  uuid := gen_random_uuid();
  v_mail   text;
  v_n      bigint;
  v_denied boolean;
  v_row    record;
begin
  -- القايدة موجودة ومقفولة
  if to_regclass('private.admins') is null then
    raise exception 'FAIL 0021: private.admins مش موجود';
  end if;
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'private' and c.relname = 'admins' and c.relrowsecurity) then
    raise exception 'FAIL 0021: RLS مش مفعّل على private.admins';
  end if;

  begin
    v_mail := 'admin-' || v_admin || '@0021.check';

    insert into auth.users (id, email) values
      (v_owner, 'owner-' || v_owner || '@0021.check'),
      (v_admin, v_mail),
      (v_son,   'son-'   || v_son   || '@0021.check');

    insert into private.admins (email) values (lower(v_mail));

    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, 'تأكيد 0021');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');
    insert into public.caregiver_preferences (caregiver_id, patient_uuid, display_name, relation)
      values (v_son, v_pat, 'محمد', 'son');

    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor,
                                       offset_minutes, repeat, start_date)
      values (v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date);
    -- ساعتين فاتوا: جوّه الـ٢٤ ساعة، وعدّى مهلة السيرفر (٦٠ د)
    insert into public.dose_events (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
      values (v_event, v_sched, current_date, now() - interval '2 hours', 'pending');
    insert into public.escalations (dose_event_uuid, caregiver_id, delivery_status)
      values (v_event, v_son, 'sent');

    -- جهاز: بطارية مقيّدة، والمدى خلص
    insert into public.device_health
      (patient_uuid, install_id, platform, app_version, battery_state,
       horizon_until, checked_at)
      values (v_pat, 'install-0021', 'android', '1.0.0+1', 'restricted',
              now() - interval '1 hour', now());

    -- ١) الأدمن بيشوف الأرقام
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'email', v_mail, 'is_anonymous', false)::text, true);
    execute 'set local role authenticated';

    select * into v_row from public.admin_accounts() where patient_uuid = v_pat;
    if v_row is null then
      raise exception 'FAIL 0021: الأدمن مش شايف الحساب';
    end if;
    if v_row.missed_doses_24h <> 1 then
      raise exception 'FAIL 0021: الجرعة المفتوحة ما اتعدّتش (%)', v_row.missed_doses_24h;
    end if;
    if v_row.followers_count <> 1 then
      raise exception 'FAIL 0021: المتابع ما اتعدّش (%)', v_row.followers_count;
    end if;
    if v_row.reminder_horizon_ok then
      raise exception 'FAIL 0021: مدى خلصان اتحسب تمام';
    end if;
    if v_row.battery_state <> 'restricted' then
      raise exception 'FAIL 0021: حالة البطارية ما وصلتش (%)', v_row.battery_state;
    end if;
    if v_row.pending_escalations <> 1 or v_row.escalations_7d <> 1 then
      raise exception 'FAIL 0021: عدّ التنبيهات غلط (% و%)',
        v_row.pending_escalations, v_row.escalations_7d;
    end if;
    if v_row.last_sync_at is null then
      raise exception 'FAIL 0021: آخر مزامنة فاضية';
    end if;

    select count(*) into v_n from public.admin_counts() c where c.battery_restricted >= 1;
    if v_n <> 1 then
      raise exception 'FAIL 0021: العدّادات ما شافتش البطارية المقيّدة';
    end if;

    select count(*) into v_n from public.admin_patient_followers(v_pat)
      where display_name = 'محمد' and relation = 'son' and status = 'accepted';
    if v_n <> 1 then
      raise exception 'FAIL 0021: المتابعين مش راجعين صح (%)', v_n;
    end if;

    select count(*) into v_n from public.admin_patient_escalations(v_pat)
      where delivery_status = 'sent';
    if v_n <> 1 then
      raise exception 'FAIL 0021: التنبيهات مش راجعة (%)', v_n;
    end if;

    -- ٢) **نفس الإيميل بس جلسة مجهولة** → مرفوض. النص التاني من الحارس
    -- مش مكتوب وبس — متجرّب.
    execute 'reset role';
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'email', v_mail, 'is_anonymous', true)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      perform public.admin_counts();
    exception when others then
      if sqlerrm <> 'not admin' then raise; end if;
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0021: جلسة مجهولة بإيميل أدمن عدّت';
    end if;

    -- ٣) مستخدم عادي مش في القايمة → «not admin»
    execute 'reset role';
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_son, 'email', 'son-' || v_son || '@0021.check',
                        'is_anonymous', false)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      perform public.admin_accounts();
    exception when others then
      if sqlerrm <> 'not admin' then raise; end if;
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0021: مستخدم مش أدمن قرا الحسابات';
    end if;

    -- ٤) anon مقفول عند الصلاحية نفسها، قبل ما الحارس يشتغل أصلاً
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    execute 'set local role anon';
    v_denied := false;
    begin
      perform public.admin_counts();
    exception when insufficient_privilege then
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0021: anon قدر ينده الدالة';
    end if;

    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);

    raise exception '0021_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0021_ROLLBACK' then raise; end if;
  end;

  raise notice '0021 OK — الأدمن بالإيميل يشوف الأرقام، وغيره «not admin»، وanon مقفول خالص';
end $$;
