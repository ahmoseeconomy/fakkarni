-- 0007_escalate_rpc.sql — نافذة واحدة ضيّقة على استعلام الاختيار.
--
-- ليه الملف ده موجود أصلاً: `private` **مش مكشوفة عبر PostgREST** — وده
-- مقصود من ٠٠٠٢ وما بيتغيّرش. يعني الدالة السحابية (اللي بتكلم القاعدة
-- عن طريق PostgREST زي أي عميل) **مش قادرة** تنادي
-- `private.due_escalations` مهما كان معاها مفتاح. ده اكتُشف وقت كتابة
-- `functions/escalate/index.ts`، مش وقت التخطيط.
--
-- الحلول اللي **مرفوضة**:
--   * كشف مخطط `private` في إعدادات الـAPI — ده بيفتح كل دوال الوصول
--     المعرِّفة اللي فيه دفعة واحدة. تنازل أمني عشان راحة استدعاء.
--   * نسخة من الاستعلام مكتوبة TypeScript جوّه الدالة السحابية — ده
--     بالظبط «تعريفين للاختيار» اللي الجولة دي كلها اتبنت ضده.
--
-- الحل: غلاف رفيع في `public` **مالوش جسم خاص بيه** — بينادي
-- `private.due_escalations` وخلاص. التنفيذ لـ`service_role` بس، والباقي
-- ممنوع صراحة. يعني PostgREST هيرفض النداء لأي مستخدم مسجّل أو مجهول
-- بـ42501، ومفتاح الخدمة عمره ما بيخرج من السيرفر.
--
-- SECURITY DEFINER هنا مش للتفاف على RLS — الاستعلام جوّه معرِّف أصلاً —
-- لكن عشان النداء يشتغل بامتيازات المالك على مخطط `private` من غير ما
-- نضطر نوسّع صلاحيات المخطط ده لأي دور تاني.

create or replace function public.due_escalations_for_service(p_limit integer default 200)
returns table (
  dose_event_uuid uuid,
  patient_uuid    uuid,
  patient_name    text,
  medication_name text,
  scheduled_at    timestamptz,
  caregiver_id    uuid
)
language sql stable security definer
set search_path = ''
as $$
  select * from private.due_escalations(p_limit);
$$;

revoke execute on function public.due_escalations_for_service(integer)
  from anon, authenticated, public;
grant  execute on function public.due_escalations_for_service(integer)
  to service_role;
