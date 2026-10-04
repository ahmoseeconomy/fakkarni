-- ============================================================================
-- 0038 — نوع الدوا (قرص / كبسولة / حقنة / مرهم / شراب / نقط / بخاخة / لبوس)
-- (ملف بس — المالك راجعه ووافق ٤ أكتوبر ٢٠٢٦، وهو اللي بيطبّقه بإيده)
-- ============================================================================
-- طلب المدير (٤ أكتوبر ٢٠٢٦): كل دوا ليه نوع، والنوع هو اللي بيحدد وحدة
-- كارت المخزون («باقي كام كبسولة؟»). على الموبايل العمود محلي في drift v32؛
-- هنا عشان الابن والممرض يشوفوه ويتقري في «أدويته» وكارت المخزون عندهم.
--
-- null = ما اتحددش (كل الأدوية القديمة) — الوحدة بتفضل من كلام الجرعة زي
-- النهارده. **مفيش تخمين للقديم.**
--
-- **مالوش علاقة بالتذكير ولا بالتصعيد**: `due_escalations` ما بتقراش العمود.
-- RLS زي ما هي (العمود على صف `medications` — قراية للدائرة وكتابة للمالك).
-- الترتيب: بعد 0037 (0036 محجوز لـPRN). idempotent.

alter table public.medications add column if not exists form text;

alter table public.medications drop constraint if exists medications_form_check;
alter table public.medications
  add constraint medications_form_check
  check (form is null or form in
    ('tablet', 'capsule', 'injection', 'ointment', 'syrup', 'drops', 'inhaler', 'suppository', 'other'));

-- فحص ذاتي — آخر حاجة في الملف. المالك في auth.users قبل المريض (درس ٠٠١٦)،
-- وكل الأعمدة NOT NULL متعبّية.
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_n        integer;
  v_rejected boolean;
begin
  begin
    insert into auth.users (id, email) values
      (v_owner, 'owner-' || v_owner || '@0038.check'),
      (v_son,   'son-'   || v_son   || '@0038.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0038');
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
      values (v_pat, v_son, 'accepted', 'follower', false, false);

    -- ١) المالك بيكتب النوع — بـRETURNING زي التطبيق
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into public.medications (uuid, patient_uuid, name, form)
      values (v_med, v_pat, 'Omeprazole', 'capsule')
      returning 1 into v_n;
    execute 'reset role';

    -- ٢) قيمة برّه القايمة بتترفض
    v_rejected := false;
    begin
      update public.medications set form = 'pill' where uuid = v_med;
    exception when check_violation then v_rejected := true;
    end;
    if not v_rejected then raise exception 'FAIL 0038: نوع برّه القايمة اتقبل'; end if;

    -- ٣) الابن بيشوفه وما بيعدّلوش
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    if not exists (select 1 from public.medications where uuid = v_med and form = 'capsule') then
      raise exception 'FAIL 0038: الابن مش شايف النوع';
    end if;
    update public.medications set form = 'tablet' where uuid = v_med;  -- RLS: صفر صف
    execute 'reset role';
    if (select form from public.medications where uuid = v_med) <> 'capsule' then
      raise exception 'FAIL 0038: الابن عدّل النوع';
    end if;

    raise exception '0038_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0038_ROLLBACK' then raise; end if;
  end;

  raise notice '0038 OK — نوع الدوا: القايمة مقفولة، والدائرة قراية';
end $$;
