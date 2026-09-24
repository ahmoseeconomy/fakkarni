-- 0026_nurse_account.sql — حساب الممرض: نوع حساب لوحده، مرآة كاملة لتطبيق
-- المريض (قرار المالك، ٢٤ سبتمبر ٢٠٢٦).
--
-- **ملف بس — ما اتطبّقش.** الترتيب: بعد 0023 و0024 و0025.
--
-- اللي فيه:
--   ١) الكود بيحمل «يقدر يعدّل الأدوية والمواعيد؟» من لحظة ما المريض عمله،
--      و`redeem_invite` بقت تعرف الباب اللي الكود اتكتب فيه: كود متابع في
--      باب الممرض (أو العكس) بيترفض **من غير ما يتحرق**.
--   ٢) أعمدة تفاصيل الدوا اللي الممرض محتاجها: الغرض والتعليمات ونوع التنبيه.
--      **لازم تتشغّل قبل ما نسخة بتدفعهم توصل موبايل مربوط** — والدفع نفسه
--      فيه شبكة أمان: لو العمود مش موجود، بيعيد من غيرهم عشان باقي الجداول
--      (والجرعات) ما تقفش.
--   ٣) التغييرات المعلّقة بقت تشمل سجل جديد وميعاد جديد (نفس جدول ٠٠٢٤).
--   ٤) الممرض بيكتب (تأكيد نيابةً / تغيير معلّق) **بس** والاشتراك شغّال.
--      القراية زي ما هي — عشان يشوف كارت «التنبيهات واقفة» ويجدّد.
--   ٥) صور الورق: باكت خاص `patient-papers`، المسار `{patient}/{record}.jpg`.
--      المريض بس بيرفع ويمسح؛ **ممرضين المريض ده بس** بيقروا — المتابع لأ.
--      الرفع نفسه مقفول على موبايل المريض ورا اختيار «شارك صور الورق مع
--      الممرض» (مقفول افتراضياً)؛ الباكت ما بيعرفش عنه حاجة.
--
-- كله idempotent.

-- ============================================================ ١) الكود والدور
alter table public.invite_codes
  add column if not exists can_edit_meds boolean not null default false;

-- التوقيع القديم (uuid, text) بيتشال عشان نداء PostgREST ما يبقاش غامض
drop function if exists public.create_invite(uuid, text);
create or replace function public.create_invite(
  p_patient_uuid uuid,
  p_role text default 'follower',
  p_can_edit_meds boolean default false
)
returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if not private.owns_patient(p_patient_uuid) then
    raise exception 'not_owner';
  end if;
  if p_role not in ('follower', 'nurse') then
    raise exception 'bad_role';
  end if;

  update public.invite_codes
     set expires_at = now()
   where patient_uuid = p_patient_uuid
     and created_by = (select auth.uid())
     and used_at is null
     and expires_at > now();

  delete from public.invite_codes
   where expires_at < now() - interval '1 day' and used_at is null;

  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    begin
      insert into public.invite_codes (code, patient_uuid, created_by, expires_at, role, can_edit_meds)
      values (v_code, p_patient_uuid, (select auth.uid()),
              now() + interval '15 minutes', p_role,
              -- التعديل للممرض بس — كود متابع عمره ما يفتحه
              p_role = 'nurse' and coalesce(p_can_edit_meds, false));
      exit;
    exception when unique_violation then
    end;
  end loop;

  return v_code;
end;
$$;

revoke execute on function public.create_invite(uuid, text, boolean) from anon, public;
grant execute on function public.create_invite(uuid, text, boolean) to authenticated;

drop function if exists public.redeem_invite(text);
create or replace function public.redeem_invite(p_code text, p_expect_role text default null)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_invite record;
  v_uid uuid := (select auth.uid());
