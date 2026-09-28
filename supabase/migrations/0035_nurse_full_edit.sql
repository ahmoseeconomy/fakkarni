-- ============================================================================
-- 0035 — الممرض بيعدّل كل حاجة، وبيتنبّه زي الابن (ملف بس — ما اتطبّقش)
-- ============================================================================
-- أربع حاجات في ملف واحد، كلها للممرض اللي بقى تطبيقه نسخة من تطبيق المريض:
--
-- ١) أنواع تغيير جديدة على `medication_changes` (0024/0031): الساعات،
--    الشيل، الرجوع، القياس، المخزون بالرقم، و«صيدليتي». وحالة 'reverted':
--    المريض داس «تراجع» في ٢٤ ساعة، فالصف بيقول كده والممرض بيشوفه في
--    «التعديلات».
-- ٢) «صيدليتي» على صف المريض في السحابة (اسم / رقم اتصال / واتساب) —
--    موبايل المريض بيدفعها، والممرض بيقراها ويطلب منها. **رقم صيدلية مش
--    رقم شخص**: قرار D5.1 «السحابة ما بتشيلش ولا رقم تليفون» كان عن جهات
--    اتصال الطوارئ، ومحفوظ زي ما هو.
-- ٣) مفتاحين للممرض على `caregiver_preferences` (0020): «نبهني بمواعيد
--    الدوا» (موبايله بيقراه) و«نبهني لو مافيش تأكيد» (السيرفر بيقراه).
-- ٤) درجة 'nurse' في `escalations`: +٣٠ دقيقة من غير تأكيد → إشعار للممرض،
--    **قبل** الابن (+٦٠). نفس الوظيفة، نفس الدالة، نفس الحجز الذرّي —
--    بس بدرجة تانية ونافذة تانية. **`due_escalations` بتاعة الابن ما
--    اتلمستش.**
--
-- الترتيب: بعد 0034. idempotent. **لازم يتشغّل قبل نسخة بالكود ده تلمس
-- موبايل ممرض**: من غيره الأنواع الجديدة بتترفض (قيد) وبتفضل في طابور
-- الممرض («هيوصل لموبايله أول ما يفتح النت»)، والدرجة 'nurse' ما بتتبعتش.

-- ---------------------------------------------------------------- ١) الأنواع

alter table public.medication_changes drop constraint if exists medication_changes_kind_check;
alter table public.medication_changes
  add constraint medication_changes_kind_check
  check (kind in (
    'add', 'stop', 'amount', 'record', 'appointment', 'restock', 'photo', 'bought',
    'timings',    -- ساعات الدوا وأيامه: الجديد بيتكتب الأول والقديم بيتوقف، على موبايل المريض
    'remove',     -- «شيله خالص» — شيل ناعم، عمره ما مسح فعلي
    'resume',     -- رجوع دوا موقوف
    'vital',      -- قياس (ضغط / سكر / وزن / …)
    'stock_set',  -- الكمية دلوقتي وأيام التحذير — «علبة جديدة» فاضلة تزويد (restock)
    'pharmacy'    -- «صيدليتي»: الاسم ورقم الاتصال والواتساب
  ));

alter table public.medication_changes drop constraint if exists medication_changes_outcome_check;
alter table public.medication_changes
  add constraint medication_changes_outcome_check
  check (outcome in ('applied', 'conflict', 'missing', 'reverted'));

-- «تراجع» بيتكتب بعد التطبيق: `applied_at` بيفضل زي ما هو (التطبيق حصل
-- فعلاً) و`reverted_at` بيقول إمتى اترجع. المالك بس (سياسة update من 0024).
alter table public.medication_changes add column if not exists reverted_at timestamptz;

-- ------------------------------------------------------------- ٢) صيدليتي

alter table public.patients
  add column if not exists pharmacy_name     text,
  add column if not exists pharmacy_call     text,
  add column if not exists pharmacy_whatsapp text;

