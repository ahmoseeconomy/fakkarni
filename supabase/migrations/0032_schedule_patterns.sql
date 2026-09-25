-- ============================================================================
-- 0032 — أنماط الأيام على dose_schedules (ملف بس — ما اتطبّقش)
-- ============================================================================
-- الجولة ٢ من أنماط الجدولة (docs/schedule_patterns_audit.md): «أيام معيّنة»
-- و«كل كام يوم» و«فترة وراحة». **الأيام بس** — الدقيقة لسه من المرساة أو
-- الساعة الثابتة، والحساب على موبايل المريض من `start_date`.
--
-- أربع أعمدة، كلهم null = «كل يوم» — فكل صف قديم صالح زي ما هو:
--   weekdays   — بت لكل يوم (الاتنين = البت ٠ … الحد = البت ٦)، ١..١٢٧
--   every_days — كل كام يوم، ٢..٣٠
--   cycle_on / cycle_off — فترة وراحة، ١..٩٠ لكل واحد، **الاتنين مع بعض**
-- ونمط واحد بس على الصف.
--
-- **`due_escalations` ما بتتغيّرش**: بتقرا `dose_events`، واليوم المقفول ما
-- بيطلعش منه حدث أصلاً على موبايل المريض. ومفيش سياسة جديدة: الأعمدة على صف
-- `dose_schedules` اللي سياساته (0002) بتدّي القراية للدائرة والكتابة للمالك.
--
-- لحد ما الملف ده يتشغّل: الموبايل بيرفع الجداول العادية بنفس الحمولة،
-- والجدول اللي بنمط بيفضل عنده (والتذكير شغّال) وبيتعاد لوحده، ولوحة
-- الأدمن بتشوف `patternSync`. الترتيب: بعد 0031. idempotent.

alter table public.dose_schedules add column if not exists weekdays   smallint;
alter table public.dose_schedules add column if not exists every_days smallint;
alter table public.dose_schedules add column if not exists cycle_on   smallint;
alter table public.dose_schedules add column if not exists cycle_off  smallint;

alter table public.dose_schedules drop constraint if exists dose_schedules_pattern_check;
alter table public.dose_schedules
  add constraint dose_schedules_pattern_check check (
    (weekdays is null or weekdays between 1 and 127)
    and (every_days is null or every_days between 2 and 30)
    and ((cycle_on is null) = (cycle_off is null))
    and (cycle_on is null or (cycle_on between 1 and 90 and cycle_off between 1 and 90))
    and ((weekdays is not null)::int + (every_days is not null)::int + (cycle_on is not null)::int) <= 1
  );

-- فحص ذاتي — من الجداول وRLS بس تحت `set local role authenticated`، ولا
-- نداء private.* في الدور ده.
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_plain    uuid := gen_random_uuid();
  v_week     uuid := gen_random_uuid();
  v_back     uuid;
  v_n        integer;
  v_denied   boolean;
begin
  begin
    -- المالك في auth.users **قبل** المريض — درس ٠٠١٦
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0032.check'),
      (v_son,      'son-'      || v_son      || '@0032.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0032.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0032');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    -- ١) صف قديم الشكل (من غير نمط) لسه صالح
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
      values (v_plain, v_med, 'anchor', 'breakfast', -30, 'daily', current_date)
      returning uuid into v_back;
    if v_back is distinct from v_plain then raise exception 'FAIL 0032: الصف العادي ما اتكتبش'; end if;
    -- ٢) السبت والتلات والخميس — بـRETURNING زي التطبيق (درس ٠٠٠٥)
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date, weekdays)
      values (v_week, v_med, 'anchor', 'dinner', 0, 'daily', current_date, (1 << 5) | (1 << 1) | (1 << 3))
      returning uuid into v_back;
    if v_back is distinct from v_week then raise exception 'FAIL 0032: جدول الأيام ما اتكتبش'; end if;
    -- ٣) نمطين على صف واحد، وراحة من غير فترة، وكل يوم واحد — مرفوضين
    v_denied := false;
    begin
      insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date, weekdays, every_days)
        values (gen_random_uuid(), v_med, 'anchor', 'lunch', 0, 'daily', current_date, 3, 2);
    exception when check_violation then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0032: نمطين على صف واحد عدّوا'; end if;
    v_denied := false;
    begin
      insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date, cycle_on)
        values (gen_random_uuid(), v_med, 'anchor', 'lunch', 0, 'daily', current_date, 21);
    exception when check_violation then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0032: فترة من غير راحة عدّت'; end if;
    v_denied := false;
    begin
      insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date, every_days)
        values (gen_random_uuid(), v_med, 'anchor', 'lunch', 0, 'daily', current_date, 1);
    exception when check_violation then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0032: كل يوم واحد عدّى كـevery_days'; end if;
    execute 'reset role';

    -- ٤) الابن بيقرا النمط وما بيعدّلوش
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.dose_schedules where uuid = v_week and weekdays = 42;
    if v_n <> 1 then raise exception 'FAIL 0032: الابن مش شايف النمط'; end if;
    update public.dose_schedules set weekdays = 127 where uuid = v_week;  -- RLS: صفر صف
    execute 'reset role';
    if (select weekdays from public.dose_schedules where uuid = v_week) <> 42 then
      raise exception 'FAIL 0032: الابن عدّل النمط';
    end if;

    -- ٥) الغريب ما بيشوفش
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.dose_schedules where medication_uuid = v_med;
    execute 'reset role';
    if v_n <> 0 then raise exception 'FAIL 0032: غريب شاف الجداول'; end if;

    raise exception '0032_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0032_ROLLBACK' then raise; end if;
  end;

  raise notice '0032 OK — أنماط الأيام: الصفوف القديمة صالحة، نمط واحد بس، الابن بيقرا وما بيعدّلش، والغريب ما بيشوفش';
end $$;