begin
  select * into v_invite
    from public.invite_codes
   where code = p_code
     and used_at is null
     and expires_at > now();

  if not found then
    raise exception 'invalid_code';
  end if;

  -- ٠٠٢٦: الباب لازم يطابق نوع الكود — **قبل أي كتابة**، فالكود ما بيتحرقش
  if p_expect_role is not null and p_expect_role <> v_invite.role then
    raise exception 'wrong_role_%', v_invite.role;
  end if;

  if exists (select 1 from public.patients p
              where p.uuid = v_invite.patient_uuid and p.owner_id = v_uid) then
    raise exception 'own_code';
  end if;

  if exists (select 1 from public.care_relationships cr
              where cr.patient_uuid = v_invite.patient_uuid
                and cr.caregiver_id = v_uid
                and cr.status = 'accepted') then
    raise exception 'already_linked';
  end if;

  -- 0025: الاشتراك الواحد بيغطّي لحد خمسة — والممرض واحد منهم
  if (select count(*) from public.care_relationships cr
       where cr.patient_uuid = v_invite.patient_uuid and cr.status = 'accepted')
     >= private.follower_cap() then
    raise exception 'circle_full';
  end if;

  insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
  values (v_invite.patient_uuid, v_uid, 'accepted', v_invite.role,
          v_invite.role = 'nurse', v_invite.role = 'nurse' and v_invite.can_edit_meds)
  on conflict (patient_uuid, caregiver_id)
    do update set status = 'accepted',
                  role = excluded.role,
                  can_confirm = excluded.can_confirm,
                  can_edit_meds = excluded.can_edit_meds;

  update public.invite_codes
     set used_by = v_uid, used_at = now()
   where code = p_code;

  return v_invite.patient_uuid;
end;
$$;

revoke execute on function public.redeem_invite(text, text) from anon, public;
grant execute on function public.redeem_invite(text, text) to authenticated;

-- ============================================================ ٢) تفاصيل الدوا
alter table public.medications add column if not exists purpose      text;
alter table public.medications add column if not exists instructions text;
alter table public.medications add column if not exists alert_mode   text;

-- ============================================================ ٣) تغييرات معلّقة أوسع
alter table public.medication_changes drop constraint if exists medication_changes_kind_check;
alter table public.medication_changes
  add constraint medication_changes_kind_check
  check (kind in ('add', 'stop', 'amount', 'record', 'appointment'));

-- ============================================================ ٤) الكتابة مع الاشتراك بس
--
-- `family_subscription_active` مسحوبة من authenticated (0025)، والسياسة
-- بتتنفّذ بصلاحيات النادي — فالسؤال بيعدّي على دالة definer ليها سؤال واحد.
create or replace function private.circle_writes_allowed(p_patient uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.can_access_patient(p_patient) and private.family_subscription_active(p_patient);
$$;

revoke execute on function private.circle_writes_allowed(uuid) from anon, public;
grant execute on function private.circle_writes_allowed(uuid) to authenticated;

drop policy if exists proxy_confirmations_insert on public.proxy_confirmations;
create policy proxy_confirmations_insert on public.proxy_confirmations
  for insert to authenticated
  with check (
    actor_id = (select auth.uid())
    and private.can_confirm_for(patient_uuid)
    and private.dose_confirmable(dose_event_uuid, patient_uuid)
    and private.circle_writes_allowed(patient_uuid)
  );

drop policy if exists medication_changes_insert on public.medication_changes;
create policy medication_changes_insert on public.medication_changes
  for insert to authenticated
  with check (
    actor_id = (select auth.uid())
    and private.can_edit_meds_for(patient_uuid)
    and private.circle_writes_allowed(patient_uuid)
  );

-- ============================================================ ٥) صور الورق
create or replace function private.is_nurse_of(p_patient uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.care_relationships cr
    where cr.patient_uuid = p_patient
      and cr.caregiver_id = (select auth.uid())
      and cr.status = 'accepted'
      and cr.role = 'nurse'
  );
$$;

-- المريض من أول جزء في المسار. **مسار مش uuid بيرجّع null مش خطأ** —
-- خطأ تحويل جوّه سياسة كان هيوقّع أي قراية في الباكت كلها.
create or replace function private.paper_patient(p_name text)
returns uuid
language plpgsql immutable
set search_path = ''
as $$
begin
  return split_part(p_name, '/', 1)::uuid;
exception when others then
  return null;
