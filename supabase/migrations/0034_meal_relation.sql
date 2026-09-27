-- ============================================================================
-- 0034 — «قبل الأكل» وأخواتها كلمة على الجدول (ملف بس — ما اتطبّقش، مستني مراجعة)
-- ============================================================================
-- الروتين والمراسي اتشالوا من التطبيق (قرار المالك، ٢٧ سبتمبر ٢٠٢٦): كل جرعة
-- بقت ساعة ثابتة، وعلاقة الأكل فضلت **كلمة تعليمات** ما بتحرّكش الساعة.
-- الموبايل بيبعتها في `dose_schedules.meal_relation` وجانب الابن والممرض
-- بيقروها جنب الساعة.
--
-- **ولا عمود بيتشال**: `anchor` و`offset_minutes` و`timing_kind` و
-- `day_routines` كلهم بيفضلوا زي ما هم (nullable من الأول) — الموبايل بس بطل
-- يكتب فيهم: كل صف جديد `timing_kind = 'fixed'` والمرساة null. صف قديم من
-- موبايل لسه ما اترقّاش بيتقري بكلمته من غير حساب ساعة.
--
-- **مالهاش علاقة بالتذكير ولا بالتصعيد**: `due_escalations` ما بتقراش العمود.
-- RLS زي ما هي: العمود على صف سياساته موجودة. الترتيب: بعد 0033. idempotent.

alter table public.dose_schedules
  add column if not exists meal_relation text
    check (meal_relation in ('before', 'with', 'after', 'empty_stomach'));

-- فحص ذاتي — الكتابة بالشكل الجديد (fixed + كلمة أكل) بتعدّي القيد القديم،
-- وكلمة غريبة بتترفض، والابن بيقراها. كله بيتلف رجوع.
do $$
declare
  v_owner  uuid := gen_random_uuid();
  v_son    uuid := gen_random_uuid();
  v_pat    uuid := gen_random_uuid();
  v_med    uuid := gen_random_uuid();
  v_sched  uuid := gen_random_uuid();
  v_n      integer;
  v_denied boolean;
begin
  begin
    -- المالك في auth.users **قبل** المريض — درس ٠٠١٦
    insert into auth.users (id, email) values
      (v_owner, 'owner-' || v_owner || '@0034.check'),
      (v_son,   'son-'   || v_son   || '@0034.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0034');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');

    -- ١) المالك بيكتب جدول بالشكل الجديد: ثابت + كلمة أكل، من غير مرساة
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, meal_relation, repeat, start_date)
      values (v_sched, v_med, 'fixed', null, null, 'after', 'daily', current_date)
      returning 1 into v_n;
    insert into public.fixed_timings (uuid, dose_schedule_uuid, minute_of_day) values (gen_random_uuid(), v_sched, 540);

    -- ٢) كلمة غريبة مرفوضة
    v_denied := false;
    begin
      update public.dose_schedules set meal_relation = 'breakfast' where uuid = v_sched;
    exception when check_violation then v_denied := true;
    end;
    execute 'reset role';
    if not v_denied then raise exception 'FAIL 0034: كلمة أكل غريبة اتقبلت'; end if;

    -- ٣) الابن بيقراها جنب الساعة
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.dose_schedules where uuid = v_sched and meal_relation = 'after';
    execute 'reset role';
    if v_n <> 1 then raise exception 'FAIL 0034: الابن مش شايف كلمة الأكل'; end if;

    raise exception '0034_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0034_ROLLBACK' then raise; end if;
  end;

  raise notice '0034 OK — كلمة الأكل على الجدول: ثابت + كلمة بيعدّي، غريبة مرفوضة، والابن بيقراها';
end $$;
