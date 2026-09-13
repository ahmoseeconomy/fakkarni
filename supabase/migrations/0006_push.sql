-- 0006_push.sql — جولة ٤.٢ب، الجزء التاني: جدولا الدفع + استعلام الاختيار.
--
-- الجزء الأول خلّى السحابة تعرف الجرعة **قبل** معادها. الملف ده بيجاوب
-- السؤال اللي بعده: مين الصف اللي يستاهل ينبّه ابنه، ومين اللي اتنبّه
-- عليه خلاص.
--
-- تلات قرارات بتحكم الملف كله:
--
--   ١) **الاختيار له تعريف واحد.** لو الـEdge Function حملت الاستعلام
--      في TypeScript والاختبار حمل نسخة مكتوبة بالإيد في SQL، الاختبار
--      بيثبت جملة الدالة عمرها ما بتشغّلها — وده بالظبط العمى اللي
--      عدّى بيه `rls_test.sql` على باج ٠٠٠٥. فالاستعلام عايش هنا مرة
--      واحدة في `private.due_escalations`، والكرون والاختبار بينادوا
--      نفس الدالة ومش قادرين يختلفوا.
--
--   ٢) **مفيش سياسة كتابة على `escalations` لأي إنسان.** الكتابة
--      لـservice_role بس (الدالة السحابية). الغياب هنا رفضٌ افتراضي،
--      زي `care_relationships` في ٠٠٠٢ — مش سهو.
--
--   ٣) **توكن الجهاز مِلك صاحبه وبس.** مقدّم الرعاية المربوط بيشوف
--      جرعات الأب؛ عمره ما يشوف توكن موبايله. مفيش `can_access_patient`
--      في أي سياسة على `device_tokens` — لا قراءة ولا كتابة.
--
-- القاعدة الثابتة بعد ٠٠٠٥ متطبّقة هنا صراحة: **سياسة جدول لا تنادي
-- دالة تستعلم عن نفس الجدول.** `device_tokens` بتقارن عمود في الصف
-- نفسه (`user_id`)، و`escalations` بتمرّ من دالة بتلمس dose_events /
-- schedules / medications / patients / care_relationships — كلها جداول
-- **تانية**. فـ`INSERT ... RETURNING` على الاتنين سليم.

-- ================================================================ ١) الجداول

-- --------------------------------------------------------- device_tokens
-- التوكن نفسه هو الهوية، فهو المفتاح الأساسي: مفيش رقم نخترعه، و«نفس
-- التوكن مرتين» مستحيل بحكم البنية مش بحكم كود بيفتكر.
--
-- التفرّد العالمي على التوكن مقصود وحاسم: التوكن بيخص **جهاز**، والجهاز
-- ممكن يغيّر صاحبه. في تطبيقنا ده مش نادر — تسجيل الخروج محلي، وتسجيل
-- دخول تاني بيعمل مستخدم مجهول جديد على نفس النسخة وبنفس توكن FCM. لو
-- سمحنا بصفّين، الصف القديم يفضل يوصّل تنبيهات لابن **خارج** من حسابه.
create table if not exists public.device_tokens (
  token      text primary key check (char_length(token) between 1 and 4096),
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- RLS فوراً، في السطر اللي بعد الجدول على طول. لو السكربت وقع في أي
-- خطوة بعدها، الجدول يكون محمي أصلاً — مش مكشوف لحد ما حد يرجع يشغّله.
alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, public;

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);

drop trigger if exists set_updated_at on public.device_tokens;
create trigger set_updated_at before update on public.device_tokens
  for each row execute procedure moddatetime (updated_at);