end;
$$;

create or replace function private.can_read_paper(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.paper_patient(p_name) is not null
     and (private.owns_patient(private.paper_patient(p_name))
          or private.is_nurse_of(private.paper_patient(p_name)));
$$;

create or replace function private.can_write_paper(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.paper_patient(p_name) is not null
     and private.owns_patient(private.paper_patient(p_name));
$$;

revoke execute on function private.is_nurse_of(uuid), private.paper_patient(text),
                           private.can_read_paper(text), private.can_write_paper(text)
  from anon, public;
grant execute on function private.is_nurse_of(uuid), private.paper_patient(text),
                          private.can_read_paper(text), private.can_write_paper(text)
  to authenticated;

insert into storage.buckets (id, name, public)
values ('patient-papers', 'patient-papers', false)
on conflict (id) do update set public = false;

drop policy if exists patient_papers_select on storage.objects;
create policy patient_papers_select on storage.objects
  for select to authenticated
  using (bucket_id = 'patient-papers' and private.can_read_paper(name));

drop policy if exists patient_papers_insert on storage.objects;
create policy patient_papers_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'patient-papers' and private.can_write_paper(name));

drop policy if exists patient_papers_update on storage.objects;
create policy patient_papers_update on storage.objects
  for update to authenticated
  using (bucket_id = 'patient-papers' and private.can_write_paper(name))
  with check (bucket_id = 'patient-papers' and private.can_write_paper(name));

drop policy if exists patient_papers_delete on storage.objects;
create policy patient_papers_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'patient-papers' and private.can_write_paper(name));

