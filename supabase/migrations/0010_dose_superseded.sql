-- 0010_dose_superseded.sql — حالة «اتغيّرت القاعدة» لصف جرعة.
--
-- ليه: تعديل توقيت جرعة لوقت أبكر (٢:٠٠ → ٧:٠٠ الساعة ١١:١٧) بيخلّي صف
-- النهارده «قبل سريان القاعدة» (`dose_schedules.active_from` محلي، v15).
-- الصف ده ممكن يكون اتبعت للسحابة من امبارح كـ«بكرة». مسحه محلي ما
-- بيوصلش هنا (المزامنة مفيهاش مسح — دين ١)، فكان هيفضل pending والكرون
-- ينبّه الابن عن جرعة اتشالت. فالجهاز بيكتب state = 'superseded' بدل
-- المسح، وده بيتبعت زي أي حالة.
--
-- `private.due_escalations` بتختار `state = 'pending'` بس، فمفيش تغيير فيها
-- — `tests/escalation_test.sql` فيه حالة ✘ للحالة الجديدة.
--
-- **لازم يتشغّل قبل ما نسخة v15 من التطبيق توصل موبايل مربوط**: من غيره
-- الـcheck القديم بيرفض الصف، ودفعة dose_events كلها بتفشل في صمت،
-- والسحابة بتقدم لحد ما الملف ده يتشغّل.
--
-- متكرر بأمان: drop if exists قبل add.

-- اسم الـcheck اللي 0001 عمله inline اسمه الافتراضي `dose_events_state_check`،
-- بس ما بنراهنش على الاسم: أي check على العمود state بيتشال، وإلا القديم
-- يفضل يرفض 'superseded' والملف يبان إنه اشتغل.
do $$
declare c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    where ns.nspname = 'public'
      and rel.relname = 'dose_events'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%state%'
  loop
    execute format('alter table public.dose_events drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.dose_events
  add constraint dose_events_state_check
  check (state in ('pending', 'taken', 'skipped', 'missed', 'superseded'));

-- تأكيد إن الـcheck الجديد هو اللي موجود فعلاً
do $$
begin
  if not exists (
    select 1 from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    where rel.relname = 'dose_events' and con.conname = 'dose_events_state_check'
      and pg_get_constraintdef(con.oid) ilike '%superseded%'
  ) then
    raise exception 'FAIL: dose_events_state_check ما فيهوش superseded';
  end if;
  raise notice '0010 OK — dose_events بتقبل superseded';
end $$;
