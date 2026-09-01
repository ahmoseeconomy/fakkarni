-- 0004_sync.sql — ساعة السيرفر: updated_at على كل جدول، يصونها تريجر.
--
-- طابع السيرفر هو المرجع لعرض «آخر ظهور» في 3.5 — ساعة جهاز الأب قد تكون
-- غلطاً كله، وساعة السيرفر واحدة للجميع. moddatetime امتداد Postgres قياسي
-- تشحنه Supabase.

create extension if not exists moddatetime;

alter table public.patients           add column updated_at timestamptz not null default now();
alter table public.day_routines       add column updated_at timestamptz not null default now();
alter table public.medications        add column updated_at timestamptz not null default now();
alter table public.dose_schedules     add column updated_at timestamptz not null default now();
alter table public.fixed_timings      add column updated_at timestamptz not null default now();
alter table public.dose_events        add column updated_at timestamptz not null default now();
alter table public.care_relationships add column updated_at timestamptz not null default now();

create trigger set_updated_at before update on public.patients           for each row execute procedure moddatetime (updated_at);
create trigger set_updated_at before update on public.day_routines       for each row execute procedure moddatetime (updated_at);
create trigger set_updated_at before update on public.medications        for each row execute procedure moddatetime (updated_at);
create trigger set_updated_at before update on public.dose_schedules     for each row execute procedure moddatetime (updated_at);
create trigger set_updated_at before update on public.fixed_timings     for each row execute procedure moddatetime (updated_at);
create trigger set_updated_at before update on public.dose_events        for each row execute procedure moddatetime (updated_at);
create trigger set_updated_at before update on public.care_relationships for each row execute procedure moddatetime (updated_at);