-- ============================================================ فحص ذاتي
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_sched    uuid := gen_random_uuid();
  v_event    uuid := gen_random_uuid();
  v_event2   uuid := gen_random_uuid();
  v_code     text;
  v_n        integer;
  v_denied   boolean;
  v_err      text;
  v_path     text;
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'care_relationships'
                   and column_name = 'can_edit_meds') then
    raise exception 'FAIL 0026: شغّل 0023 الأول';
  end if;
  if to_regclass('public.medication_changes') is null then
    raise exception 'FAIL 0026: شغّل 0024 الأول';
  end if;
  if to_regclass('public.family_subscriptions') is null then
    raise exception 'FAIL 0026: شغّل 0025 الأول';
  end if;
  if not exists (select 1 from storage.buckets where id = 'patient-papers' and not public) then
    raise exception 'FAIL 0026: باكت الصور مش موجود أو مش خاص';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0026.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0026.check'),
      (v_son,      'son-'      || v_son      || '@0026.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0026.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0026');

    -- ١) المريض بيعمل كود ممرض بتعديل، والباب الغلط بيرفضه من غير ما يحرقه
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    v_code := public.create_invite(v_pat, 'nurse', true);
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    v_err := null;
    begin
      perform public.redeem_invite(v_code, 'follower');
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'wrong_role_nurse' then
      raise exception 'FAIL 0026: كود ممرض في باب المتابع عدّى (%)', v_err;
    end if;
    perform public.redeem_invite(v_code, 'nurse');
    execute 'reset role';
    if not exists (select 1 from public.care_relationships
                   where patient_uuid = v_pat and caregiver_id = v_nurse
                     and role = 'nurse' and can_confirm and can_edit_meds) then
      raise exception 'FAIL 0026: الممرض ما اتربطش بدوره وصلاحية التعديل';
    end if;

    -- كود متابع في باب الممرض: مرفوض ومش محروق، وبعدها الابن بيستعمله عادي
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    v_code := public.create_invite(v_pat, 'follower', true);  -- التعديل بيتجاهل لمتابع
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    v_err := null;
    begin
      perform public.redeem_invite(v_code, 'nurse');
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'wrong_role_follower' then
      raise exception 'FAIL 0026: كود متابع في باب الممرض عدّى (%)', v_err;
    end if;
    perform public.redeem_invite(v_code, 'follower');
    execute 'reset role';
    if not exists (select 1 from public.care_relationships
                   where patient_uuid = v_pat and caregiver_id = v_son
                     and role = 'follower' and not can_edit_meds) then
      raise exception 'FAIL 0026: المتابع خد تعديل الأدوية';
    end if;

    -- ٢) الممرض بيقرا تفاصيل الدوا، والغريب لأ
    insert into public.medications (uuid, patient_uuid, name, purpose, instructions, alert_mode)
      values (v_med, v_pat, 'Concor', 'pressure', 'بعد الأكل', 'repeating');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date)
      values (v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date);
    insert into public.dose_events (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
      values (v_event, v_sched, current_date, now() - interval '10 minutes', 'pending'),
             (v_event2, v_sched, current_date - 1, now() - interval '20 minutes', 'pending');

    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medications where uuid = v_med and instructions = 'بعد الأكل';
    if v_n <> 1 then raise exception 'FAIL 0026: الممرض مش شايف تفاصيل الدوا'; end if;
    -- والاشتراك شغّال: التأكيد نيابةً بيعدّي (عشان الرفض تحت يبقى بسبب الاشتراك وبس)
    insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id)
      values (v_event, v_pat, v_nurse);
    -- ميعاد معلّق من الممرض
    insert into public.medication_changes (patient_uuid, actor_id, kind, payload)
      values (v_pat, v_nurse, 'appointment', '{"follow_kind":"visit","day":"2026-10-01"}'::jsonb);
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medications where uuid = v_med;
    if v_n <> 0 then raise exception 'FAIL 0026: غريب شاف الأدوية'; end if;
    execute 'reset role';

    -- ٣) المتابع ما بيكتبش تغيير
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      insert into public.medication_changes (patient_uuid, actor_id, kind) values (v_pat, v_son, 'record');
    exception when insufficient_privilege then v_denied := true;
    end;
    execute 'reset role';
    if not v_denied then raise exception 'FAIL 0026: المتابع كتب تغيير معلّق'; end if;

    -- ٤) الصور: المالك والممرض بيقروا، والمتابع والغريب لأ، والكتابة للمالك بس
    v_path := v_pat::text || '/' || gen_random_uuid()::text || '.jpg';
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    if not private.can_read_paper(v_path) or not private.can_write_paper(v_path) then
      raise exception 'FAIL 0026: المالك مش بيقرا/يكتب صوره';
    end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    if not private.can_read_paper(v_path) then raise exception 'FAIL 0026: الممرض مش بيقرا الصورة'; end if;
    if private.can_write_paper(v_path) then raise exception 'FAIL 0026: الممرض بيكتب في صور المريض'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    if private.can_read_paper(v_path) then raise exception 'FAIL 0026: المتابع شاف الصورة'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    if private.can_read_paper(v_path) then raise exception 'FAIL 0026: غريب شاف الصورة'; end if;
    if private.can_read_paper('مش-uuid/x.jpg') then raise exception 'FAIL 0026: مسار بايظ عدّى'; end if;
    execute 'reset role';

    -- ٥) الاشتراك خلص: الممرض لسه بيقرا، بس ما بيأكّدش ولا بيبعت تغيير
    update public.family_subscriptions set status = 'expired' where patient_uuid = v_pat;
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medications where uuid = v_med;
    if v_n <> 1 then raise exception 'FAIL 0026: الممرض اتقفل عن القراية'; end if;
    v_denied := false;
    begin
      insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id)
        values (v_event2, v_pat, v_nurse);
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0026: تأكيد نيابةً عدّى والاشتراك منتهي'; end if;
    v_denied := false;
    begin
      insert into public.medication_changes (patient_uuid, actor_id, kind) values (v_pat, v_nurse, 'stop');
    exception when insufficient_privilege then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0026: تغيير معلّق عدّى والاشتراك منتهي'; end if;
    execute 'reset role';

    raise exception '0026_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0026_ROLLBACK' then raise; end if;
  end;

  raise notice '0026 OK — كود الممرض بصلاحيته، الباب الغلط بيرفض من غير ما يحرق، الممرض بيقرا والمتابع ما بيكتبش، الصور للمالك والممرض بس، والكتابة مع الاشتراك بس';
end $$;
