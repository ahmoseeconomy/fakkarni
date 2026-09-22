-- verify_migrations.sql — **بيقرا بس.** ولا DDL، ولا insert، ولا DO block
-- بيكتب. سكريبت تأكيد بيغيّر القاعدة مش سكريبت تأكيد.
--
-- الصق الملف ده في محرر SQL بتاع المشروع. بيرجّع **صف لكل ترحيل** من 0001
-- لـ0019: اسمه، كام حاجة المفروض تكون موجودة، كام لقاها، وok — وعمود
-- `missing` بأسامي اللي ناقص، عشان الرد يبقى «0012 ناقصها records_select»
-- مش «0012 وقعت».
--
-- **ليه الملف ده موجود**: ملف ترحيل في الريبو مش ترحيل في القاعدة. جولة
-- ٢٥ ضاعت في تشخيص شاشة الابن لأن الفحص اتعمل على الملفات: العمود كان في
-- git ومكانش في Postgres، و`0014` عمرها ما اتشغّلت. ده الفحص اللي بيسأل
-- **القاعدة**.
--
-- بيتأكد من اللي غيابه بيكسر حاجة فعلاً — جداول، أعمدة، دوال، سياسات،
-- فهارس، تريجرات، قيود، ومهام cron — مش رمز واحد لكل ملف.

