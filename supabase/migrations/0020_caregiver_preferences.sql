-- 0020 — تفضيلات المتابع: اسمه وصلته، ونطاق تنبيهه، وساعات هدوئه.
--
-- **الإعدادات دي بتغيّر اللي بيوصل الابن وبس.** تذكير الأب وسلّم التصعيد
-- وأي حاجة على جهاز الأب ما بتتلمسش من هنا.
--
-- تلات قرارات من المالك (٢٢ سبتمبر ٢٠٢٦) مكتوبة في الملف ده لأنها هي
-- اللي بتحدد شكله:
--
--   ١. **مفيش علامة «دوا مهم»**، واتشالت عن قصد في ٢ سبتمبر (القاعدة ٦).
--      فـ`alert_scope` ليها قيمة واحدة النهارده. العمود والقيد موجودين
--      عشان اليوم اللي تبقى فيه العلامة موجودة يبقى سطر واحد، مش هجرة.
--
--   ٢. **ساعات الهدوء للمواعيد والملخصات بس.** جرعة فايتة بتوصل الابن في
--      أي وقت. عشان كده `due_escalations` **ما بتقراش** ساعات الهدوء
--      خالص — النافذة دي بتتطبّق على إشعارات المواعيد المحلية على موبايل
--      الابن، واللي بتتأجّل لآخر النافذة (ما بتتلغيش). تأجيل تنبيه جرعة
--      فايتة لحد الصبح هو بالظبط الحاجة اللي السلّم موجود عشان يمنعها.
--
--   ٣. **الأب بيقرا الاسم والصلة وبس.** سياسات بوستجرس على مستوى الصف مش
--      العمود، فلو اتسمح له بالصف كان هيقرا ساعات هدوء ابنه ونطاق تنبيهه.
--      الدالة `public.followers_of_patient` بترجّع العمودين دول وبس.
--
-- idempotent زي كل الملفات: `if not exists` و`create or replace`.

-- ---------------------------------------------------------------- الجدول
create table if not exists public.caregiver_preferences (
  caregiver_id      uuid not null references auth.users (id) on delete cascade,
  patient_uuid      uuid not null references public.patients (uuid) on delete cascade,
  display_name      text,
  relation          text check (relation in ('son', 'daughter', 'other')),
  relation_other    text,
  -- قيمة واحدة النهارده — شوف القرار ١ فوق.
  alert_scope       text not null default 'everyMissedDose'
                    check (alert_scope in ('everyMissedDose')),
  -- بالدقايق من نص الليل. الاتنين null = مفيش هدوء.
  -- **والبداية ما تساويش النهاية**: نافذة كده يا يوم كامل صمت يا مفيش
  -- نافذة — الغموض ده بيتقال بـnull مش بقيمة.
  quiet_from_minute integer check (quiet_from_minute between 0 and 1439),
  quiet_to_minute   integer check (quiet_to_minute   between 0 and 1439),
  constraint caregiver_preferences_quiet_pair check (
    (quiet_from_minute is null) = (quiet_to_minute is null)
  ),
  constraint caregiver_preferences_quiet_not_empty check (
    quiet_from_minute is null or quiet_from_minute <> quiet_to_minute
  ),
  updated_at        timestamptz not null default now(),
  primary key (caregiver_id, patient_uuid)
);

alter table public.caregiver_preferences enable row level security;
revoke all on public.caregiver_preferences from anon, public;

-- ختم السيرفر، زي كل جدول تاني (٠٠٠٤).
drop trigger if exists set_updated_at on public.caregiver_preferences;
create trigger set_updated_at
  before update on public.caregiver_preferences
  for each row execute procedure moddatetime (updated_at);

-- ------------------------------------------------------------- السياسات
--
-- **الصف بيقارن عموده هو** (قاعدة ٠٠٠٥): مفيش دالة بتستعلم نفس الجدول،
-- ومفيش `can_access_patient` هنا في أي اتجاه — ده صف الابن، والأب بيوصله
-- بالدالة اللي تحت مش بسياسة.
drop policy if exists caregiver_preferences_select on public.caregiver_preferences;
create policy caregiver_preferences_select on public.caregiver_preferences
  for select to authenticated
  using (caregiver_id = (select auth.uid()));

