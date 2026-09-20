-- 0018 — نبضة سلامة لكل (مريض، تنزيلة)
--
-- كل عيب صلّحناه الأسبوع ده كان **ساكت**: التطبيق شكله سليم والوعد
-- مكسور. آخر واحد كلّف ماك وConsole.app وتلات ساعات. مع ألف مستخدم،
-- الطريقة الوحيدة إننا نعرف إن حساب بايظ هي إن الجهاز يقول بنفسه.
--
-- **أكواد سلامة وبس.** مفيش اسم دوا، ولا محتوى جرعة، ولا أي حاجة طبية
-- في الجدول ده — الصف بيجاوب «إيه اللي ممكن يمنع التذكير» ويقف.

create table if not exists public.device_health (
  patient_uuid      uuid not null references public.patients(uuid) on delete cascade,
  -- التنزيلة، مش الحساب: مسح بيانات التطبيق = جهاز تاني من ناحية التذكير
  install_id        text not null,
  checked_at        timestamptz not null default now(),
  app_version       text,
  platform          text,
  os_version        text,
  tz                text,
  notif_permission  text,
  pending_count     int,
  horizon_until     timestamptz,
  has_token         boolean,
  has_caregiver     boolean,
  last_sync_at      timestamptz,
  dirty_count       int,
  failing_codes     text[] not null default '{}',
  updated_at        timestamptz not null default now(),
  primary key (patient_uuid, install_id)
);

alter table public.device_health enable row level security;
revoke all on public.device_health from anon, public;

create extension if not exists moddatetime;
drop trigger if exists set_updated_at on public.device_health;
create trigger set_updated_at before update on public.device_health
  for each row execute procedure moddatetime (updated_at);

-- ملاحظة القاعدة اللي كلّفتنا قبل كده: **سياسة جدول عمرها ما تنده دالة
-- بتستعلم نفس الجدول**. الأعمدة بتاعة الصف موجودة في السياق أصلاً،
-- والدوال المعرِّفة بتوصل لجداول **تانية** بس.
drop policy if exists device_health_select on public.device_health;
create policy device_health_select on public.device_health
  for select to authenticated
  -- صاحب المريض، أو راعي مقبول — وde بيمرّ على جدول تاني، مش على ده
  using (private.can_access_patient(patient_uuid));

drop policy if exists device_health_insert on public.device_health;
create policy device_health_insert on public.device_health
  for insert to authenticated
  with check (private.owns_patient(patient_uuid));

drop policy if exists device_health_update on public.device_health;
create policy device_health_update on public.device_health
  for update to authenticated
  using (private.owns_patient(patient_uuid))
  with check (private.owns_patient(patient_uuid));

drop policy if exists device_health_delete on public.device_health;
create policy device_health_delete on public.device_health
  for delete to authenticated
  using (private.owns_patient(patient_uuid));

create index if not exists device_health_failing_idx
  on public.device_health using gin (failing_codes);

create index if not exists device_health_checked_idx
  on public.device_health (checked_at desc);

-- أنهي حسابات مكسورة دلوقتي وعلى إيه — من غير ما حد يمسك موبايل.
--
-- `private` مش مكشوف لـPostgREST، فالدالة دي للتشغيل من SQL editor أو من
-- غلاف `public` ضيق لو احتجنا واحد بعدين (زي 0007 بالظبط).
create or replace function private.broken_devices(p_stale interval default interval '24 hours')
returns table (
  patient_uuid uuid,
  install_id text,
  checked_at timestamptz,
  platform text,
  app_version text,
  failing_codes text[],
  silent boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    h.patient_uuid,
    h.install_id,
    h.checked_at,
    h.platform,
    h.app_version,
    h.failing_codes,
    -- الجهاز نفسه بقى ساكت: آخر نبضة قديمة. ده مش كود من التطبيق —
    -- ده غياب، وهو أخطر من أي كود لأن الجهاز مش بيقدر يقوله عن نفسه.
    (h.checked_at < now() - p_stale) as silent
  from public.device_health h
  where cardinality(h.failing_codes) > 0
     or h.checked_at < now() - p_stale
  order by h.checked_at desc
$$;

revoke all on function private.broken_devices(interval) from anon, authenticated;

-- ============================================================ فحص ذاتي
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_count int;
begin
  begin
    -- المالك الأول: patients.owner_id بيشاور على auth.users
    insert into auth.users (id, email) values (v_owner, 'owner-' || v_owner || '@0018.check');
    insert into auth.users (id, email) values (v_other, 'other-' || v_other || '@0018.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, 'تأكيد 0018');

    insert into public.device_health
      (patient_uuid, install_id, platform, failing_codes, pending_count, checked_at)
      values (v_pat, 'install-a', 'ios', array['reminderHorizon'], 12, now());

    -- upsert على نفس (مريض، تنزيلة) بيعدّل، ما بيزوّدش صف
    insert into public.device_health
      (patient_uuid, install_id, platform, failing_codes, pending_count, checked_at)
      values (v_pat, 'install-a', 'ios', '{}', 30, now())
    on conflict (patient_uuid, install_id) do update
      set failing_codes = excluded.failing_codes,
          pending_count = excluded.pending_count,
          checked_at = excluded.checked_at;

    select count(*) into v_count from public.device_health where patient_uuid = v_pat;
    if v_count <> 1 then
      raise exception 'FAIL 0018: الـupsert عمل صف تاني بدل ما يعدّل';
    end if;

    -- جهاز مكسور بيطلع في القايمة، والسليم لأ
    insert into public.device_health
      (patient_uuid, install_id, platform, failing_codes, checked_at)
      values (v_pat, 'install-b', 'android', array['notificationPermission'], now());

    select count(*) into v_count from private.broken_devices()
      where patient_uuid = v_pat;
    if v_count <> 1 then
      raise exception 'FAIL 0018: القايمة المفروض تجيب المكسور بس — لقت %', v_count;
    end if;

    -- وجهاز ساكت من زمان بيطلع كمان، حتى وهو من غير أكواد
    update public.device_health
      set checked_at = now() - interval '3 days'
      where patient_uuid = v_pat and install_id = 'install-a';
    select count(*) into v_count from private.broken_devices()
      where patient_uuid = v_pat and silent;
    if v_count <> 1 then
      raise exception 'FAIL 0018: الجهاز الساكت ما اتحسبش';
    end if;

    -- RLS شغّال: الجدول مقفول
    if not exists (select 1 from pg_class
                   where oid = 'public.device_health'::regclass and relrowsecurity) then
      raise exception 'FAIL 0018: RLS مش مفعّل على الجدول';
    end if;

    delete from public.patients where uuid = v_pat;
    delete from auth.users where id in (v_owner, v_other);
    raise exception '0018_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0018_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0018 OK — نبضة السلامة بتتكتب مرة لكل تنزيلة، والقايمة بتجيب المكسور والساكت';
end $$;