-- ----------------------------------------------------------- escalations
-- سجلّ تدقيق: «الابن ده اتنبّه على الجرعة دي، الدرجة دي، في الوقت ده».
--
-- الـuuid هنا **بـdefault من السيرفر** — وده مش نقض لقاعدة ٠٠٠١. القاعدة
-- هناك بتحكم جداول بتعكس صفوف اتولدت على جهاز الأب: هوية الصف مولودة
-- معاه والسيرفر ما يخترعهاش. صف التصعيد ده مالوش أصل محلي أبداً — هو
-- بيتولد في السحابة وقت الفحص، فالسيرفر هو صاحبه الطبيعي.
--
-- `unique (dose_event_uuid, caregiver_id, rung)` هو **آلية عدم التكرار
-- كلها**: الفحص بيدخل الصف الأول عشان يحجز التنبيه، وكرونان بيتسابقوا
-- واحد فيهم بس بينجح. مفيش عدّاد ولا علم ولا ذاكرة في الدالة السحابية.
--
-- `rung` = 'caregiver' الجولة دي. درجة «الدائرة كلها» (+٩٠) هتيجي
-- بترحيل بيوسّع الـcheck — عشان محدش يبص على صف قديم ويخمّن كان يقصد
-- إيه. `channel` عمود تدقيق عام قيمته 'push'؛ المكالمات الصوتية
-- **ملغية من المنتج** (دين تقني في CLAUDE.md)، والعمود ده مش مكانها
-- المحجوز.
create table if not exists public.escalations (
  uuid            uuid primary key default gen_random_uuid(),
  dose_event_uuid uuid not null references public.dose_events (uuid) on delete cascade,
  caregiver_id    uuid not null references auth.users (id) on delete cascade,
  rung            text not null default 'caregiver' check (rung in ('caregiver')),
  channel         text not null default 'push'      check (channel in ('push')),
  -- 'claimed' = الصف اتحجز والإرسال لسه؛ الباقي نتيجة FCM كما رجعت.
  delivery_status text not null default 'claimed'
                    check (delivery_status in ('claimed', 'sent', 'no_token', 'failed')),
  fcm_status      integer,   -- كود HTTP من FCM، بدون تفسير
  fcm_response    text,      -- جسم الرد كما هو — ده مصدر الحقيقة وقت العطل
  created_at      timestamptz not null default now(),
  sent_at         timestamptz,
  unique (dose_event_uuid, caregiver_id, rung)
);

alter table public.escalations enable row level security;
revoke all on public.escalations from anon, public;

create index if not exists escalations_caregiver_idx
  on public.escalations (caregiver_id, created_at desc);

-- ------------------------------------------------- فهرس الفحص على dose_events
-- الفحص بيدور على (state = 'pending' AND scheduled_at في نافذة) كل خمس
-- دقايق، للأبد. من غير الفهرس ده ده مسح كامل بيكبر مع كل يوم بيعدّي.
create index if not exists dose_events_scan_idx
  on public.dose_events (state, scheduled_at);

-- ========================================================= ٢) ثابت المهلة

-- مهلة السيرفر — **مرآة** `serverGraceWindow` في
-- lib/domain/escalation/escalation_ladder.dart (٦٠ دقيقة).
--
-- Postgres ما يقدرش يقرا دارت، فالرقم مكتوب مرتين بالضرورة. النسختين
-- بتفرقوا في صمت، والفرق بيظهر كإنذار كاذب على موبايل الابن — مش كبناء
-- فاشل. عشان كده `test/data/sync/server_grace_sql_test.dart` بيقرا الملف
-- ده ويقارن الرقمين، وبيقع لو أي ناحية اتحركت لوحدها.
--
-- الدالة دي هي **المكان الوحيد** للرقم في الـSQL كله، و`due_escalations`
-- مجبرة تعدّي عليها — فمفيش نسخة تانية تفلت من الاختبار.
--
-- ليه ٦٠ مش ٤٥ زي الجهاز: الفرق (`syncSlack` = ١٥) ميزانية للسلك.
-- الأب بيأكّد عند +٤٤، الدفعة عندها debounce ٣ ثواني، والكرون بيدق عند
-- +٤٥ — الصف لسه pending في السحابة والابن بيتقلق على حبة اتاخدت من نص
-- دقيقة. دي آخر دقيقة في كل مهلة، مش حالة نادرة.
create or replace function private.server_grace_window()
returns interval
language sql immutable
set search_path = ''
as $$ select interval '60 minutes' $$;

-- ================================================== ٣) دوال الوصول الخاصة

