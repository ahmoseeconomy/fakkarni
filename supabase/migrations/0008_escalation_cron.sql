-- 0008_escalation_cron.sql — اللي بيخلّي كل اللي فات يشتغل من غير ما حد
-- يفتح حاجة.
--
-- لحد دلوقتي التصعيد كان بيحصل لما **إحنا** نندهه. الأب اللي بيتنسي
-- جرعته مش هيفتح التطبيق، وابنه مش هيفتح المتصفح. الملف ده بيخلي
-- السيرفر يسأل لوحده كل خمس دقايق.
--
-- ---------------------------------------------------- خطوة يدوية واحدة قبله
--
-- المفتاح **ما بيتكتبش في الملف ده ولا في أي ملف**. حطّه في Vault مرة
-- واحدة، بإيدك، في محرر SQL:
--
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1/escalate',
--     'escalate_function_url',
--     'نقطة نهاية دالة التصعيد');
--
--   select vault.create_secret(
--     '<SERVICE_ROLE_KEY>',
--     'escalate_service_role_key',
--     'مفتاح الخدمة اللي الكرون بينده بيه دالة التصعيد');
--
-- (الشقّ ده هو الوحيد اللي ما ينفعش يتلصق في شات ولا يتكوميت. لو اتكرر
-- النداء باسم موجود، Vault بيرفض — امسح القديم بـ`vault.update_secret`
-- أو غيّر الاسم.)
--
-- الرابط مش سرّ، بس محطوط في Vault مع المفتاح عشان الملف ده يفضل شغّال
-- على أي مشروع من غير تعديل — مفيش project-ref متحوّط في الكود.
--
-- ------------------------------------------------------- ليه الشكل ده بالذات
--
-- المفتاح بيتقرا **وقت التشغيل، جوّه الدالة** — مش وقت الجدولة. لو
-- حطّيناه في نص الأمر المجدول، كان هيتخزّن كما هو في `cron.job.command`،
-- وأي حد يقرا الجدول يقراه. الجدول هنا بيقول `select
-- private.run_escalation_scan()` وخلاص.
--
-- pg_net **مش بيستنى الرد**: بيسجّل الطلب وعامل خلفي بينفّذه، فوظيفة
-- الكرون بتخلص في أجزاء من الثانية ومش بتقفل على اتصال. الرد بيتحطّ في
-- `net._http_response` — وده أول مكان تبص فيه لو التنبيه ما وصلش.
--
-- وتشغيلتين متداخلتين مش مشكلة: الحجز في `escalations` بالـunique هو
-- اللي بيمنع التكرار، مش توقيت الكرون.

-- ==================================================== ١) الامتدادات
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ============================================ ٢) الأمر اللي بيتنفّذ كل ٥ دقايق
--
-- SECURITY DEFINER عشان يقرا Vault بامتيازات المالك مهما كان الدور اللي
-- جدول الوظيفة. مفيش وسيطات، فمفيش حاجة تتحقن فيه.
create or replace function private.run_escalation_scan()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_key text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'escalate_function_url';
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = 'escalate_service_role_key';

  -- بنقع بصوت عالي، كل خمس دقايق، في `cron.job_run_details`. الضجّة دي
  -- صح: معناها إن آخر درجة في السلّم مقفولة، وده لازم يبان مش يتبلع.
  if v_url is null or v_key is null then
    raise exception
      'التصعيد مش مظبوط: escalate_function_url أو escalate_service_role_key '
      'مش موجودين في Vault — شوف تعليمات 0008_escalation_cron.sql';
  end if;

  perform net.http_post(
    url := v_url,
    -- جسم فاضي = وضع المسح. الاختيار كله جوّه `due_escalations`.
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    -- الدالة بتبعت لكل هدف بالدور، فالمهلة مساحة لدفعة كاملة مش لنداء
    -- واحد. العامل الخلفي هو اللي بيستنى، مش وظيفة الكرون.
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function private.run_escalation_scan() from anon, authenticated, public;

-- ================================================== ٣) الجدولة — كل ٥ دقايق
-- إلغاء قبل الجدولة عشان الملف يتعاد تشغيله بأمان زي باقي السلسلة.
select cron.unschedule('fakkarni-escalate')
where exists (select 1 from cron.job where jobname = 'fakkarni-escalate');

select cron.schedule(
  'fakkarni-escalate',
  '*/5 * * * *',
  $job$select private.run_escalation_scan()$job$
);

-- ==================================================== ٤) تحقّق بعد التشغيل
--
--   -- الوظيفة موجودة ومفعّلة؟
--   select jobid, jobname, schedule, active from cron.job
--    where jobname = 'fakkarni-escalate';
--
--   -- آخر تشغيلات: المفروض succeeded. فشل هنا = Vault أو الامتدادات.
--   select status, return_message, start_time from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'fakkarni-escalate')
--    order by start_time desc limit 5;
--
--   -- رد الدالة السحابية نفسها — ده اللي بيقول no_token / sent.
--   select id, status_code, content, created from net._http_response
--    order by created desc limit 5;
--
--   -- ومين اتنبّه فعلاً:
--   select e.created_at, e.delivery_status, e.fcm_status, e.caregiver_id
--     from public.escalations e order by e.created_at desc limit 10;
--
-- إيقاف مؤقّت من غير حذف:
--   update cron.job set active = false where jobname = 'fakkarni-escalate';
