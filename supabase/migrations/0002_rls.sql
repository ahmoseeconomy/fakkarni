-- 0002_rls.sql — أمن مستوى الصف. هذا الملف هو النموذج الأمني كله.
--
-- المفتاح المنشور علني بحكم التعريف؛ RLS هو الجدار الوحيد أمام قائمة
-- أدوية أي مريض. جدول بدون RLS أو سياسة ناقصة = تسريب بيانات طبية.
--
-- لماذا دالة الوصول SECURITY DEFINER؟
--   ظهور patients يعتمد على care_relationships («في علاقة accepted؟»)
--   وظهور care_relationships يعتمد على patients («ده مريضي؟»). لو كل
--   سياسة قرأت جدول الأخرى مباشرة، Postgres يكتشف الحلقة ويرمي
--   «infinite recursion detected in policy» وقت الاستعلام — الـAPI كله
--   يقع. الدالة المعرِّفة تكسر الحلقة لأنها تعمل بصلاحيات مالكها
--   فتقرأ الجداول الخام بدون إعادة دخول أي سياسة.
--   private = غير مكشوفة عبر PostgREST؛ STABLE = تُحسب مرة في الاستعلام؛
--   SET search_path = '' = لا يمكن خطف الجداول التي تقرأها ببديل خبيث.
--
-- قواعد ثابتة في كل السياسات:
--   * (select auth.uid()) دائماً — تُحسب مرة للاستعلام، ليس لكل صف.
--   * TO authenticated فقط — دور anon لا يحصل على شيء في أي مكان.
--   * سياسة لكل عملية؛ INSERT تعني WITH CHECK.
--   * مقدّم الرعاية قراءة فقط هذه الجولة — كتابته الوحيدة (تأكيد جرعة
--     نيابةً عن الأب) تأتي مع التصعيد كسياسة UPDATE ضيّقة، لا كتابة عامة.

-- ------------------------------------------------- ١) RLS أولاً، قبل أي شيء
alter table public.patients           enable row level security;
alter table public.day_routines       enable row level security;
alter table public.medications        enable row level security;
alter table public.dose_schedules     enable row level security;
alter table public.fixed_timings      enable row level security;
alter table public.dose_events        enable row level security;
alter table public.care_relationships enable row level security;

-- anon لا يلمس الجداول حتى بامتيازات SQL، بغضّ النظر عن السياسات
revoke all on public.patients,
              public.day_routines,
              public.medications,
              public.dose_schedules,
              public.fixed_timings,
              public.dose_events,
              public.care_relationships
  from anon, public;

-- --------------------------------------------------- ٢) دوال الوصول الخاصة
create schema if not exists private;

-- «أنا مالك المريض ده؟» — للكتابة.
create or replace function private.owns_patient(p_uuid uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.patients p
    where p.uuid = p_uuid
      and p.owner_id = (select auth.uid())
  );
$$;

-- «أقدر أشوف المريض ده؟» — مالك، أو مقدّم رعاية بعلاقة accepted.
-- كل سياسة قراءة في كل الجداول تمرّ من هنا — نقطة تحقّق واحدة.
create or replace function private.can_access_patient(p_uuid uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.owns_patient(p_uuid)
      or exists (
           select 1
           from public.care_relationships cr
           where cr.patient_uuid = p_uuid
             and cr.caregiver_id = (select auth.uid())
             and cr.status = 'accepted'
         );
$$;

-- الأطفال لا يحملون patient_uuid مباشرة — مصعدان معرِّفان بدل تداخل سياسات
create or replace function private.patient_of_medication(m_uuid uuid)
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select m.patient_uuid from public.medications m where m.uuid = m_uuid;
$$;

create or replace function private.patient_of_schedule(s_uuid uuid)
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select m.patient_uuid
  from public.dose_schedules s
  join public.medications m on m.uuid = s.medication_uuid
  where s.uuid = s_uuid;
$$;

revoke execute on function private.owns_patient(uuid),
                           private.can_access_patient(uuid),
                           private.patient_of_medication(uuid),
                           private.patient_of_schedule(uuid)
  from anon, public;
grant execute on function private.owns_patient(uuid),
                          private.can_access_patient(uuid),
                          private.patient_of_medication(uuid),
                          private.patient_of_schedule(uuid)
  to authenticated;

-- ---------------------------------------------------------------- patients
-- القراءة عبر الدالة (مالك أو رعاية accepted)؛ الكتابة للمالك حصراً.
create policy patients_select on public.patients
  for select to authenticated
  using (private.can_access_patient(uuid));

create policy patients_insert on public.patients
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy patients_update on public.patients
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy patients_delete on public.patients
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- ------------------------------------------------------------ day_routines
create policy day_routines_select on public.day_routines
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

create policy day_routines_insert on public.day_routines
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

create policy day_routines_update on public.day_routines
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

create policy day_routines_delete on public.day_routines
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- ------------------------------------------------------------- medications
create policy medications_select on public.medications
  for select to authenticated
  using (private.can_access_patient(patient_uuid));

create policy medications_insert on public.medications
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

create policy medications_update on public.medications
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

create policy medications_delete on public.medications
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

-- ---------------------------------------------------------- dose_schedules
create policy dose_schedules_select on public.dose_schedules
  for select to authenticated
  using (private.can_access_patient(private.patient_of_medication(medication_uuid)));

create policy dose_schedules_insert on public.dose_schedules
  for insert to authenticated
  with check (private.owns_patient(private.patient_of_medication(medication_uuid)));

create policy dose_schedules_update on public.dose_schedules
  for update to authenticated
  using (private.owns_patient(private.patient_of_medication(medication_uuid)))
  with check (private.owns_patient(private.patient_of_medication(medication_uuid)));

create policy dose_schedules_delete on public.dose_schedules
  for delete to authenticated
  using (private.owns_patient(private.patient_of_medication(medication_uuid)));

-- ----------------------------------------------------------- fixed_timings
create policy fixed_timings_select on public.fixed_timings
  for select to authenticated
  using (private.can_access_patient(private.patient_of_schedule(dose_schedule_uuid)));

create policy fixed_timings_insert on public.fixed_timings
  for insert to authenticated
  with check (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)));

create policy fixed_timings_update on public.fixed_timings
  for update to authenticated
  using (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)))
  with check (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)));

create policy fixed_timings_delete on public.fixed_timings
  for delete to authenticated
  using (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)));

-- ------------------------------------------------------------- dose_events
create policy dose_events_select on public.dose_events
  for select to authenticated
  using (private.can_access_patient(private.patient_of_schedule(dose_schedule_uuid)));

create policy dose_events_insert on public.dose_events
  for insert to authenticated
  with check (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)));

create policy dose_events_update on public.dose_events
  for update to authenticated
  using (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)))
  with check (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)));

create policy dose_events_delete on public.dose_events
  for delete to authenticated
  using (private.owns_patient(private.patient_of_schedule(dose_schedule_uuid)));

-- ------------------------------------------------------ care_relationships
-- مقدّم الرعاية يرى صفوفه؛ المالك يرى صفوف مرضاه. لا INSERT لأحد هذه
-- الجولة (إنشاء العلاقة يأتي مع تدفّق كود الدعوة في 3.3 — الغياب هنا
-- رفض افتراضي، ليس سهواً). لا أحد يعدّل status غير مالك المريض.
create policy care_select on public.care_relationships
  for select to authenticated
  using (
    caregiver_id = (select auth.uid())
    or private.owns_patient(patient_uuid)
  );

create policy care_update on public.care_relationships
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

create policy care_delete on public.care_relationships
  for delete to authenticated
  using (private.owns_patient(patient_uuid));