-- من مريض حدث الجرعة — صعود كامل: event → schedule → medication → patient.
-- بتلمس جداول **تانية** بس، فنداءها من سياسة `escalations` مش تكرار.
create or replace function private.patient_of_dose_event(e_uuid uuid)
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select m.patient_uuid
  from public.dose_events ev
  join public.dose_schedules s on s.uuid = ev.dose_schedule_uuid
  join public.medications    m on m.uuid = s.medication_uuid
  where ev.uuid = e_uuid;
$$;

revoke execute on function private.patient_of_dose_event(uuid) from anon, public;
grant  execute on function private.patient_of_dose_event(uuid) to authenticated;

-- ------------------------------------------------------- استعلام الاختيار
-- الجرعات اللي تستاهل تنبيه لابنه دلوقتي. **التعريف الوحيد** — الكرون
-- بينادي الدالة السحابية، والدالة السحابية بتنادي دي، والاختبار بينادي
-- دي. مفيش نسخة تانية في أي لغة.
--
-- الشروط، وكل واحد ليه سبب:
--   * `state = 'pending'` — «اتاخدت» أو «اتنست» قرار اتكتب خلاص. تأكيد
--     الأب بيمسح التنبيه بحكم الشرط ده وحده (القاعدة الخامسة).
--   * `scheduled_at <= now() - server_grace_window()` — الستين دقيقة.
--   * `scheduled_at > now() - interval '2 days'` — **الفحص محدود**.
--     تغطية السحابة يومين بالتصميم (كل فتحة بترفع النهاردة وبكرة)، فصف
--     أقدم من كده مالوش حقيقة حالية وراه. من غير الحد ده الفحص بيكبر مع
--     عمر البيانات ويصعّد على جرعات من شهر فات أول ما التطبيق يرجع يفتح.
--   * علاقة رعاية `accepted` — مريض من غير ابن مربوط مفيش حد يتنبّه.
--   * `m.stopped_at is null` — دوا إنسان وقّفه بإيده. تنبيه الابن على
--     جرعة من دوا متوقّف إنذار كاذب بحكم التعريف.
--   * `not exists` في `escalations` — اتنبّه خلاص. ده اللي بيخلي التشغيل
--     التاني فاضي، والـunique اللي فوق بيمسك السباق بين كرونين.
--
-- SECURITY DEFINER عشان الدالة تقرا الجداول الخام؛ التنفيذ لـservice_role
-- بس — مفيش مستخدم عادي بيقدر يستعرض جرعات الناس من هنا.
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
  where ev.state = 'pending'
    and ev.scheduled_at <= now() - private.server_grace_window()
    and ev.scheduled_at >  now() - interval '2 days'
    and m.stopped_at is null
    and not exists (
      select 1
      from public.escalations e
      where e.dose_event_uuid = ev.uuid
        and e.caregiver_id    = cr.caregiver_id
        and e.rung            = 'caregiver'
    )
  order by ev.scheduled_at
  limit p_limit;
$$;

revoke execute on function private.due_escalations(integer) from anon, public, authenticated;
grant  execute on function private.due_escalations(integer) to service_role;

