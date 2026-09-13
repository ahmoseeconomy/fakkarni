-- 0001_schema.sql — المرآة السحابية لمخطط drift المحلي (lib/data/db/tables.dart)
--
-- قاعدتان حاكمتان:
--   * المفتاح الأساسي سحابياً هو uuid الصف — **مولود على الجهاز** (جولة 3.2a)،
--     ومفيش DEFAULT له هنا عن قصد: السيرفر عمره ما يولّد هوية، والإدخال
--     الناقص يفشل بصوت بدل ما ياخد هوية سيرفر في صمت.
--   * الأرقام التسلسلية المحلية (int id) لا تغادر الجهاز أبداً — لا يوجد
--     عمود لها هنا إطلاقاً. علاقات السحابة كلها على uuid.
--
-- ملاحظة أمان: مفتاح النشر (publishable key) داخل التطبيق نفسه — أي حد
-- يقدر يستخرجه ويكلم Postgres مباشرة. RLS في 0002 هو الحاجز الوحيد.
-- الملف ده لا يُشغَّل بدون 0002 بعده فوراً.
--
-- `if not exists` على كل جدول وفهرس: السلسلة كلها لازم تعيد التشغيل من
-- الأول بأمان (وعد مكتوب في README، وكان **غلط** — الملف ده كان بيقع من
-- أول `create table` على أي مشروع شغّال). الثمن المعروف: إعادة التشغيل
-- ما بتغيّرش شكل جدول موجود. وده المطلوب — الترحيلات تاريخ، وتغيير الشكل
-- بيجي في ملف جديد بترقيمه، مش بتعديل ملف قديم.

-- ---------------------------------------------------------------- patients
create table if not exists public.patients (
  uuid              uuid primary key,            -- device-minted, no default
  owner_id          uuid not null references auth.users (id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 80),
  -- خانة أرقام الإشعارات محلية بطبيعتها (نطاق per-device). بنعكسها كبيانات
  -- بس من غير UNIQUE العالمي المحلي — التفرّد هنا معناه per-device مش عالمي.
  notification_slot integer not null default 0,
  created_at        timestamptz not null default now()
);

create index if not exists patients_owner_idx on public.patients (owner_id);

-- ------------------------------------------------------------ day_routines
create table if not exists public.day_routines (
  uuid              uuid primary key,
  patient_uuid      uuid not null references public.patients (uuid) on delete cascade,
  wake_minutes      integer not null check (wake_minutes      between 0 and 1439),
  breakfast_minutes integer not null check (breakfast_minutes between 0 and 1439),
  lunch_minutes     integer not null check (lunch_minutes     between 0 and 1439),
  dinner_minutes    integer not null check (dinner_minutes    between 0 and 1439),
  sleep_minutes     integer not null check (sleep_minutes     between 0 and 1439),
  updated_at        timestamptz not null default now(),
  created_at        timestamptz not null default now(),
  unique (patient_uuid)                          -- روتين واحد للمريض
);

-- ------------------------------------------------------------- medications
create table if not exists public.medications (
  uuid           uuid primary key,
  patient_uuid   uuid not null references public.patients (uuid) on delete cascade,
  name           text not null check (char_length(name) between 1 and 120),
  amount_label   text,
  notes          text,
  -- null = الدوا شغّال. لا يُكتب إلا بيد إنسان (قاعدة المنتج الثالثة).
  stopped_at     timestamptz,
  amount_unknown boolean not null default false,
  created_at     timestamptz not null default now()
);

create index if not exists medications_patient_idx on public.medications (patient_uuid);

-- ---------------------------------------------------------- dose_schedules
create table if not exists public.dose_schedules (
  uuid            uuid primary key,
  medication_uuid uuid not null references public.medications (uuid) on delete cascade,
  timing_kind     text not null default 'anchor'
                    check (timing_kind in ('anchor', 'fixed')),
  anchor          text check (anchor in ('wake','breakfast','lunch','dinner','sleep')),
  offset_minutes  integer,
  repeat          text not null check (repeat in ('daily', 'once')),
  start_date      date not null,
  duration_days   integer check (duration_days > 0),  -- null = مدة مفتوحة، أبداً لا تُخمَّن
  created_at      timestamptz not null default now(),
  -- نفس عقد drift: مرساة بمرساتها، وثابتة من غير مرساة
  check (
    (timing_kind = 'anchor' and anchor is not null)
    or (timing_kind = 'fixed' and anchor is null and offset_minutes is null)
  )
);

create index if not exists dose_schedules_medication_idx on public.dose_schedules (medication_uuid);

-- ----------------------------------------------------------- fixed_timings
create table if not exists public.fixed_timings (
  uuid               uuid primary key,
  dose_schedule_uuid uuid not null unique
                       references public.dose_schedules (uuid) on delete cascade,
  minute_of_day      integer not null check (minute_of_day between 0 and 1439),
  created_at         timestamptz not null default now()
);

-- ------------------------------------------------------------- dose_events
create table if not exists public.dose_events (
  uuid               uuid primary key,
  dose_schedule_uuid uuid not null references public.dose_schedules (uuid) on delete cascade,
  routine_day        date not null,
  scheduled_at       timestamptz not null,
  state              text not null check (state in ('pending','taken','skipped','missed')),
  acted_at           timestamptz,
  created_at         timestamptz not null default now(),
  unique (dose_schedule_uuid, routine_day)       -- مفتاح الحدث زي المحلي
);

create index if not exists dose_events_schedule_idx on public.dose_events (dose_schedule_uuid);

-- ------------------------------------------------------ care_relationships
-- الجدول بس — تدفّق كود الدعوة جولة 3.3. موجود من دلوقتي لأن سياساته
-- وسياسات patients نصفا تصميم واحد ولا يُكتبان منفصلين.
create table if not exists public.care_relationships (
  uuid         uuid primary key default gen_random_uuid(),
  patient_uuid uuid not null references public.patients (uuid) on delete cascade,
  caregiver_id uuid not null references auth.users (id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending', 'accepted', 'revoked')),
  created_at   timestamptz not null default now(),
  unique (patient_uuid, caregiver_id)
);

create index if not exists care_relationships_caregiver_idx on public.care_relationships (caregiver_id);
create index if not exists care_relationships_patient_idx   on public.care_relationships (patient_uuid);