-- ------------------------------------------------------- ٣) مفاتيح الممرض

alter table public.caregiver_preferences
  add column if not exists nurse_dose_reminders    boolean not null default true,
  add column if not exists nurse_unconfirmed_alert boolean not null default true;

-- ---------------------------------------------------------- ٤) درجة الممرض

alter table public.escalations drop constraint if exists escalations_rung_check;
alter table public.escalations
  add constraint escalations_rung_check check (rung in ('caregiver', 'nurse'));

-- **٣٠ دقيقة** — مرآة `nurseGraceWindow` في `lib/domain/escalation/`.
-- `test/data/sync/nurse_grace_sql_test.dart` بيوقع لو واحد اتحرّك لوحده.
create or replace function private.nurse_grace_window()
returns interval
language sql immutable
set search_path = ''
as $$ select interval '30 minutes' $$;

revoke execute on function private.nurse_grace_window() from anon, public;
grant  execute on function private.nurse_grace_window() to authenticated, service_role;

-- الممرض عنده مفتاح «نبهني لو مافيش تأكيد» — مقفول = السيرفر ساكت له.
-- من غير صف تفضيلات = مفتوح (الافتراضي في التطبيق كمان).
create or replace function private.nurse_unconfirmed_alert_on(p_caregiver uuid, p_patient uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce(
    (select cp.nurse_unconfirmed_alert
       from public.caregiver_preferences cp
      where cp.caregiver_id = p_caregiver and cp.patient_uuid = p_patient),
    true);
$$;

revoke execute on function private.nurse_unconfirmed_alert_on(uuid, uuid) from anon, public;
grant  execute on function private.nurse_unconfirmed_alert_on(uuid, uuid) to authenticated, service_role;

-- **نفس شكل `due_escalations` بالحرف** (0025)، بتلات فروق: العلاقة ممرض،
-- النافذة ٣٠، والدرجة 'nurse'. التأكيد نيابةً بيسكّتها زي ما بيسكّت
-- الابن، والاشتراك نفس الشرط. التعريف الواحد للاختيار — الكرون والدالة
-- والاختبار بيسألوا هنا.
create or replace function private.due_nurse_escalations(p_limit integer default 200)
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
      and cr.role   = 'nurse'
  where ev.state in ('pending', 'missed')
    and ev.scheduled_at <= now() - private.nurse_grace_window()
    and ev.scheduled_at >  now() - interval '2 days'
    and m.stopped_at is null
    and m.removed_at is null
    and s.stopped_at is null
    and private.follower_subscription_active(cr.caregiver_id, p.uuid)
    and private.nurse_unconfirmed_alert_on(cr.caregiver_id, p.uuid)
    and not exists (
      select 1 from public.proxy_confirmations pc
      where pc.dose_event_uuid = ev.uuid
    )
    and not exists (
      select 1
      from public.escalations e
      where e.dose_event_uuid = ev.uuid
        and e.caregiver_id    = cr.caregiver_id
        and e.rung            = 'nurse'
        and (
          e.delivery_status <> 'claimed'
          or e.created_at > now() - private.escalation_retry_after()
        )
    )
  order by ev.scheduled_at
  limit p_limit;
$$;

revoke execute on function private.due_nurse_escalations(integer) from anon, public, authenticated;
grant  execute on function private.due_nurse_escalations(integer) to service_role;

-- الغلاف العام — نفس قاعدة 0007: `private` مش مكشوفة لـPostgREST.
create or replace function public.due_nurse_escalations_for_service(p_limit integer default 200)
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
as $$ select * from private.due_nurse_escalations(p_limit) $$;

revoke execute on function public.due_nurse_escalations_for_service(integer) from anon, public, authenticated;
grant  execute on function public.due_nurse_escalations_for_service(integer) to service_role;

-- الحجز بدرجة: نفس 0009 بالحرف + `p_rung`. التوقيع القديم بيفضل شغّال
-- (الدالة المنشورة بتنده عليه لحد ما تتحدّث) وبيمرّر 'caregiver'.
create or replace function public.claim_escalation_for_service(
  p_dose_event_uuid uuid,
  p_caregiver_id    uuid,
  p_rung            text
)
returns uuid
language sql
security definer
set search_path = ''
as $$
  insert into public.escalations (dose_event_uuid, caregiver_id, rung)
  values (p_dose_event_uuid, p_caregiver_id, p_rung)
  on conflict (dose_event_uuid, caregiver_id, rung) do update
     set created_at      = now(),
         delivery_status = 'claimed',
         sent_at         = null,
         fcm_status      = null,
         fcm_response    = null
   where public.escalations.delivery_status = 'claimed'
     and public.escalations.created_at
         <= now() - private.escalation_retry_after()
  returning uuid;
$$;

revoke execute on function public.claim_escalation_for_service(uuid, uuid, text) from anon, public, authenticated;
grant  execute on function public.claim_escalation_for_service(uuid, uuid, text) to service_role;

-- ============================================ ٥) إشارة «اتأكّدت» للناحية التانية
-- المريض أكّد على موبايله → ممرضينه يلغوا تذكيرهم حالاً؛ ممرض أكّد نيابةً →
-- موبايل المريض يسحبه (وده اللي بيلغي سلّمه) والممرضين التانيين يلغوا.
-- الإشارة رسالة دفع **صامتة** (data) عن طريق دالة الحافة `confirm-signal`،
-- بنفس مفتاح Vault بتاع 0008 + رابط جديد:
--
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1/confirm-signal',
--     'confirm_signal_function_url',
--     'نقطة نهاية إشارة التأكيد');
--
-- **التريجر عمره ما يرمي**: بيجري جوّه upsert موبايل المريض، ورمية هنا
-- كانت هتوقّع دفعة الجرعات كلها. من غير السرّ = سكوت، والمقارنة الجاية على
-- كل موبايل بتكمّل (الإشارة بتسرّع، ما بتقرّرش).

