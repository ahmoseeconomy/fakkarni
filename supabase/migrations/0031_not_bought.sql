-- ============================================================================
-- 0031 — «أدوية لسه ماتشترتش» للدائرة (ملف بس — ما اتطبّقش، مستني مراجعة)
-- ============================================================================
-- على موبايل المريض القايمة محلية (drift v28، `medications.not_bought_at`).
-- عشان الابن والممرض يشوفوها، العمود لازم يبقى في السحابة؛ وعشان الممرض
-- بـ«يعدّل الأدوية» يقول «اشتريته»، محتاجين نوع تغيير جديد 'bought' على
-- `medication_changes` (بيتطبّق على موبايل المريض بسكّة 0024 زي الباقي).
--
-- **مالهاش علاقة بالتذكير ولا بالتصعيد**: `due_escalations` ما بتقراش
-- العمود ده — جرعة دوا «لسه ماتشترتش» بتصعّد زي أي جرعة.
--
-- RLS زي ما هي: العمود على صف `medications` اللي سياساته (0002/0026)
-- بتدّي القراية للدائرة والكتابة للمالك. مفيش سياسة جديدة.
-- الترتيب: بعد 0030. idempotent.

alter table public.medications add column if not exists not_bought_at timestamptz;

alter table public.medication_changes drop constraint if exists medication_changes_kind_check;
alter table public.medication_changes
  add constraint medication_changes_kind_check
  check (kind in ('add', 'stop', 'amount', 'record', 'appointment', 'restock', 'photo', 'bought'));

-- فحص ذاتي — من الجداول وRLS بس تحت `set local role authenticated`، ولا
-- نداء private.* في الدور ده.
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_n        integer;
  v_denied   boolean;
begin
  if not exists (select 1 from pg_constraint where conname = 'medication_changes_kind_check'
                 and pg_get_constraintdef(oid) like '%photo%') then
    raise exception 'FAIL 0031: شغّل 0029 الأول';
  end if;

  begin
    -- المالك في auth.users **قبل** المريض — درس ٠٠١٦
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0031.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0031.check'),
      (v_son,      'son-'      || v_son      || '@0031.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0031.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0031');
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
      values (v_pat, v_nurse, 'accepted', 'nurse',    true,  true),
             (v_pat, v_son,   'accepted', 'follower', false, false);

    -- ١) المالك بيكتب الدوا بـ«لسه ماتشترتش» — بـRETURNING زي التطبيق
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into public.medications (uuid, patient_uuid, name, not_bought_at)
      values (v_med, v_pat, 'Concor', now())
      returning 1 into v_n;
    execute 'reset role';

    -- ٢) الابن والممرض بيشوفوه، وما بيعدّلوش
    foreach v_n in array array[1, 2] loop
      perform set_config('request.jwt.claims',
        json_build_object('sub', case v_n when 1 then v_son else v_nurse end)::text, true);
      execute 'set local role authenticated';
      if not exists (select 1 from public.medications where uuid = v_med and not_bought_at is not null) then
        raise exception 'FAIL 0031: الدائرة مش شايفة «لسه ماتشترتش»';
      end if;
      update public.medications set not_bought_at = null where uuid = v_med;  -- RLS: صفر صف
      execute 'reset role';
    end loop;
    if (select not_bought_at from public.medications where uuid = v_med) is null then
      raise exception 'FAIL 0031: حد من الدائرة عدّل العمود';
    end if;

    -- ٣) الممرض بـ«يعدّل الأدوية» بيبعت 'bought'، والابن لأ
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    insert into public.medication_changes (patient_uuid, actor_id, kind, medication_uuid)
      values (v_pat, v_nurse, 'bought', v_med);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      insert into public.medication_changes (patient_uuid, actor_id, kind, medication_uuid)
        values (v_pat, v_son, 'bought', v_med);
    exception when insufficient_privilege then v_denied := true;
    end;
    execute 'reset role';
    if not v_denied then raise exception 'FAIL 0031: المتابع بعت «اشتريته»'; end if;

    -- ٤) الغريب ما بيشوفش
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medications where uuid = v_med;
    execute 'reset role';
    if v_n <> 0 then raise exception 'FAIL 0031: غريب شاف الدوا'; end if;

    raise exception '0031_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0031_ROLLBACK' then raise; end if;
  end;

  raise notice '0031 OK — «لسه ماتشترتش» للدائرة قراية، والممرض بيبعت «اشتريته» والابن لأ';
end $$;