drop policy if exists caregiver_preferences_insert on public.caregiver_preferences;
create policy caregiver_preferences_insert on public.caregiver_preferences
  for insert to authenticated
  with check (
    caregiver_id = (select auth.uid())
    -- **وبس لمريض هو متابعه فعلاً**: من غير الشرط ده، صاحب مفتاح عرف
    -- uuid مريض يقدر يكتب صف تفضيلات عليه — مش تسريب، بس صفوف بتترمي
    -- على جدول من برّه الدائرة.
    and private.is_accepted_caregiver(patient_uuid)
  );

drop policy if exists caregiver_preferences_update on public.caregiver_preferences;
create policy caregiver_preferences_update on public.caregiver_preferences
  for update to authenticated
  using (caregiver_id = (select auth.uid()))
  with check (caregiver_id = (select auth.uid()));

drop policy if exists caregiver_preferences_delete on public.caregiver_preferences;
create policy caregiver_preferences_delete on public.caregiver_preferences
  for delete to authenticated
  using (caregiver_id = (select auth.uid()));

-- --------------------------------------------- اللي الأب بيقراه، وبس هو
--
-- الاسم والصلة. **مفيش ساعات هدوء ولا نطاق تنبيه** — دي حاجة الابن.
create or replace function public.followers_of_patient(p_patient_uuid uuid)
returns table (display_name text, relation text, relation_other text)
language sql stable security definer
set search_path = ''
as $$
  select cp.display_name, cp.relation, cp.relation_other
  from public.caregiver_preferences cp
  join public.care_relationships cr
       on cr.patient_uuid = cp.patient_uuid
      and cr.caregiver_id = cp.caregiver_id
      and cr.status = 'accepted'
  where cp.patient_uuid = p_patient_uuid
    -- **الأب وبس** — الدالة definer، فالشرط ده هو الحارس كله.
    and private.owns_patient(p_patient_uuid)
  order by cp.display_name;
$$;

revoke execute on function public.followers_of_patient(uuid) from anon, public;
grant  execute on function public.followers_of_patient(uuid) to authenticated;

