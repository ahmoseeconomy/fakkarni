-- 0016 — نطاق التحليل زي ما هو مطبوع على ورقة المعمل.
--
-- الجهاز بقى (نسخة ١٨) بيخزّن مع كل سطر تحليل النطاق **المنقول من الورقة**:
--
--   * `ref_low` / `ref_high` — طرفا النطاق الرقمي. واحد منهم ممكن يكون null
--     لوحده: ورقة مكتوب فيها «up to 200» بتدّي `ref_high` بس.
--   * `ref_text` — النطاق المطبوع اللي مش رقم أصلاً («Negative»، «< 5»).
--     بيتعرض بالحرف وعمره ما بيتقارن.
--
-- **التلاتة نقل، مش معرفة.** مفيش في التطبيق — ولا هنا — جدول قيم طبيعية:
-- النطاقات بتختلف من معمل لمعمل وبطريقة التحليل وبالسن والنوع، واختراع
-- واحد يبقى كلام دكتور (القاعدة ٦). السطر اللي الورقة ما طبعتش له نطاق
-- بيفضل التلاتة فيه null، وده جواب صح مش نقص — الشاشة بتقول «الورقة ما
-- فيهاش نطاق للتحليل ده» وما بتعلّمش عليه.
--
-- الأعمدة بتترفع مع سطر التحليل (`_pushLabResults`). استعلام الابن
-- (`supabase_caregiver_remote`) بيختار أعمدته بالاسم، فما بيشوفهمش لحد ما
-- حد يضيفهم هناك عن قصد — شاشته لسه بتعرض الرقم من غير نطاق.
--
-- **مفيش تغيير في السياسات ولا في `private.due_escalations`**: دي أعمدة على
-- جدول موجود بسياساته (0012)، ومالهاش أي علاقة بالتصعيد ولا بالجرعات.
--
-- idempotent زي كل الملفات: `add column if not exists`.

alter table public.lab_results add column if not exists ref_low  double precision;
alter table public.lab_results add column if not exists ref_high double precision;
alter table public.lab_results add column if not exists ref_text text;

-- ================================================================ تأكيد
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله يترجع.
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_rec   uuid := gen_random_uuid();
  v_low   double precision;
  v_text  text;
  c       text;
begin
  -- التلاتة موجودين وnullable
  foreach c in array array['ref_low', 'ref_high', 'ref_text'] loop
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'lab_results'
                     and column_name = c and is_nullable = 'YES') then
      raise exception 'FAIL 0016: lab_results.% مش موجود أو مش nullable', c;
    end if;
  end loop;

  begin
    -- المالك لازم يتعمل الأول: patients.owner_id بيشاور على auth.users.
    insert into auth.users (id, email) values (v_owner, 'owner-' || v_owner || '@0016.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, 'تأكيد 0016');
    insert into public.records (uuid, patient_uuid, kind, title, happened_at)
      values (v_rec, v_pat, 'lab', 'صورة دم كاملة', now());

    -- سطر بنطاق رقمي من الورقة
    insert into public.lab_results (uuid, record_uuid, test_name, value, unit, ref_low, ref_high)
      values (gen_random_uuid(), v_rec, 'WBC', 12.4, '10^3/uL', 4, 11);
    -- سطر بنطاق مطبوع مش رقمي
    insert into public.lab_results (uuid, record_uuid, test_name, value, ref_text)
      values (gen_random_uuid(), v_rec, 'CRP', 3, 'Negative');
    -- **وسطر الورقة ما طبعتش له نطاق — لازم يفضل صالح بالتلاتة null**
    insert into public.lab_results (uuid, record_uuid, test_name, value, unit)
      values (gen_random_uuid(), v_rec, 'Uric acid', 5.1, 'mg/dL');

    select ref_low into v_low from public.lab_results where record_uuid = v_rec and test_name = 'WBC';
    if v_low is null or v_low <> 4 then
      raise exception 'FAIL 0016: نطاق الورقة ما اتخزّنش';
    end if;

    select ref_text into v_text from public.lab_results where record_uuid = v_rec and test_name = 'CRP';
    if v_text is distinct from 'Negative' then
      raise exception 'FAIL 0016: النطاق المكتوب بالحروف ما اتخزّنش بالحرف';
    end if;

    if exists (select 1 from public.lab_results
               where record_uuid = v_rec and test_name = 'Uric acid'
                 and (ref_low is not null or ref_high is not null or ref_text is not null)) then
      raise exception 'FAIL 0016: سطر من غير نطاق اتملا من حتة';
    end if;

    -- ومسح السجل بيشيل سطوره زي ما هو (cascade من 0012)
    delete from public.records where uuid = v_rec;
    if exists (select 1 from public.lab_results where record_uuid = v_rec) then
      raise exception 'FAIL 0016: الـcascade ما اشتغلش';
    end if;

    delete from public.patients where uuid = v_pat;
    raise exception '0016_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0016_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0016 OK — نطاق الورقة بيتخزّن، والسطر من غير نطاق بيفضل من غير نطاق';
end $$;
