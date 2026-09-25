-- ============================================================================
-- 0029 — صور الأدوية للدائرة (ملف بس — ما اتطبّقش)
-- ============================================================================
-- الباكت نفسه `patient-papers` (0026)، تحت مسار واضح:
--   {patient_uuid}/med-photos/{medication_uuid}.jpg        ← نسخة المريض
--   {patient_uuid}/med-photos/pending/{change_uuid}.jpg    ← صورة من الممرض
--
-- **ليه محتاجة هجرة أصلاً** (المطلوب كان «من غير ما نلمس السياسات»):
-- سياسات 0026 بتقول القراية للمالك والممرض بس، والكتابة للمالك بس. ده
-- بيكفي للمريض يرفع والممرض يشوف — بس **المتابع (الابن) مالوش قراية**،
-- و**الممرض مالوش كتابة** يبعت بيها صورة جديدة. الاتنين مطلوبين.
--
-- **سياسات 0026 ما اتلمستش**: الصور الورقية لسه للمالك والممرض بس. اللي
-- اتضاف سياسات **جديدة** على مسار `med-photos/` بس (السياسات في Postgres
-- بتتجمع بـOR، فالجديدة بتفتح المسار ده وبس):
--   * القراية: أي حد في الدائرة (المالك + أي علاقة مقبولة، متابع أو ممرض).
--   * الكتابة على النسخة الرسمية: المالك بس (موبايله مصدر الحقيقة).
--   * الممرض اللي معاه «يعدّل الأدوية» والاشتراك شغّال: بيرفع تحت
--     `pending/` بس، ويبعت تغيير معلّق نوعه 'photo' — موبايل المريض بيسحبه
--     ويطبّقه بسكّته (زي باقي تغييرات 0024).
--   * نوع 'photo' على `medication_changes`.
--
-- الترتيب: بعد 0023 → 0028. idempotent.

-- --------------------------------------------------------------- ١) الدوال
create or replace function private.med_photo_patient(p_name text)
returns uuid
language sql immutable
set search_path = ''
as $$
  select case when split_part(p_name, '/', 2) = 'med-photos'
              then private.paper_patient(p_name) end;
$$;

-- القراية: الدائرة كلها (can_access_patient = المالك + علاقة مقبولة بأي دور)
create or replace function private.can_read_med_photo(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.med_photo_patient(p_name) is not null
     and private.can_access_patient(private.med_photo_patient(p_name));
$$;

-- الكتابة الرسمية: المالك بس، على أي حاجة تحت med-photos/ (وده بيشمل
-- إنه يمسح صورة الممرض بعد ما يطبّقها)
create or replace function private.can_write_med_photo(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.med_photo_patient(p_name) is not null
     and private.owns_patient(private.med_photo_patient(p_name));
$$;

-- الممرض: تحت pending/ بس، بصلاحية التعديل، والاشتراك شغّال
create or replace function private.can_stage_med_photo(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select private.med_photo_patient(p_name) is not null
     and split_part(p_name, '/', 3) = 'pending'
     and private.can_edit_meds_for(private.med_photo_patient(p_name))
     and private.circle_writes_allowed(private.med_photo_patient(p_name));
$$;

revoke execute on function private.med_photo_patient(text), private.can_read_med_photo(text),
                           private.can_write_med_photo(text), private.can_stage_med_photo(text)
  from anon, public;
grant execute on function private.med_photo_patient(text), private.can_read_med_photo(text),
                          private.can_write_med_photo(text), private.can_stage_med_photo(text)
  to authenticated;

-- --------------------------------------------------------------- ٢) السياسات
drop policy if exists med_photos_select on storage.objects;
create policy med_photos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'patient-papers' and private.can_read_med_photo(name));

drop policy if exists med_photos_insert on storage.objects;
create policy med_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'patient-papers'
              and (private.can_write_med_photo(name) or private.can_stage_med_photo(name)));

drop policy if exists med_photos_update on storage.objects;
create policy med_photos_update on storage.objects
  for update to authenticated
  using (bucket_id = 'patient-papers' and private.can_write_med_photo(name))
  with check (bucket_id = 'patient-papers' and private.can_write_med_photo(name));

drop policy if exists med_photos_delete on storage.objects;
create policy med_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'patient-papers' and private.can_write_med_photo(name));

-- --------------------------------------------------------------- ٣) نوع التغيير
alter table public.medication_changes drop constraint if exists medication_changes_kind_check;
alter table public.medication_changes
  add constraint medication_changes_kind_check
  check (kind in ('add', 'stop', 'amount', 'record', 'appointment', 'restock', 'photo'));

-- --------------------------------------------------------------- ٤) فحص ذاتي
-- بيختبر **من الجداول و RLS بس** تحت `set local role authenticated`:
-- إدخال وقراية على storage.objects و medication_changes — **ولا نداء
-- private.* وإحنا في الدور ده** (authenticated مالوش USAGE على private؛
-- السياسات نفسها بتنده الدوال بالـOID، ومش محتاجة USAGE).
-- ما بيمسحش من storage.objects بـSQL (Supabase بيمنع المسح المباشر) —
-- الـrollback في الآخر هو اللي بيشيل كل حاجة.
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_viewer   uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_official text;
  v_pending  text;
  v_paper    text;
  v_who      uuid;
  v_n        integer;
  v_denied   boolean;
