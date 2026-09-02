-- 0004_sync.sql — ساعة السيرفر: updated_at على كل جدول، يصونها تريجر.
--
-- طابع السيرفر هو المرجع لعرض «آخر ظهور» في 3.5 — ساعة جهاز الأب قد تكون
-- غلطاً كله، وساعة السيرفر واحدة للجميع. moddatetime امتداد Postgres قياسي
-- تشحنه Supabase.

-- ملاحظة: 0001 بيدي day_routines عمود updated_at بالفعل، فالإضافة هنا
-- `if not exists` والتريجرات بتتمسح قبل ما تتعمل — الملف يتعاد تشغيله بأمان.

create extension if not exists moddatetime;

alter table public.patients           add column if not exists updated_at timestamptz not null default now();
alter table public.day_routines       add column if not exists updated_at timestamptz not null default now();
alter table public.medications        add column if not exists updated_at timestamptz not null default now();
alter table public.dose_schedules     add column if not exists updated_at timestamptz not null default now();
alter table public.fixed_timings      add column if not exists updated_at timestamptz not null default now();
alter table public.dose_events        add column if not exists updated_at timestamptz not null default now();
alter table public.care_relationships add column if not exists updated_at timestamptz not null default now();

drop trigger if exists set_updated_at on public.patients;
create trigger set_updated_at before update on public.patients for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.day_routines;
create trigger set_updated_at before update on public.day_routines for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.medications;
create trigger set_updated_at before update on public.medications for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.dose_schedules;
create trigger set_updated_at before update on public.dose_schedules for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.fixed_timings;
create trigger set_updated_at before update on public.fixed_timings for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.dose_events;
create trigger set_updated_at before update on public.dose_events for each row execute procedure moddatetime (updated_at);
drop trigger if exists set_updated_at on public.care_relationships;
create trigger set_updated_at before update on public.care_relationships for each row execute procedure moddatetime (updated_at);