-- ------------------------------------------------- سكّة الاشتراك (Pricing)
--
-- **ده السيم — المكان الوحيد اللي فحص الاشتراك هيتحط فيه.**
--
-- قرار المالك (٢٢ سبتمبر ٢٠٢٦، قسم «Pricing» في CLAUDE.md): صاحب حساب
-- المريض بيدفع اشتراكه، **وكل متابع بيدفع اشتراقه هو**. مفيش كود دفع
-- النهارده — مستني حساب Apple Developer (الدين ٣) — فالدالة دي بترجّع
-- `true` دايماً.
--
-- ولمّا تشتغل: سؤال السلامة رقم ٢ في «Pricing» بيقول إن المتابع اللي
-- اشتراكه وقف **لازم يتقاله**، و**الأب لازم يتقاله** إن الشخص ده مابقاش
-- بيتابعه — الأب اللي فاكر إن حد بيراقب ومحدش بيراقب أسوأ من إنه عمره ما
-- ربط حد. فالمكان ده مش بس فلتر؛ هو كمان اللي بيعرف إمتى الخبرين دول
-- يتبعتوا.
create or replace function private.follower_subscription_active(p_caregiver uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select true;
$$;

revoke execute on function private.follower_subscription_active(uuid) from anon, public, authenticated;
grant  execute on function private.follower_subscription_active(uuid) to service_role;

-- ------------------------------------------ الاختيار: نفس ٠٠١٤ + السيم
--
-- **التعريف الوحيد لـ«مين يستاهل تنبيه»** (القاعدة من ٠٠٠٦). اللي اتزوّد
-- سطر واحد: سكّة الاشتراك. **ومفيش ساعات هدوء هنا عن قصد** — قرار ٢ فوق.
create or replace function private.due_escalations(p_limit integer default 200)
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
  select ev.uuid,
         p.uuid,
         p.name,
         m.name,
         ev.scheduled_at,
         cr.caregiver_id
  from public.dose_events ev
  join public.dose_schedules s on s.uuid = ev.dose_schedule_uuid
  join public.medications    m on m.uuid = s.medication_uuid
  join public.patients       p on p.uuid = m.patient_uuid
  join public.care_relationships cr
       on cr.patient_uuid = p.uuid
      and cr.status = 'accepted'
  where ev.state in ('pending', 'missed')
    and ev.scheduled_at <= now() - private.server_grace_window()
    and ev.scheduled_at >  now() - interval '2 days'
    and m.stopped_at is null
    and m.removed_at is null
    and s.stopped_at is null
    -- 0020: سكّة الاشتراك — `true` دايماً لحد ما الدفع يتبني.
    and private.follower_subscription_active(cr.caregiver_id)
    and not exists (
      select 1
      from public.escalations e
      where e.dose_event_uuid = ev.uuid
        and e.caregiver_id    = cr.caregiver_id
        and e.rung            = 'caregiver'
        and (
          e.delivery_status <> 'claimed'
          or e.created_at > now() - private.escalation_retry_after()
        )
    )
  order by ev.scheduled_at
  limit p_limit;
$$;

revoke execute on function private.due_escalations(integer) from anon, public, authenticated;
grant  execute on function private.due_escalations(integer) to service_role;

-- ================================================================ تأكيد
--
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله
-- يترجع. **والمالك بيتعمل في `auth.users` الأول** — `patients.owner_id`
-- مفتاح أجنبي عليه، ولو اتنسي الملف كله بيترجع والهجرة اللي افتكرتها
-- اتطبّقت عمرها ما اتطبّقت (درس ٠٠١٦).
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_sched    uuid := gen_random_uuid();
  v_event    uuid := gen_random_uuid();
  v_n        integer;
  v_due      boolean;
begin
  -- الجدول والأعمدة موجودين
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'caregiver_preferences'
                   and column_name = 'quiet_from_minute') then
    raise exception 'FAIL 0020: caregiver_preferences.quiet_from_minute مش موجود';
  end if;
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'caregiver_preferences'
                   and c.relrowsecurity) then
    raise exception 'FAIL 0020: RLS مش مفعّل على caregiver_preferences';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0020.check'),
      (v_son,      'son-'      || v_son      || '@0020.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0020.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0020');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');

    insert into public.caregiver_preferences
      (caregiver_id, patient_uuid, display_name, relation, quiet_from_minute, quiet_to_minute)
      values (v_son, v_pat, 'محمد', 'son', 0, 420);

    -- ١) الابن بيقرا صفّه
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.caregiver_preferences;
    if v_n <> 1 then raise exception 'FAIL 0020: الابن مش شايف صفّه (%)', v_n; end if;

    -- ٢) غريب ما بيشوفش حاجة
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.caregiver_preferences;
    if v_n <> 0 then raise exception 'FAIL 0020: غريب شاف تفضيلات (%)', v_n; end if;

    -- ٣) **الأب ما بيشوفش الصف** — لا ساعات هدوء ولا نطاق تنبيه…
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.caregiver_preferences;
    if v_n <> 0 then raise exception 'FAIL 0020: الأب قرا صف التفضيلات (%)', v_n; end if;

    -- …ولكن بيقرا الاسم والصلة بالدالة
    select count(*) into v_n from public.followers_of_patient(v_pat);
    if v_n <> 1 then raise exception 'FAIL 0020: الأب مش شايف متابعه (%)', v_n; end if;
    if not exists (select 1 from public.followers_of_patient(v_pat)
                   where display_name = 'محمد' and relation = 'son') then
      raise exception 'FAIL 0020: الاسم أو الصلة غلط';
    end if;

    -- ٤) وغريب ما بيجبش حاجة من الدالة — definer، والحارس جوّاها
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.followers_of_patient(v_pat);
    if v_n <> 0 then raise exception 'FAIL 0020: غريب قرا متابعين (%)', v_n; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);

    -- ٥) **جرعة فايتة بتعدّي مهما كانت ساعات الهدوء** — قرار ٢ فوق.
    -- ساعات الهدوء بتاعة الابن ٠٠:٠٠–٠٧:٠٠ فوق؛ الاختيار ما بيقراهاش أصلاً.
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind, anchor,
                                       offset_minutes, repeat, start_date)
      values (v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date);
    insert into public.dose_events (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
      values (v_event, v_sched, current_date, now() - interval '90 minutes', 'pending');

    select exists (select 1 from private.due_escalations(200)
                   where dose_event_uuid = v_event) into v_due;
    if not v_due then
      raise exception 'FAIL 0020: جرعة فايتة اتحجزت — الهدوء المفروض للمواعيد بس';
    end if;

    -- ٦) والسكّة شغّالة وبترجّع true النهارده
    if not private.follower_subscription_active(v_son) then
      raise exception 'FAIL 0020: سكّة الاشتراك بترجّع false والدفع لسه ما اتبناش';
    end if;

    raise notice '0020 OK — الابن يقرا صفّه، الأب الاسم والصلة بس، والجرعة الفايتة بتعدّي';
    raise exception 'rollback_0020';
  exception
    when others then
      execute 'reset role';
      if sqlerrm <> 'rollback_0020' then raise; end if;
  end;
end $$;