create or replace function private.send_confirm_signal(p_event uuid, p_source text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_key text;
begin
  -- عدّاد للفحص الذاتي بس: لو الجلسة عاملة جدول مؤقت بالاسم ده، بنسجّل فيه
  -- النداء قبل أي حاجة (السرّ مش موجود في الفحص، والطلب نفسه مش بيتبعت)
  if to_regclass('pg_temp.confirm_signal_calls') is not null then
    insert into pg_temp.confirm_signal_calls (dose_event_uuid, source) values (p_event, p_source);
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'confirm_signal_function_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'escalate_service_role_key';
  if v_url is null or v_key is null then return; end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('dose_event_uuid', p_event, 'source', p_source),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    timeout_milliseconds := 15000
  );
exception when others then
  -- مجاملة: الدفعة تكمّل مهما حصل
  null;
end;
$$;

revoke execute on function private.send_confirm_signal(uuid, text) from anon, public, authenticated;

-- **الإشارة للجرعات اللي معادها في آخر ٢٤ ساعة بس.** موبايل بيعيد رفع
-- تاريخه كله (أول دفعة، أو بعد تنصيب) بيمرّر مئات الجرعات القديمة كـ`taken`
-- — ولا واحدة فيهم عندها تذكير مستني إلغاء، فمفيش داعي تفرّغ دفعات دفع.
create or replace function private.confirm_signal_window()
returns interval
language sql immutable
set search_path = ''
as $$ select interval '24 hours' $$;

revoke execute on function private.confirm_signal_window() from anon, public;

create or replace function private.on_dose_taken()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.state = 'taken'
     and (tg_op = 'INSERT' or old.state is distinct from 'taken')
     and new.scheduled_at >= now() - private.confirm_signal_window() then
    perform private.send_confirm_signal(new.uuid, 'patient');
  end if;
  return new;