with expected(migration, kind, ident) as (
  values
    ('0001_schema', 'table', 'public.patients'),
    ('0001_schema', 'table', 'public.day_routines'),
    ('0001_schema', 'table', 'public.medications'),
    ('0001_schema', 'table', 'public.dose_schedules'),
    ('0001_schema', 'table', 'public.fixed_timings'),
    ('0001_schema', 'table', 'public.dose_events'),
    ('0001_schema', 'table', 'public.care_relationships'),
    ('0001_schema', 'index', 'public|patients_owner_idx'),
    ('0001_schema', 'index', 'public|medications_patient_idx'),
    ('0001_schema', 'index', 'public|dose_schedules_medication_idx'),
    ('0001_schema', 'index', 'public|dose_events_schedule_idx'),
    ('0001_schema', 'index', 'public|care_relationships_patient_idx'),
    ('0001_schema', 'index', 'public|care_relationships_caregiver_idx'),
    ('0002_rls', 'schema', 'private'),
    ('0002_rls', 'function', 'private.owns_patient'),
    ('0002_rls', 'function', 'private.can_access_patient'),
    ('0002_rls', 'function', 'private.patient_of_medication'),
    ('0002_rls', 'function', 'private.patient_of_schedule'),
    ('0002_rls', 'policy', 'public.patients|patients_select'),
    ('0002_rls', 'policy', 'public.patients|patients_insert'),
    ('0002_rls', 'policy', 'public.patients|patients_update'),
    ('0002_rls', 'policy', 'public.patients|patients_delete'),
    ('0002_rls', 'rls', 'public.patients'),
    ('0002_rls', 'policy', 'public.day_routines|day_routines_select'),
    ('0002_rls', 'policy', 'public.day_routines|day_routines_insert'),
    ('0002_rls', 'policy', 'public.day_routines|day_routines_update'),
    ('0002_rls', 'policy', 'public.day_routines|day_routines_delete'),
    ('0002_rls', 'rls', 'public.day_routines'),
    ('0002_rls', 'policy', 'public.medications|medications_select'),
    ('0002_rls', 'policy', 'public.medications|medications_insert'),
    ('0002_rls', 'policy', 'public.medications|medications_update'),
    ('0002_rls', 'policy', 'public.medications|medications_delete'),
    ('0002_rls', 'rls', 'public.medications'),
    ('0002_rls', 'policy', 'public.dose_schedules|dose_schedules_select'),
    ('0002_rls', 'policy', 'public.dose_schedules|dose_schedules_insert'),
    ('0002_rls', 'policy', 'public.dose_schedules|dose_schedules_update'),
    ('0002_rls', 'policy', 'public.dose_schedules|dose_schedules_delete'),
    ('0002_rls', 'rls', 'public.dose_schedules'),
    ('0002_rls', 'policy', 'public.fixed_timings|fixed_timings_select'),
    ('0002_rls', 'policy', 'public.fixed_timings|fixed_timings_insert'),
    ('0002_rls', 'policy', 'public.fixed_timings|fixed_timings_update'),
    ('0002_rls', 'policy', 'public.fixed_timings|fixed_timings_delete'),
    ('0002_rls', 'rls', 'public.fixed_timings'),
    ('0002_rls', 'policy', 'public.dose_events|dose_events_select'),
    ('0002_rls', 'policy', 'public.dose_events|dose_events_insert'),
    ('0002_rls', 'policy', 'public.dose_events|dose_events_update'),
    ('0002_rls', 'policy', 'public.dose_events|dose_events_delete'),
    ('0002_rls', 'rls', 'public.dose_events'),
    ('0002_rls', 'policy', 'public.care_relationships|care_select'),
    ('0002_rls', 'policy', 'public.care_relationships|care_update'),
    ('0002_rls', 'policy', 'public.care_relationships|care_delete'),
    ('0002_rls', 'rls', 'public.care_relationships'),
    ('0003_invites', 'table', 'public.invite_codes'),
    ('0003_invites', 'function', 'public.create_invite'),
    ('0003_invites', 'function', 'public.redeem_invite'),
    ('0003_invites', 'policy', 'public.invite_codes|invite_codes_select'),
    ('0003_invites', 'rls', 'public.invite_codes'),
    ('0004_sync', 'column', 'public.patients.updated_at'),
    ('0004_sync', 'trigger', 'public.patients|set_updated_at'),
    ('0004_sync', 'column', 'public.day_routines.updated_at'),
    ('0004_sync', 'trigger', 'public.day_routines|set_updated_at'),
    ('0004_sync', 'column', 'public.medications.updated_at'),
    ('0004_sync', 'trigger', 'public.medications|set_updated_at'),
    ('0004_sync', 'column', 'public.dose_schedules.updated_at'),
    ('0004_sync', 'trigger', 'public.dose_schedules|set_updated_at'),
    ('0004_sync', 'column', 'public.fixed_timings.updated_at'),
    ('0004_sync', 'trigger', 'public.fixed_timings|set_updated_at'),
    ('0004_sync', 'column', 'public.dose_events.updated_at'),
    ('0004_sync', 'trigger', 'public.dose_events|set_updated_at'),
    ('0004_sync', 'column', 'public.care_relationships.updated_at'),
    ('0004_sync', 'trigger', 'public.care_relationships|set_updated_at'),
    ('0005_fix_patients_select', 'function', 'private.is_accepted_caregiver'),
    ('0005_fix_patients_select', 'policysrc', 'public.patients|patients_select|is_accepted_caregiver'),
    ('0006_push', 'table', 'public.device_tokens'),
    ('0006_push', 'rls', 'public.device_tokens'),
    ('0006_push', 'table', 'public.escalations'),
    ('0006_push', 'rls', 'public.escalations'),
    ('0006_push', 'function', 'private.server_grace_window'),
    ('0006_push', 'function', 'private.patient_of_dose_event'),
    ('0006_push', 'function', 'private.due_escalations'),
    ('0006_push', 'function', 'public.claim_device_token'),
    ('0006_push', 'policy', 'public.device_tokens|device_tokens_select'),
    ('0006_push', 'policy', 'public.device_tokens|device_tokens_insert'),
    ('0006_push', 'policy', 'public.device_tokens|device_tokens_update'),
    ('0006_push', 'policy', 'public.device_tokens|device_tokens_delete'),
    ('0006_push', 'policy', 'public.escalations|escalations_select'),
    ('0006_push', 'index', 'public|device_tokens_user_idx'),
    ('0006_push', 'index', 'public|escalations_caregiver_idx'),
    ('0006_push', 'index', 'public|dose_events_scan_idx'),
    ('0006_push', 'trigger', 'public.device_tokens|set_updated_at'),
    ('0007_escalate_rpc', 'function', 'public.due_escalations_for_service'),
    ('0008_escalation_cron', 'function', 'private.run_escalation_scan'),
    ('0008_escalation_cron', 'cron', 'fakkarni-escalate'),
    ('0009_escalation_retry', 'function', 'private.escalation_retry_after'),
    ('0009_escalation_retry', 'function', 'public.claim_escalation_for_service'),
    ('0009_escalation_retry', 'funcsrc', 'private.due_escalations|escalation_retry_after'),
    ('0010_dose_superseded', 'constraintdef', 'public.dose_events|dose_events_state_check|superseded'),
    ('0011_escalate_missed', 'funcsrc', 'private.due_escalations|missed'),
    ('0012_health_file', 'table', 'public.records'),
    ('0012_health_file', 'rls', 'public.records'),
    ('0012_health_file', 'trigger', 'public.records|set_updated_at'),
    ('0012_health_file', 'policy', 'public.records|records_select'),
    ('0012_health_file', 'policy', 'public.records|records_insert'),
    ('0012_health_file', 'policy', 'public.records|records_update'),
    ('0012_health_file', 'policy', 'public.records|records_delete'),
    ('0012_health_file', 'table', 'public.readings'),
    ('0012_health_file', 'rls', 'public.readings'),
    ('0012_health_file', 'trigger', 'public.readings|set_updated_at'),
    ('0012_health_file', 'policy', 'public.readings|readings_select'),
    ('0012_health_file', 'policy', 'public.readings|readings_insert'),
    ('0012_health_file', 'policy', 'public.readings|readings_update'),
    ('0012_health_file', 'policy', 'public.readings|readings_delete'),
    ('0012_health_file', 'table', 'public.lab_results'),
    ('0012_health_file', 'rls', 'public.lab_results'),
    ('0012_health_file', 'trigger', 'public.lab_results|set_updated_at'),
    ('0012_health_file', 'policy', 'public.lab_results|lab_results_select'),
    ('0012_health_file', 'policy', 'public.lab_results|lab_results_insert'),
    ('0012_health_file', 'policy', 'public.lab_results|lab_results_update'),
    ('0012_health_file', 'policy', 'public.lab_results|lab_results_delete'),
    ('0012_health_file', 'table', 'public.visit_questions'),
    ('0012_health_file', 'rls', 'public.visit_questions'),
    ('0012_health_file', 'trigger', 'public.visit_questions|set_updated_at'),
    ('0012_health_file', 'policy', 'public.visit_questions|visit_questions_select'),
    ('0012_health_file', 'policy', 'public.visit_questions|visit_questions_insert'),
    ('0012_health_file', 'policy', 'public.visit_questions|visit_questions_update'),
    ('0012_health_file', 'policy', 'public.visit_questions|visit_questions_delete'),
    ('0012_health_file', 'table', 'public.emergency_profile'),
    ('0012_health_file', 'rls', 'public.emergency_profile'),
    ('0012_health_file', 'trigger', 'public.emergency_profile|set_updated_at'),
    ('0012_health_file', 'policy', 'public.emergency_profile|emergency_profile_select'),
    ('0012_health_file', 'policy', 'public.emergency_profile|emergency_profile_insert'),
    ('0012_health_file', 'policy', 'public.emergency_profile|emergency_profile_update'),
    ('0012_health_file', 'policy', 'public.emergency_profile|emergency_profile_delete'),
    ('0012_health_file', 'function', 'private.patient_of_record'),
    ('0012_health_file', 'function', 'private.record_retention'),
    ('0012_health_file', 'function', 'private.purge_deleted_records'),
    ('0012_health_file', 'index', 'public|records_patient_idx'),
    ('0012_health_file', 'index', 'public|readings_patient_idx'),
    ('0012_health_file', 'index', 'public|lab_results_record_idx'),
    ('0012_health_file', 'index', 'public|visit_questions_patient_idx'),
    ('0012_health_file', 'cron', 'fakkarni-purge-records'),
    ('0013_ai_reads', 'table', 'public.ai_reads'),
    ('0013_ai_reads', 'rls', 'public.ai_reads'),
    ('0013_ai_reads', 'function', 'private.cairo_day_start'),
    ('0013_ai_reads', 'function', 'public.ai_reads_today_for_service'),
    ('0013_ai_reads', 'index', 'public|ai_reads_user_day_idx'),
    ('0013_ai_reads', 'index', 'public|ai_reads_day_idx'),
    ('0014_soft_stop', 'column', 'public.medications.removed_at'),
    ('0014_soft_stop', 'column', 'public.dose_schedules.stopped_at'),
    ('0014_soft_stop', 'index', 'public|medications_removed_idx'),
    ('0014_soft_stop', 'index', 'public|dose_schedules_stopped_idx'),
    ('0014_soft_stop', 'funcsrc', 'private.due_escalations|removed_at'),
    ('0015_checkup_dates', 'column', 'public.records.checkup_stage_since'),
    ('0015_checkup_dates', 'column', 'public.records.lab_booking_at'),
    ('0015_checkup_dates', 'column', 'public.records.result_ready_at'),
    ('0015_checkup_dates', 'column', 'public.records.doctor_visit_at'),
    ('0016_lab_ranges', 'column', 'public.lab_results.ref_low'),
    ('0016_lab_ranges', 'column', 'public.lab_results.ref_high'),
    ('0016_lab_ranges', 'column', 'public.lab_results.ref_text'),
    ('0017_follow_kind', 'column', 'public.records.follow_kind'),
    ('0017_follow_kind', 'constraintdef', 'public.records|records_follow_kind_check|visit'),
    ('0018_device_health', 'table', 'public.device_health'),
    ('0018_device_health', 'rls', 'public.device_health'),
    ('0018_device_health', 'column', 'public.device_health.failing_codes'),
    ('0018_device_health', 'column', 'public.device_health.horizon_until'),
    ('0018_device_health', 'column', 'public.device_health.install_id'),
    ('0018_device_health', 'policy', 'public.device_health|device_health_select'),
    ('0018_device_health', 'policy', 'public.device_health|device_health_insert'),
    ('0018_device_health', 'policy', 'public.device_health|device_health_update'),
    ('0018_device_health', 'policy', 'public.device_health|device_health_delete'),
    ('0018_device_health', 'index', 'public|device_health_failing_idx'),
    ('0018_device_health', 'index', 'public|device_health_checked_idx'),
    ('0018_device_health', 'function', 'private.broken_devices'),
    -- المفتاح المركّب هو اللي بيخلّي الـupsert يعدّل بدل ما يزوّد صف
    ('0018_device_health', 'constraintdef', 'public.device_health|device_health_pkey|install_id'),
    ('0019_battery_state', 'column', 'public.device_health.battery_state'),
    ('0019_battery_state', 'constraintdef',
       'public.device_health|device_health_battery_state_check|unknown'),
    -- 0020 — تفضيلات المتابع
    ('0020_caregiver_preferences', 'table',  'public.caregiver_preferences'),
    ('0020_caregiver_preferences', 'rls',    'public.caregiver_preferences'),
    ('0020_caregiver_preferences', 'column', 'public.caregiver_preferences.display_name'),
    ('0020_caregiver_preferences', 'column', 'public.caregiver_preferences.relation'),
    ('0020_caregiver_preferences', 'column', 'public.caregiver_preferences.alert_scope'),
    ('0020_caregiver_preferences', 'column', 'public.caregiver_preferences.quiet_from_minute'),
    ('0020_caregiver_preferences', 'column', 'public.caregiver_preferences.quiet_to_minute'),
    ('0020_caregiver_preferences', 'policy',
       'public.caregiver_preferences|caregiver_preferences_select'),
    ('0020_caregiver_preferences', 'policy',
       'public.caregiver_preferences|caregiver_preferences_insert'),
    ('0020_caregiver_preferences', 'policy',
       'public.caregiver_preferences|caregiver_preferences_update'),
    ('0020_caregiver_preferences', 'policy',
       'public.caregiver_preferences|caregiver_preferences_delete'),
    ('0020_caregiver_preferences', 'trigger',
       'public.caregiver_preferences|set_updated_at'),
    ('0020_caregiver_preferences', 'function', 'public.followers_of_patient'),
    -- **سكّة الاشتراك** — وجودها بالاسم هو اللي بيخلّي «Pricing» مكان واحد
    ('0020_caregiver_preferences', 'function', 'private.follower_subscription_active'),
    -- **مش فحص وجود**: `due_escalations` بتتكتب من جديد في ٠٠٠٦ و٠٠٠٩
    -- و٠٠١١ و٠٠١٤ و٠٠٢٠، فوجودها بيكدب. اللي بيتأكد هو إن جسمها بينده
    -- السكّة — يعني نسخة ٠٠٢٠ هي اللي شغّالة فعلاً.
    ('0020_caregiver_preferences', 'funcsrc',
       'private.due_escalations|follower_subscription_active')
),
checked as (
  select
    e.migration,
    e.kind,
    e.ident,
    case e.kind

      -- جدول: 'public.patients'
      when 'table' then to_regclass(e.ident) is not null

      -- RLS مفعّلة على الجدول: 'public.patients'
      when 'rls' then coalesce(
        (select c.relrowsecurity from pg_class c where c.oid = to_regclass(e.ident)), false)

      -- سكيما: 'private'
      when 'schema' then exists (select 1 from pg_namespace n where n.nspname = e.ident)

      -- عمود: 'public.records.follow_kind'
      when 'column' then exists (
        select 1 from information_schema.columns c
        where c.table_schema = split_part(e.ident, '.', 1)
          and c.table_name   = split_part(e.ident, '.', 2)
          and c.column_name  = split_part(e.ident, '.', 3))

      -- دالة بالاسم (أي توقيع): 'private.due_escalations'
      when 'function' then exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = split_part(e.ident, '.', 1)
          and p.proname = split_part(e.ident, '.', 2))

      -- دالة **ونصّها فيه** كلمة: 'private.due_escalations|missed'
      -- ده اللي بيفرّق بين نسخ نفس الدالة: 0006 عملتها، و0009 و0011 و0014
      -- عدّلوها. وجودها مش دليل إن آخر نسخة هي اللي واقفة.
      when 'funcsrc' then exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = split_part(split_part(e.ident, '|', 1), '.', 1)
          and p.proname = split_part(split_part(e.ident, '|', 1), '.', 2)
          and p.prosrc like '%' || split_part(e.ident, '|', 2) || '%')

      -- سياسة: 'public.patients|patients_select'
      when 'policy' then exists (
        select 1 from pg_policies pl
        where pl.schemaname = split_part(split_part(e.ident, '|', 1), '.', 1)
          and pl.tablename  = split_part(split_part(e.ident, '|', 1), '.', 2)
          and pl.policyname = split_part(e.ident, '|', 2))

      -- سياسة **وتعريفها فيه** كلمة — زي فرق 0005 عن 0002 على نفس الاسم:
      -- 'public.patients|patients_select|is_accepted_caregiver'
      when 'policysrc' then exists (
        select 1 from pg_policies pl
        where pl.schemaname = split_part(split_part(e.ident, '|', 1), '.', 1)
          and pl.tablename  = split_part(split_part(e.ident, '|', 1), '.', 2)
          and pl.policyname = split_part(e.ident, '|', 2)
          and coalesce(pl.qual, '') || coalesce(pl.with_check, '')
                like '%' || split_part(e.ident, '|', 3) || '%')

      -- فهرس: 'public|patients_owner_idx'
      when 'index' then exists (
        select 1 from pg_indexes i
        where i.schemaname = split_part(e.ident, '|', 1)
          and i.indexname  = split_part(e.ident, '|', 2))

      -- تريجر: 'public.patients|set_updated_at'
      when 'trigger' then exists (
        select 1 from pg_trigger t
        where t.tgrelid = to_regclass(split_part(e.ident, '|', 1))
          and t.tgname = split_part(e.ident, '|', 2)
          and not t.tgisinternal)

      -- قيد **وتعريفه فيه** كلمة:
      -- 'public.dose_events|dose_events_state_check|superseded'
      when 'constraintdef' then exists (
        select 1 from pg_constraint c
        where c.conrelid = to_regclass(split_part(e.ident, '|', 1))
          and c.conname = split_part(e.ident, '|', 2)
          and pg_get_constraintdef(c.oid) like '%' || split_part(e.ident, '|', 3) || '%')

      -- مهمة cron بالاسم: 'fakkarni-escalate'
      --
      -- `cron.job` مش موجودة لو الامتداد مش متركّب، والإشارة ليها مباشرةً
      -- كانت هتوقّع السكريبت كله وقت التخطيط. فبنسأل الأول بـ`to_regclass`
      -- (بتاخد نص، فمفيش تخطيط لجدول)، وبعدين بنقراها بـ`query_to_xml`،
      -- وهي دالة **قراية** بتنفّذ الـSELECT اللي بنديهالها وبس.
      when 'cron' then case
        when to_regclass('cron.job') is null then false
        else (xpath('/row/c/text()', query_to_xml(
               format('select count(*) as c from cron.job where jobname = %L', e.ident),
               false, true, '')))[1]::text::int > 0
      end

      else false
    end as present
  from expected e
)
select
  migration                                              as "migration",
  count(*)                                               as "expected",
  count(*) filter (where present)                        as "found",
  bool_and(present)                                      as "ok",
  coalesce(string_agg(kind || ' ' || ident, ', '
           order by kind, ident) filter (where not present), '')  as "missing"
from checked
group by migration
order by migration;