begin
  if not exists (select 1 from storage.buckets where id = 'patient-papers' and not public) then
    raise exception 'FAIL 0029: شغّل 0026 الأول (الباكت مش موجود)';
  end if;
  if not exists (select 1 from pg_constraint where conname = 'medication_changes_kind_check'
                 and pg_get_constraintdef(oid) like '%restock%') then
    raise exception 'FAIL 0029: شغّل 0028 الأول';
  end if;

  v_official := v_pat::text || '/med-photos/' || v_med::text || '.jpg';
  v_pending  := v_pat::text || '/med-photos/pending/' || gen_random_uuid()::text || '.jpg';
  v_paper    := v_pat::text || '/' || gen_random_uuid()::text || '.jpg';

  begin
    -- المالك في auth.users **قبل** المريض — درس ٠٠١٦
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0029.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0029.check'),
      (v_viewer,   'viewer-'   || v_viewer   || '@0029.check'),
      (v_son,      'son-'      || v_son      || '@0029.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0029.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0029');
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
      values (v_pat, v_nurse,  'accepted', 'nurse',    true,  true),
             (v_pat, v_viewer, 'accepted', 'nurse',    true,  false),
             (v_pat, v_son,    'accepted', 'follower', false, false);

    -- ١) المالك بيرفع النسخة الرسمية وورقة عادية
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    insert into storage.objects (bucket_id, name, owner) values ('patient-papers', v_official, v_owner);
    insert into storage.objects (bucket_id, name, owner) values ('patient-papers', v_paper, v_owner);
    execute 'reset role';

    -- ٢) الدائرة كلها بتشوف صورة الدوا — الابن (متابع) كمان
    foreach v_who in array array[v_nurse, v_viewer, v_son] loop
      perform set_config('request.jwt.claims', json_build_object('sub', v_who)::text, true);
      execute 'set local role authenticated';
      select count(*) into v_n from storage.objects where bucket_id = 'patient-papers' and name = v_official;
      execute 'reset role';
      if v_n <> 1 then raise exception 'FAIL 0029: حد من الدائرة مش شايف صورة الدوا'; end if;
    end loop;

    -- ٣) **الورق زي ما هو**: الابن لسه ما بيشوفش صورة ورقة (0026 ما اتلمستش)
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from storage.objects where bucket_id = 'patient-papers' and name = v_paper;
    execute 'reset role';
    if v_n <> 0 then raise exception 'FAIL 0029: الابن بقى شايف صور الورق'; end if;

    -- ٤) الغريب ما بيشوفش
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from storage.objects where bucket_id = 'patient-papers' and name = v_official;
    execute 'reset role';
    if v_n <> 0 then raise exception 'FAIL 0029: غريب شاف صورة الدوا'; end if;

    -- ٥) الابن والممرض ما بيكتبوش على النسخة الرسمية
    foreach v_who in array array[v_son, v_nurse] loop
      perform set_config('request.jwt.claims', json_build_object('sub', v_who)::text, true);
      execute 'set local role authenticated';
      v_denied := false;
      begin
        insert into storage.objects (bucket_id, name, owner)
          values ('patient-papers', v_pat::text || '/med-photos/' || gen_random_uuid()::text || '.jpg', v_who);
      exception when insufficient_privilege then v_denied := true;
      end;
      execute 'reset role';
      if not v_denied then raise exception 'FAIL 0029: حد غير المالك كتب النسخة الرسمية'; end if;
    end loop;

    -- ٦) الممرض بصلاحية التعديل بيرفع تحت pending/ ويبعت تغيير 'photo'
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    insert into storage.objects (bucket_id, name, owner) values ('patient-papers', v_pending, v_nurse);
    insert into public.medication_changes (patient_uuid, actor_id, kind, medication_uuid, payload)
      values (v_pat, v_nurse, 'photo', v_med, json_build_object('photo_path', v_pending)::jsonb);
    execute 'reset role';

    -- ٧) ممرض من غير «يعدّل الأدوية» والابن: لا pending ولا تغيير
    foreach v_who in array array[v_viewer, v_son] loop
      perform set_config('request.jwt.claims', json_build_object('sub', v_who)::text, true);
      execute 'set local role authenticated';
      v_denied := false;
      begin
        insert into storage.objects (bucket_id, name, owner)
          values ('patient-papers', v_pat::text || '/med-photos/pending/' || gen_random_uuid()::text || '.jpg', v_who);
      exception when insufficient_privilege then v_denied := true;
      end;
      execute 'reset role';
      if not v_denied then raise exception 'FAIL 0029: رفع pending من غير صلاحية التعديل'; end if;
    end loop;

    -- ٨) الاشتراك خلص: الممرض لسه بيشوف، بس ما بيرفعش
    update public.family_subscriptions set status = 'expired', expires_at = now() - interval '30 days'
      where patient_uuid = v_pat;
    if not found then
      insert into public.family_subscriptions (patient_uuid, status, trial_ends_at, expires_at)
        values (v_pat, 'expired', now() - interval '30 days', now() - interval '30 days');
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from storage.objects where bucket_id = 'patient-papers' and name = v_official;
    v_denied := false;
    begin
      insert into storage.objects (bucket_id, name, owner)
        values ('patient-papers', v_pat::text || '/med-photos/pending/' || gen_random_uuid()::text || '.jpg', v_nurse);
    exception when insufficient_privilege then v_denied := true;
    end;
    execute 'reset role';
    if v_n <> 1 then raise exception 'FAIL 0029: الممرض اتقفل عن القراية'; end if;
    if not v_denied then raise exception 'FAIL 0029: الممرض رفع والاشتراك منتهي'; end if;

    raise exception '0029_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0029_ROLLBACK' then raise; end if;
  end;

  raise notice '0029 OK — الدائرة كلها بتشوف صورة الدوا، الورق زي ما هو، الرسمية للمالك، والممرض بصلاحية التعديل بيرفع pending والاشتراك شغّال';
end $$;