end;
$$;

drop trigger if exists confirm_signal_on_taken on public.dose_events;
create trigger confirm_signal_on_taken
  after insert or update of state on public.dose_events
  for each row execute function private.on_dose_taken();

create or replace function private.on_proxy_confirmed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.dose_events e
    where e.uuid = new.dose_event_uuid
      and e.scheduled_at >= now() - private.confirm_signal_window()
  ) then
    perform private.send_confirm_signal(new.dose_event_uuid, 'proxy');
  end if;
  return new;
end;
$$;

drop trigger if exists confirm_signal_on_proxy on public.proxy_confirmations;
create trigger confirm_signal_on_proxy
  after insert on public.proxy_confirmations
  for each row execute function private.on_proxy_confirmed();

-- «مين يستلم الإشارة» — تعريف واحد للدالة: أصحاب المريض (المالك)، وكل ممرض
-- مقبول. المتابع العادي لأ (ماعندوش تذكيرات يلغيها).
create or replace function public.confirm_signal_targets_for_service(p_event uuid)
returns table (user_id uuid, patient_uuid uuid, is_owner boolean)
language sql stable security definer
set search_path = ''
as $$
  with ev as (
    select p.uuid as patient_uuid, p.owner_id
    from public.dose_events e
    join public.dose_schedules s on s.uuid = e.dose_schedule_uuid
    join public.medications m on m.uuid = s.medication_uuid
    join public.patients p on p.uuid = m.patient_uuid
    where e.uuid = p_event
  )
  select ev.owner_id, ev.patient_uuid, true from ev
  union
  select cr.caregiver_id, ev.patient_uuid, false
  from ev join public.care_relationships cr
    on cr.patient_uuid = ev.patient_uuid and cr.status = 'accepted' and cr.role = 'nurse';
$$;

revoke execute on function public.confirm_signal_targets_for_service(uuid) from anon, public, authenticated;
grant  execute on function public.confirm_signal_targets_for_service(uuid) to service_role;

-- ================================================================ فحص ذاتي
-- من الجداول وRLS تحت `set local role authenticated`، ولا نداء private.*
-- في الدور ده (درس 0026). المالك في auth.users **قبل** المريض (درس 0016).
do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_nurse    uuid := gen_random_uuid();
  v_son      uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_pat      uuid := gen_random_uuid();
  v_med      uuid := gen_random_uuid();
  v_sched    uuid := gen_random_uuid();
  v_ev       uuid := gen_random_uuid();
  v_old_ev   uuid := gen_random_uuid();
  v_change   uuid := gen_random_uuid();
  v_n        integer;
  v_denied   boolean;
  v_kind     text;
