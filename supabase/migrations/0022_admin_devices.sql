-- 0022_admin_devices.sql — اللوحة بتشوف أكواد السلامة بتاعة كل جهاز.
--
-- **قاعدة المالك (٢٤ سبتمبر ٢٠٢٦): المريض ما يشوفش مشكلة تقنية أبداً.**
-- يا التطبيق بيصلّحها لوحده في صمت، يا بتتبلّغ للوحة الأدمن. النبضة
-- (`0018`) كانت بترفع `failing_codes` من زمان — الحلقة الناقصة كانت إن
-- اللوحة ما بتقراهاش: `private.broken_devices` من `0018` مش معروضة
-- لـPostgREST ولا ليها غلاف. ده الغلاف.
--
-- **قراية بس، وبنفس حدود 0021**: `returns table` بقايمة أعمدة مقفولة،
-- ولا عمود فيها بيقول اسم دوا ولا سجل ولا قياس ولا بيانات طوارئ — أكواد
-- سلامة وأرقام عدّ وأختام وقت. عمود جديد = ترحيل جديد.
--
-- بترجّع **كل** صف في `device_health`، مش المكسور بس: اللوحة هي اللي
-- بتقرر «فيه مشكلة» (أكواد موجودة، أو نبضة أقدم من ٢٤ ساعة) عشان الجملة
-- «ماوصلش منه حاجة من {مدة}» تتحسب بساعة الأدمن مش بساعة السيرفر وقت
-- الاستعلام.
--
-- كل حاجة `create or replace`، فالسلسلة تعيد التشغيل بأمان.

-- ============================================================ ١) الغلاف

create or replace function public.admin_devices()
returns table (
  patient_uuid     uuid,
  patient_name     text,
  install_id       text,
  checked_at       timestamptz,
  platform         text,
  app_version      text,
  os_version       text,
  notif_permission text,
  pending_count    int,
  horizon_until    timestamptz,
  has_token        boolean,
  has_caregiver    boolean,
  last_sync_at     timestamptz,
  dirty_count      int,
  battery_state    text,
  failing_codes    text[]
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
      h.patient_uuid,
      p.name,
      h.install_id,
      h.checked_at,
      h.platform,
      h.app_version,
      h.os_version,
      h.notif_permission,
      h.pending_count,
      h.horizon_until,
      h.has_token,
      h.has_caregiver,
      h.last_sync_at,
      h.dirty_count,
      h.battery_state,
      h.failing_codes
    from public.device_health h
    join public.patients p on p.uuid = h.patient_uuid
    order by h.checked_at desc;
end;
$$;

-- نفس شكل 0021: anon مقفول عند الصلاحية نفسها، وauthenticated بيوصل
-- للحارس اللي بيقول «not admin».
revoke all on function public.admin_devices() from anon, public;
grant execute on function public.admin_devices() to authenticated;

-- ============================================================ فحص ذاتي
--
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله
-- يترجع. **والمالك بيتعمل في `auth.users` الأول** — `patients.owner_id`
-- مفتاح أجنبي عليه (درس ٠٠١٦).
do $$
declare
  v_owner  uuid := gen_random_uuid();
  v_admin  uuid := gen_random_uuid();
  v_other  uuid := gen_random_uuid();
  v_pat    uuid := gen_random_uuid();
  v_mail   text;
  v_n      bigint;
  v_denied boolean;
  v_row    record;
begin
  if to_regclass('public.device_health') is null then
    raise exception 'FAIL 0022: device_health مش موجود — شغّل 0018 الأول';
  end if;
  if to_regprocedure('private.is_admin()') is null then
    raise exception 'FAIL 0022: private.is_admin مش موجودة — شغّل 0021 الأول';
  end if;

  begin
    v_mail := 'admin-' || v_admin || '@0022.check';

    insert into auth.users (id, email) values
      (v_owner, 'owner-' || v_owner || '@0022.check'),
      (v_admin, v_mail),
      (v_other, 'other-' || v_other || '@0022.check');

    insert into private.admins (email) values (lower(v_mail));

    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, 'تأكيد 0022');

    insert into public.device_health
      (patient_uuid, install_id, platform, app_version, notif_permission,
       battery_state, dirty_count, failing_codes, checked_at)
      values (v_pat, 'install-0022', 'android', '1.0.0+1', 'denied',
              'restricted', 4, array['notificationPermission', 'staleSync'], now());

    -- ١) الأدمن بيشوف الصف بأكواده
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'email', v_mail, 'is_anonymous', false)::text, true);
    execute 'set local role authenticated';

    select * into v_row from public.admin_devices() d where d.patient_uuid = v_pat;
    if v_row is null then
      raise exception 'FAIL 0022: الأدمن مش شايف الجهاز';
    end if;
    if v_row.patient_name <> 'تأكيد 0022' then
      raise exception 'FAIL 0022: اسم المريض ما وصلش (%)', v_row.patient_name;
    end if;
    if not (v_row.failing_codes @> array['notificationPermission', 'staleSync']) then
      raise exception 'FAIL 0022: الأكواد ما وصلتش (%)', v_row.failing_codes;
    end if;
    if v_row.dirty_count <> 4 or v_row.notif_permission <> 'denied' then
      raise exception 'FAIL 0022: أعمدة النبضة ما وصلتش';
    end if;

    -- ٢) نفس الإيميل بجلسة مجهولة → مرفوض
    execute 'reset role';
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'email', v_mail, 'is_anonymous', true)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      perform public.admin_devices();
    exception when others then
      if sqlerrm <> 'not admin' then raise; end if;
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0022: جلسة مجهولة بإيميل أدمن عدّت';
    end if;

    -- ٣) مستخدم عادي → «not admin»
    execute 'reset role';
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_other, 'email', 'other-' || v_other || '@0022.check',
                        'is_anonymous', false)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      perform public.admin_devices();
    exception when others then
      if sqlerrm <> 'not admin' then raise; end if;
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0022: مستخدم مش أدمن قرا الأجهزة';
    end if;

    -- ٤) anon مقفول عند الصلاحية نفسها
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    execute 'set local role anon';
    v_denied := false;
    begin
      perform public.admin_devices();
    exception when insufficient_privilege then
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0022: anon قدر ينده الدالة';
    end if;

    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);

    raise exception '0022_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0022_ROLLBACK' then raise; end if;
  end;

  raise notice '0022 OK — الأدمن بيشوف أكواد كل جهاز، وغيره «not admin»، وanon مقفول';
end $$;
