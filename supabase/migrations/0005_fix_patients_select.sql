-- 0005_fix_patients_select.sql
--
-- إصلاح: سياسة القراءة على patients كانت بتنادي can_access_patient(uuid)،
-- والدالة دي بتدوّر على الصف **جوّه جدول patients نفسه**. عند INSERT ...
-- RETURNING بيطبّق Postgres سياسة القراءة على الصف الجديد، والدالة ما
-- بتلاقيهوش لأن صف اتكتب في نفس الأمر مش مرئي لاستعلام في نفس الأمر.
-- النتيجة: كل إدخال مريض جديد بيفشل بـ 42501 — مش حالة نادرة، ده كل مرة.
--
-- الحل: للمالك نقارن بعمود owner_id **اللي في الصف نفسه** (مفيش استعلام،
-- فمفيش مشكلة رؤية)، ولمقدّم الرعاية دالة definer بتلمس care_relationships
-- بس — جدول تاني، فمفيش لا تكرار لا نداء ذاتي.
--
-- القاعدة اللي اتعلمناها: **سياسة جدول عمرها ما تنادي دالة بتستعلم عن نفس
-- الجدول.** الأعمدة متاحة في السياسة على طول — استخدمها.

create or replace function private.is_accepted_caregiver(p_uuid uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.care_relationships cr
    where cr.patient_uuid = p_uuid
      and cr.caregiver_id = (select auth.uid())
      and cr.status = 'accepted'
  );
$$;

revoke execute on function private.is_accepted_caregiver(uuid) from anon, public;
grant  execute on function private.is_accepted_caregiver(uuid) to authenticated;

drop policy if exists patients_select on public.patients;

create policy patients_select on public.patients
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    or private.is_accepted_caregiver(uuid)
  );
