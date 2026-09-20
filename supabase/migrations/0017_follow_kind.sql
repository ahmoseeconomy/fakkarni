-- 0017 — نوع المتابعة: تحليل ولا زيارة.
--
-- الجهاز بقى (نسخة ١٩) بيتابع حاجتين: **تحليل** زي ما كان من D3.7،
-- و**زيارة** (اتحجزت ← تمت ← المتابعة). الاتنين بيقعدوا على نفس الصف
-- بنفس `checkup_stage`، فلازم يبان النوع عشان الرقم يتفسّر صح: الرقم ٢
-- في متابعة تحليل «حجز المعمل»، وفي متابعة زيارة «الزيارة تمت».
--
--   * `follow_kind` — 'lab' أو 'visit'. **null معناها 'lab'**، ومش تخمين:
--     قبل الجولة دي مكانش فيه نوع تاني أصلاً، فكل صف قديم ليه مرحلة هو
--     متابعة تحليل بالتعريف.
--
-- **اللي مش هنا عن قصد: `follow_source_id`.** ده `id` داخلي بتاع صف على
-- موبايل الأب (السجل اللي المتابعة اتبدت منه) — ومالوش أي معنى هنا، زي
-- `attachment_path` بالظبط. الأرقام الداخلية عمرها ما بتخرج من الجهاز
-- (CLAUDE.md)، و`health_file_sync_guard_test` بيقع لو الاسم ده ظهر في أي
-- حمولة سحابة.
--
-- استعلام الابن (`supabase_caregiver_remote`) بيختار أعمدته بالاسم، فما
-- بيشوفش العمود الجديد لحد ما حد يضيفه هناك عن قصد — شاشته لسه بتعرض
-- السجل من غير ما تقول نوع متابعته.
--
-- **مفيش تغيير في السياسات ولا في `private.due_escalations`**: عمود جديد
-- على جدول موجود بسياساته (0012)، ومالوش علاقة بالتصعيد ولا بالجرعات.
--
-- idempotent زي كل الملفات: `add column if not exists`.

alter table public.records add column if not exists follow_kind text;

-- القيم المسموحة — والقيد بيتلغي ويتعمل تاني عشان الملف يتعاد تشغيله.
alter table public.records drop constraint if exists records_follow_kind_check;
alter table public.records
  add constraint records_follow_kind_check
  check (follow_kind is null or follow_kind in ('lab', 'visit'));

-- ================================================================ تأكيد
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله يترجع.
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_rec   uuid := gen_random_uuid();
  v_kind  text;
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'records'
                   and column_name = 'follow_kind' and is_nullable = 'YES') then
    raise exception 'FAIL 0017: records.follow_kind مش موجود أو مش nullable';
  end if;

  -- و`follow_source_id` **مش** المفروض يبقى موجود: ده رقم داخلي.
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'records'
               and column_name = 'follow_source_id') then
    raise exception 'FAIL 0017: follow_source_id وصل السحابة — ده id داخلي';
  end if;

  begin
    -- المالك لازم يتعمل الأول: patients.owner_id بيشاور على auth.users.
    insert into auth.users (id, email) values (v_owner, 'owner-' || v_owner || '@0017.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, 'تأكيد 0017');

    -- متابعة زيارة
    insert into public.records (uuid, patient_uuid, kind, title, happened_at, checkup_stage, follow_kind)
      values (v_rec, v_pat, 'visit', 'د. حسام', now(), 2, 'visit');
    select follow_kind into v_kind from public.records where uuid = v_rec;
    if v_kind is distinct from 'visit' then
      raise exception 'FAIL 0017: نوع المتابعة ما اتخزّنش';
    end if;

    -- ومتابعة قديمة من غير نوع لسه صالحة — null = تحليل
    insert into public.records (uuid, patient_uuid, kind, title, happened_at, checkup_stage)
      values (gen_random_uuid(), v_pat, 'lab', 'صورة دم كاملة', now(), 2);

    -- وقيمة تالتة مرفوضة
    begin
      insert into public.records (uuid, patient_uuid, kind, title, happened_at, follow_kind)
        values (gen_random_uuid(), v_pat, 'visit', 'غلط', now(), 'cycle');
      raise exception 'FAIL 0017: القيد قبل نوع مش معروف';
    exception when check_violation then
      null; -- ده المطلوب
    end;

    delete from public.patients where uuid = v_pat;
    raise exception '0017_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0017_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0017 OK — نوع المتابعة بيتخزّن، والقديم من غير نوع لسه تحليل';
end $$;
