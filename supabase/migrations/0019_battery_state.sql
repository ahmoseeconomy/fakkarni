-- 0019 — حالة البطارية بتلات قيم، مش اتنين
--
-- `battery_state` بيتخزّن كـ text بقيمة من {unrestricted, restricted,
-- unknown}. **ليه عمود لوحده وليه تلات قيم**: «كله تمام» و«ما قدرناش
-- نبص» كانوا بيتبعتوا بنفس الشكل، فلو القناة اللي بتقرا الحالة بايظة
-- على ألف جهاز، الجدول كان هيقول إن الألف جهاز سليمين. الغياب لازم
-- يتعدّ لوحده.

alter table public.device_health
  add column if not exists battery_state text;

alter table public.device_health
  drop constraint if exists device_health_battery_state_check;

alter table public.device_health
  add constraint device_health_battery_state_check
  check (battery_state is null
         or battery_state in ('unrestricted', 'restricted', 'unknown'));

-- ============================================================ فحص ذاتي
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_state text;
begin
  begin
    insert into auth.users (id, email) values (v_owner, 'owner-' || v_owner || '@0019.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, 'تأكيد 0019');

    insert into public.device_health (patient_uuid, install_id, battery_state)
      values (v_pat, 'install-a', 'unknown');
    select battery_state into v_state
      from public.device_health where patient_uuid = v_pat;
    if v_state is distinct from 'unknown' then
      raise exception 'FAIL 0019: الحالة ما اتخزّنتش';
    end if;

    -- صف قديم من غير الحالة لسه صالح
    insert into public.device_health (patient_uuid, install_id)
      values (v_pat, 'install-b');

    -- وقيمة رابعة مرفوضة
    begin
      insert into public.device_health (patient_uuid, install_id, battery_state)
        values (v_pat, 'install-c', 'maybe');
      raise exception 'FAIL 0019: القيد قبل قيمة مش معروفة';
    exception when check_violation then
      null; -- ده المطلوب
    end;

    delete from public.patients where uuid = v_pat;
    delete from auth.users where id = v_owner;
    raise exception '0019_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0019_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0019 OK — تلات حالات للبطارية، والقديم من غير حالة لسه صالح';
end $$;
