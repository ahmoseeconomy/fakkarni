-- 0039 — النتيجة النصية لسطر التحليل (المرحلة ٥، قرار المالك 1A).
--
-- ورقة المعمل ساعات بتطبع نتيجة **مش رقم**: «Negative»، «Nil»، «2 - 4».
-- لحد النهارده `lab_results.value` كان `not null`، فالسطور دي كانت بتتشال
-- أو بتقفل «تمام» على الموبايل. دلوقتي:
--
--   * `value` بقى nullable — سطر نصي مالوش رقم، ومفيش رقم بيتخترع (القاعدة ٦).
--   * `value_text` — النتيجة المطبوعة **بالحرف زي الورقة**، بتتعرض وعمرها
--     ما بتتقارن بمعتاد ولا نطاق — زي `ref_text` بالظبط.
--   * واحدة من الاتنين على الأقل: قيد `lab_results_value_present` بيرفض صف
--     من غير رقم ومن غير نص — صف زي ده مش نتيجة أصلاً، وكاتبه بايظ.
--     **الصفوف القديمة كلها أرقام فبتعدّي**، وقيد بيترفض معناه دفعة
--     `lab_results` بتقف (والجداول اللي بعدها في السلسلة بتستنى) — مقبول
--     عن قصد، زي قيد حالات `dose_events`: عطل صامت في الكاتب أوحش.
--
-- **مين بيقرا العمود الجديد**: استعلام الابن بيختار أعمدته بالاسم، فنسخة
-- أقدم من المرحلة ٥ ما بتطلبوش — لكن **أول صف نصي** (value = null) بيكسر
-- قراءتها (cast غير nullable في `supabase_caregiver_remote`). يعني الخطر مش
-- في الملف ده — الملف لوحده ما بيكسرش حد — الخطر في أول موبايل مريض بنسخة
-- المرحلة ٥ يرفع سطر نصي وابنه لسه على نسخة قديمة. قرار الترتيب للمالك،
-- مكتوب في تقرير المرحلة.
--
-- **مفيش تغيير في السياسات ولا في `private.due_escalations`** — أعمدة على
-- جدول موجود بسياساته (0012)، ولا علاقة بالتصعيد.
--
-- idempotent: `drop not null` مرتين لا-عملية، `add column if not exists`،
-- والقيد بـ`drop ... if exists` قبل الإضافة.

alter table public.lab_results alter column value drop not null;
alter table public.lab_results add column if not exists value_text text;

alter table public.lab_results drop constraint if exists lab_results_value_present;
alter table public.lab_results add constraint lab_results_value_present
  check (value is not null or value_text is not null);

-- ================================================================ تأكيد
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله يترجع.
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_rec   uuid := gen_random_uuid();
  v_text  text;
  v_num   double precision;
begin
  -- العمود الجديد موجود وnullable، وvalue بقى nullable
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'lab_results'
                   and column_name = 'value_text' and is_nullable = 'YES') then
    raise exception 'FAIL 0039: lab_results.value_text مش موجود أو مش nullable';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'lab_results'
                   and column_name = 'value' and is_nullable = 'YES') then
    raise exception 'FAIL 0039: lab_results.value لسه not null';
  end if;

  begin
    -- المالك لازم يتعمل الأول: patients.owner_id بيشاور على auth.users.
    insert into auth.users (id, email) values (v_owner, 'owner-' || v_owner || '@0039.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, 'تأكيد 0039');
    insert into public.records (uuid, patient_uuid, kind, title, happened_at)
      values (v_rec, v_pat, 'lab', 'تحليل بول', now());

    -- سطر رقمي زي زمان — لازم يفضل صالح بعد الملف ده
    insert into public.lab_results (uuid, record_uuid, test_name, value, unit)
      values (gen_random_uuid(), v_rec, 'Specific Gravity', 1.020, null);
    -- سطر نصي — الجديد: value فاضي والنص بالحرف
    insert into public.lab_results (uuid, record_uuid, test_name, value, value_text)
      values (gen_random_uuid(), v_rec, 'Pus Cells', null, 'Negative');

    select value_text, value into v_text, v_num
      from public.lab_results where record_uuid = v_rec and test_name = 'Pus Cells';
    if v_text is distinct from 'Negative' or v_num is not null then
      raise exception 'FAIL 0039: النتيجة النصية ما اتخزّنتش بالحرف';
    end if;

    -- صف من غير رقم ومن غير نص بيترفض — القيد شغّال
    begin
      insert into public.lab_results (uuid, record_uuid, test_name, value, value_text)
        values (gen_random_uuid(), v_rec, 'فاضي', null, null);
      raise exception 'FAIL 0039: صف من غير أي نتيجة اتقبل';
    exception when check_violation then
      null; -- المطلوب
    end;

    -- ومسح السجل بيشيل سطوره زي ما هو (cascade من 0012)
    delete from public.records where uuid = v_rec;
    if exists (select 1 from public.lab_results where record_uuid = v_rec) then
      raise exception 'FAIL 0039: الـcascade ما اشتغلش';
    end if;

    delete from public.patients where uuid = v_pat;
    raise exception '0039_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0039_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0039 OK — «Negative» بتتخزّن بالحرف، والرقم زي ما هو، والفاضي بيترفض';
end $$;