-- ============================================ ٤) تسجيل التوكن — بوابة واحدة
-- ليه دالة مش كتابة مباشرة؟ لأن التوكن ممكن يكون مسجّل باسم مستخدم تاني
-- على نفس الجهاز (خروج محلي ← مستخدم مجهول جديد ← نفس توكن FCM). ساعتها
-- upsert عادي تحت RLS بيقع بـ42501 على صف مش بتاعك، والبديل — سياسة
-- UPDATE واسعة — بتدي أي مستخدم حق يعدّل صف غيره. الدالة بتعمل الحاجتين
-- ذرّياً من غير ما نفتح الباب ده.
--
-- إثبات الملكية هو حيازة التوكن نفسه — نفس نموذج ثقة FCM بالظبط، ومفيش
-- إثبات تاني موجود أصلاً.
--
-- **نموذج التهديد، مكتوب صريح:** حد حصل على توكن FCM بتاع نسخة تانية
-- يقدر يطالب بيه هنا. النتيجة مش تسريب للمهاجم — التنبيه بيروح للجهاز
-- الضحية مش ليه — لكنها أسوأ من إزعاج: موبايل الضحية بيبقى بيستقبل
-- تنبيهات عن **مريض غريب**، وفيها اسم المريض واسم الدوا. بيانات طبية
-- على جهاز مالهوش حق فيها. والضحية في نفس الوقت بيقف يستقبل تنبيهاته هو
-- (صفّه اتاخد) — يعني تسريب ومنع خدمة في نفس الحركة.
--
-- مقبول دلوقتي: التوكن ما بيخرجش من الجهاز ولا من السيرفر بتاعنا، فحيازته
-- بتتطلب اختراق واحد منهم أصلاً.
--
-- **وده مؤقت بحكم سببه.** الدالة دي موجودة لسبب واحد: تسجيل الخروج محلي
-- والدخول بعده بيولّد **مستخدم مجهول جديد على نفس الجهاز**، فالتوكن
-- بيتصادم مع صف مستخدم مات. مع دخول Google/Apple الحقيقي هوية المستخدم
-- بتبقى ثابتة عبر الخروج والدخول، والتصادم ده بيختفي من أصله — ساعتها
-- الدالة دي تتشال ويرجع upsert عادي تحت RLS.
--
-- مربوطة بالبند ٢ في «دين تقني» (CLAUDE.md): «المصادقة المجهولة بديل
-- تطوير فقط». تتراجع لما الدين ده يتدفع — مش تفضل للأبد لأن محدش فاكر.
create or replace function public.claim_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_token is null or char_length(p_token) = 0 then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'invalid_platform' using errcode = '22023';
  end if;

  insert into public.device_tokens (token, user_id, platform)
  values (p_token, (select auth.uid()), p_platform)
  on conflict (token) do update
    set user_id  = excluded.user_id,
        platform = excluded.platform;
end;
$$;

revoke execute on function public.claim_device_token(text, text) from anon, public;
grant  execute on function public.claim_device_token(text, text) to authenticated;

-- ========================================== ٥) الصلاحيات والسياسات
-- (RLS نفسه اتفعّل فوق، مع كل جدول في سطره.)

-- صلاحيات صريحة بدل الاعتماد على الافتراضيات: الابن يقرا سجلّ التنبيه،
-- ما يكتبهوش. الكتابة كلها لـservice_role.
grant select, insert, update, delete on public.device_tokens to authenticated;
grant select                        on public.escalations   to authenticated;
grant all    on public.device_tokens, public.escalations    to service_role;

-- --------------------------------------------------------- device_tokens
-- عمود في الصف نفسه، مفيش نداء دالة خالص — القاعدة بعد ٠٠٠٥ متطبّقة
-- بأبسط شكل ممكن. ومفيش `can_access_patient` هنا عن قصد: الابن المربوط
-- بيشوف جرعات الأب، عمره ما يشوف توكن موبايله ولا العكس.
drop policy if exists device_tokens_select on public.device_tokens;
create policy device_tokens_select on public.device_tokens
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists device_tokens_insert on public.device_tokens;
create policy device_tokens_insert on public.device_tokens
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists device_tokens_update on public.device_tokens;
create policy device_tokens_update on public.device_tokens
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists device_tokens_delete on public.device_tokens;
create policy device_tokens_delete on public.device_tokens
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- ----------------------------------------------------------- escalations
-- قراءة بس، عبر نفس نقطة التحقق اللي في كل الجداول التانية. الابن المربوط
-- يشوف تنبيهاته، والأب يشوف اللي اتبعت عنه — الشفافية هنا في صالحه.
-- علاقة اتلغت = الوصول بيقف، عشان الشرط بيمرّ من can_access_patient مش من
-- caregiver_id على طول.
drop policy if exists escalations_select on public.escalations;
create policy escalations_select on public.escalations
  for select to authenticated
  using (private.can_access_patient(private.patient_of_dose_event(dose_event_uuid)));

-- مفيش INSERT / UPDATE / DELETE لأي إنسان. الدالة السحابية بتكتب بدور
-- service_role اللي بيعدّي فوق RLS. الغياب ده هو النموذج الأمني.