begin
  if not exists (select 1 from pg_constraint where conname = 'medication_changes_kind_check'
                 and pg_get_constraintdef(oid) like '%bought%') then
    raise exception 'FAIL 0035: شغّل 0031 الأول';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'dose_schedules' and column_name = 'meal_relation') then
    raise exception 'FAIL 0035: شغّل 0034 الأول';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner,    'owner-'    || v_owner    || '@0035.check'),
      (v_nurse,    'nurse-'    || v_nurse    || '@0035.check'),
      (v_son,      'son-'      || v_son      || '@0035.check'),
      (v_stranger, 'stranger-' || v_stranger || '@0035.check');
    insert into public.patients (uuid, owner_id, name, pharmacy_name, pharmacy_call, pharmacy_whatsapp)
      values (v_pat, v_owner, '0035', 'صيدلية الشفا', '0223456789', '01012345678');
    insert into public.care_relationships (patient_uuid, caregiver_id, status, role, can_confirm, can_edit_meds)
      values (v_pat, v_nurse, 'accepted', 'nurse',    true,  true),
             (v_pat, v_son,   'accepted', 'follower', false, false);
    insert into public.medications (uuid, patient_uuid, name) values (v_med, v_pat, 'Concor');
    insert into public.dose_schedules (uuid, medication_uuid, timing_kind) values (v_sched, v_med, 'fixed');
    -- جرعة معادها من ٤٠ دقيقة: جوّه نافذة الممرض (٣٠) وبرّه نافذة الابن (٦٠)
    insert into public.dose_events (uuid, dose_schedule_uuid, scheduled_at, state)
      values (v_ev, v_sched, now() - interval '40 minutes', 'pending');

    -- ١) كل نوع جديد بيدخل من الممرض اللي معاه «يعدّل الأدوية» — بـuuid من
    --    الموبايل (الطابور الأوفلاين بيعيد نفس الصف، والمفتاح الأساسي هو الحارس)
    perform set_config('request.jwt.claims', json_build_object('sub', v_nurse)::text, true);
    execute 'set local role authenticated';
    foreach v_kind in array array['timings', 'remove', 'resume', 'vital', 'stock_set', 'pharmacy'] loop
      insert into public.medication_changes (uuid, patient_uuid, actor_id, kind, medication_uuid, payload)
        values (case v_kind when 'timings' then v_change else gen_random_uuid() end,
                v_pat, v_nurse, v_kind, v_med, '{}'::jsonb);
    end loop;
    v_denied := false;
    begin
      insert into public.medication_changes (uuid, patient_uuid, actor_id, kind, medication_uuid)
        values (v_change, v_pat, v_nurse, 'timings', v_med);
    exception when unique_violation then v_denied := true;
    end;
    if not v_denied then raise exception 'FAIL 0035: نفس uuid اتكتب مرتين'; end if;
    -- والممرض بيقرا «صيدليتي» بتاعة المريض
    if (select pharmacy_call from public.patients where uuid = v_pat) <> '0223456789' then
      raise exception 'FAIL 0035: الممرض مش شايف صيدلية المريض';
    end if;
    execute 'reset role';

    -- ٢) المتابع لأ
    perform set_config('request.jwt.claims', json_build_object('sub', v_son)::text, true);
    execute 'set local role authenticated';
    v_denied := false;
    begin
      insert into public.medication_changes (patient_uuid, actor_id, kind, medication_uuid)
        values (v_pat, v_son, 'pharmacy', v_med);
    exception when insufficient_privilege then v_denied := true;
    end;
    execute 'reset role';
    if not v_denied then raise exception 'FAIL 0035: المتابع بعت تغيير'; end if;

    -- ٣) المالك بيعلّم «اترجع»
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
    execute 'set local role authenticated';
    update public.medication_changes
       set applied_at = now(), outcome = 'reverted', reverted_at = now()
     where uuid = v_change;
    execute 'reset role';
    if (select outcome from public.medication_changes where uuid = v_change) is distinct from 'reverted' then
      raise exception 'FAIL 0035: المالك ما قدرش يعلّم «اترجع»';
    end if;

    -- ٤) الدرجة: الممرض مستحق دلوقتي (+٤٠ ≥ ٣٠)، والابن لسه (< ٦٠)
    select count(*) into v_n from private.due_nurse_escalations() d where d.dose_event_uuid = v_ev;
    if v_n <> 1 then raise exception 'FAIL 0035: الممرض مش في due_nurse_escalations (%)', v_n; end if;
    select count(*) into v_n from private.due_escalations() d where d.dose_event_uuid = v_ev;
    if v_n <> 0 then raise exception 'FAIL 0035: الابن اتصعّد له قبل الستين'; end if;
    -- المفتاح مقفول → ساكت
    insert into public.caregiver_preferences (caregiver_id, patient_uuid, nurse_unconfirmed_alert)
      values (v_nurse, v_pat, false);
    select count(*) into v_n from private.due_nurse_escalations() d where d.dose_event_uuid = v_ev;
    if v_n <> 0 then raise exception 'FAIL 0035: «نبهني لو مافيش تأكيد» مقفول والسيرفر لسه بيختار'; end if;
    update public.caregiver_preferences set nurse_unconfirmed_alert = true
     where caregiver_id = v_nurse and patient_uuid = v_pat;
    -- الحجز بالدرجة، مرة — التانية null (حجز طازة)
    if public.claim_escalation_for_service(v_ev, v_nurse, 'nurse') is null then
      raise exception 'FAIL 0035: أول حجز للممرض رجّع null';
    end if;
    if public.claim_escalation_for_service(v_ev, v_nurse, 'nurse') is not null then
      raise exception 'FAIL 0035: حجز تاني طازة اتقبل';
    end if;
    select count(*) into v_n from private.due_nurse_escalations() d where d.dose_event_uuid = v_ev;
    if v_n <> 0 then raise exception 'FAIL 0035: المحجوز لسه بيتختار'; end if;
    -- التوقيع القديم لسه شغّال للابن
    if public.claim_escalation_for_service(v_ev, v_son) is null then
      raise exception 'FAIL 0035: التوقيع القديم وقع';
    end if;
    -- التأكيد نيابةً بيسكّت الممرض التاني كمان (نفس قاعدة الابن)
    delete from public.escalations where dose_event_uuid = v_ev;
    insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id) values (v_ev, v_pat, v_nurse);
    select count(*) into v_n from private.due_nurse_escalations() d where d.dose_event_uuid = v_ev;
    if v_n <> 0 then raise exception 'FAIL 0035: تأكيد نيابةً والممرض لسه بيتصعّد له'; end if;

    -- ٥) إشارة «اتأكّدت»: جرعة من ٣ أيام بتتعلّم taken (إعادة رفع تاريخ) →
    --    **مفيش نداء**؛ جرعة النهارده → نداء واحد؛ وتأكيد نيابةً على قديمة → لأ
    create temp table confirm_signal_calls (dose_event_uuid uuid, source text) on commit drop;
    insert into public.dose_events (uuid, dose_schedule_uuid, scheduled_at, state)
      values (v_old_ev, v_sched, now() - interval '3 days', 'taken');
    update public.dose_events set state = 'taken' where uuid = v_old_ev;
    select count(*) into v_n from pg_temp.confirm_signal_calls;
    if v_n <> 0 then raise exception 'FAIL 0035: جرعة من ٣ أيام طلّعت إشارة تأكيد (%)', v_n; end if;
    update public.dose_events set state = 'taken' where uuid = v_ev;
    select count(*) into v_n from pg_temp.confirm_signal_calls where dose_event_uuid = v_ev and source = 'patient';
    if v_n <> 1 then raise exception 'FAIL 0035: جرعة النهارده ما طلّعتش إشارة تأكيد (%)', v_n; end if;
    delete from public.proxy_confirmations where dose_event_uuid = v_ev;
    insert into public.proxy_confirmations (dose_event_uuid, patient_uuid, actor_id) values (v_old_ev, v_pat, v_nurse);
    select count(*) into v_n from pg_temp.confirm_signal_calls where source = 'proxy';
    if v_n <> 0 then raise exception 'FAIL 0035: تأكيد نيابةً على جرعة قديمة طلّع إشارة'; end if;

    -- ٦) الغريب ما بيشوفش حاجة
    perform set_config('request.jwt.claims', json_build_object('sub', v_stranger)::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.medication_changes where patient_uuid = v_pat;
    execute 'reset role';
    if v_n <> 0 then raise exception 'FAIL 0035: غريب شاف تغييرات'; end if;

    raise exception '0035_ROLLBACK';
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
    if sqlerrm <> '0035_ROLLBACK' then raise; end if;
  end;

  raise notice '0035 OK — الأنواع الستة و«اترجع» وصيدليتي ومفاتيح الممرض ودرجة +٣٠ للممرض قبل الابن، وإشارة التأكيد لآخر ٢٤ ساعة بس';
end $$;
