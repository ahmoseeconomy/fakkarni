-- 0015 — مواعيد متابعة التحليل: كل مرحلة بتسأل عن ميعادها.
--
-- الجهاز بقى (نسخة ١٧) بيخزّن أربع قيم جديدة على صف `records`:
--
--   * `checkup_stage_since` — ساعة دخول المرحلة الحالية. منها بس الشاشة
--     بتعرف إن المتابعة واقفة من أسبوع. **مش حكم على المعمل**: إحنا
--     عمرنا ما قلنا التحليل بياخد قد إيه، وما حدش قال لنا. اللي بيتعرض
--     واقعة عن الشاشة — «واقفة عند المرحلة دي من كذا» — مش عن الجسم.
--   * `lab_booking_at`، `result_ready_at`، `doctor_visit_at` — المواعيد
--     اللي **الإنسان** قالها («حجزت إمتى؟»، «النتيجة هتجهز إمتى؟»،
--     «معاد الدكتور؟»). null = ما قالش، ودي حالة عادية. ولا واحد فيهم
--     بيتحسب ولا بيتخمّن (القاعدة ٦).
--
-- الأعمدة بتترفع مع صف السجل زي أي عمود تاني (`_pushRecords`). استعلام
-- الابن (`supabase_caregiver_remote`) بيختار أعمدته بالاسم، فما بيشوفش
-- الجداد لحد ما حد يضيفهم هناك عن قصد.
--
-- **مفيش تغيير في السياسات ولا في `private.due_escalations`**: دي أعمدة
-- على جدول موجود بسياساته، ومالهاش أي علاقة بالتصعيد.
--
-- idempotent زي كل الملفات: `add column if not exists`.

alter table public.records add column if not exists checkup_stage_since timestamptz;
alter table public.records add column if not exists lab_booking_at      timestamptz;
alter table public.records add column if not exists result_ready_at     timestamptz;
alter table public.records add column if not exists doctor_visit_at     timestamptz;

-- ================================================================ تأكيد
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله يترجع.
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_rec   uuid := gen_random_uuid();
  v_when  timestamptz;
  c       text;
begin
  -- الأربعة موجودين وnullable
  foreach c in array array['checkup_stage_since', 'lab_booking_at',
                           'result_ready_at', 'doctor_visit_at'] loop
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'records'
                     and column_name = c and is_nullable = 'YES') then
      raise exception 'FAIL 0015: records.% مش موجود أو مش nullable', c;
    end if;
  end loop;

  begin
    insert into auth.users (id, email) values (v_owner, 'owner-' || v_owner || '@0015.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0015');

    -- سجل متابعة كامل بمواعيده
    insert into public.records
      (uuid, patient_uuid, kind, title, happened_at, checkup_stage,
       checkup_stage_since, lab_booking_at, result_ready_at, doctor_visit_at)
      values (v_rec, v_pat, 'lab', 'صورة دم كاملة', now(), 2,
              now(), now() + interval '2 days', now() + interval '5 days',
              now() + interval '9 days');

    select lab_booking_at into v_when from public.records where uuid = v_rec;
    if v_when is null then
      raise exception 'FAIL 0015: الميعاد ما اتخزّنش';
    end if;

    -- وسجل عادي من غير متابعة بيفضل صالح — الأعمدة nullable فعلاً
    insert into public.records (uuid, patient_uuid, kind, title, happened_at)
      values (gen_random_uuid(), v_pat, 'visit', 'باطنة', now());

    -- والمسح بيشيل الاتنين (نفس سياسة 0012، مالهاش دعوة بالأعمدة الجداد)
    delete from public.records where patient_uuid = v_pat;
    if exists (select 1 from public.records where patient_uuid = v_pat) then
      raise exception 'FAIL 0015: المسح ما اشتغلش';
    end if;

    raise exception '0015_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0015_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0015 OK — مواعيد المتابعة بتتخزّن، والسجل العادي زي ما هو';
end $$;
