-- 0013 — سجل قرايات الذكاء (C2): الحد اليومي، ومين بيستهلك.
--
-- مفتاح Gemini خرج من التطبيق وبقى سر عند دالة `ai-read`. الدالة دي هي
-- الكاتب **الوحيد** للجدول ده (بمفتاح الخدمة)، وهي بتسأله قبل كل قراية:
-- المستخدم ده قرا كام مرة النهارده؟ والتطبيق كله قرا كام؟
--
-- * **مفيش أي وصول للعميل.** RLS مفعّل ومفيش ولا policy، وكل الصلاحيات
--   متشالة من anon / authenticated / public. المستخدم ما يقدرش يقرا عدّاده
--   ولا يمسحه ولا يكتب فيه — لو قدر، الحد مالوش معنى.
-- * **«النهارده» يعني يوم القاهرة**، ومتعرّف هنا مرة واحدة. الدالة بتقول
--   للمستخدم «جرّب بكرة»، وبكرة عند مريض في مصر بيبدأ نص ليل القاهرة مش
--   UTC. مصر بتغيّر التوقيت الصيفي، و`at time zone` بيعرف ده.
-- * **القراية الفاشلة بتتسجّل (ok = false) وما بتتحسبش.** عطل عندنا أو عند
--   جوجل مش ذنب المريض، فما ياكلش من حدّه — بس لازم نشوفه.
-- * الحدّين نفسهم (٢٠ للمستخدم، وسقف للتطبيق كله) ثوابت فوق في
--   `functions/ai-read/index.ts`. هنا العدّ بس.
--
-- idempotent: ينفع يتشغّل تاني من غير ما يكسر حاجة. `0014` محجوز لجولة
-- الفهرس والتنظيف.

create table if not exists public.ai_reads (
  id          bigint generated always as identity primary key,
  user_id     uuid        not null references auth.users (id) on delete cascade,
  kind        text        not null check (kind in ('prescription', 'lab')),
  created_at  timestamptz not null default now(),
  bytes       integer     not null check (bytes >= 0),
  model       text,
  ok          boolean     not null,
  duration_ms integer     check (duration_ms is null or duration_ms >= 0)
);

alter table public.ai_reads enable row level security;

revoke all on public.ai_reads from anon, authenticated, public;
grant select, insert on public.ai_reads to service_role;

-- العدّ اليومي بيمشي على (المستخدم، الوقت) وعلى الوقت لوحده — والاتنين على
-- الناجح بس، فالفهرسين جزئيين وبيفضلوا صغيرين.
create index if not exists ai_reads_user_day_idx
  on public.ai_reads (user_id, created_at) where ok;
create index if not exists ai_reads_day_idx
  on public.ai_reads (created_at) where ok;

-- بداية يوم القاهرة الحالي، كلحظة.
create or replace function private.cairo_day_start()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select date_trunc('day', now() at time zone 'Africa/Cairo') at time zone 'Africa/Cairo'
$$;

-- العدّادين في نداء واحد: قرايات المستخدم الناجحة النهارده، وقرايات الكل.
-- `private` مش معروض لـPostgREST (زي ٠٠٠٧)، فده الغلاف الضيق في `public`،
-- ومتاح لـservice_role وبس.
create or replace function public.ai_reads_today_for_service(p_user uuid)
returns table (user_reads integer, all_reads integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*)::integer from public.ai_reads
      where ok and user_id = p_user and created_at >= private.cairo_day_start()),
    (select count(*)::integer from public.ai_reads
      where ok and created_at >= private.cairo_day_start())
$$;

revoke all on function public.ai_reads_today_for_service(uuid) from public, anon, authenticated;
grant execute on function public.ai_reads_today_for_service(uuid) to service_role;
revoke all on function private.cairo_day_start() from public, anon, authenticated;

-- ------------------------------------------------------------ فحص ذاتي
-- كله بيتلف في الآخر (ROLLBACK بالاستثناء) — مفيش صف بيفضل.
do $$
declare
  v_user  uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_before integer;
  v_user_reads integer;
  v_all_reads integer;
  v_denied boolean;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.ai_reads'::regclass) then
    raise exception 'FAIL 0013: RLS مش مفعّل على ai_reads';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ai_reads') then
    raise exception 'FAIL 0013: ai_reads عليه policy — المفروض مفيش أي وصول للعميل';
  end if;
  if has_table_privilege('anon', 'public.ai_reads', 'select')
     or has_table_privilege('authenticated', 'public.ai_reads', 'select')
     or has_table_privilege('authenticated', 'public.ai_reads', 'insert')
     or has_table_privilege('authenticated', 'public.ai_reads', 'delete') then
    raise exception 'FAIL 0013: العميل عنده صلاحية على ai_reads';
  end if;
  if has_function_privilege('authenticated', 'public.ai_reads_today_for_service(uuid)', 'execute')
     or has_function_privilege('anon', 'public.ai_reads_today_for_service(uuid)', 'execute') then
    raise exception 'FAIL 0013: العميل يقدر ينادي عدّاد الخدمة';
  end if;
  if not has_function_privilege('service_role', 'public.ai_reads_today_for_service(uuid)', 'execute')
     or not has_table_privilege('service_role', 'public.ai_reads', 'insert') then
    raise exception 'FAIL 0013: service_role مش قادر يكتب أو يعدّ';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_user,  'reader-' || v_user  || '@0013.check'),
      (v_other, 'other-'  || v_other || '@0013.check');

    select all_reads into v_before from public.ai_reads_today_for_service(v_user);

    insert into public.ai_reads (user_id, kind, created_at, bytes, model, ok, duration_ms) values
      (v_user,  'prescription', now(), 1000, 'm', true,  10),
      (v_user,  'lab',          now(), 1000, 'm', true,  10),
      -- فاشلة: بتتسجّل وما بتتحسبش
      (v_user,  'lab',          now(), 1000, 'm', false, 10),
      -- امبارح بتوقيت القاهرة: قبل بداية اليوم بدقيقة
      (v_user,  'prescription', private.cairo_day_start() - interval '1 minute', 1000, 'm', true, 10),
      -- مستخدم تاني: بيدخل في عدّاد الكل بس
      (v_other, 'prescription', now(), 1000, 'm', true,  10);

    select user_reads, all_reads into v_user_reads, v_all_reads
      from public.ai_reads_today_for_service(v_user);
    if v_user_reads <> 2 then
      raise exception 'FAIL 0013: عدّاد المستخدم % والمفروض ٢ (الفاشلة وامبارح ما يتحسبوش)', v_user_reads;
    end if;
    if v_all_reads <> v_before + 3 then
      raise exception 'FAIL 0013: عدّاد الكل زاد % والمفروض ٣', v_all_reads - v_before;
    end if;

    -- المستخدم نفسه ما يقدرش يشوف عدّاده ولا يمسحه
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    v_denied := false;
    begin
      perform 1 from public.ai_reads limit 1;
    exception when insufficient_privilege then
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0013: مستخدم مسجّل قدر يقرا ai_reads';
    end if;
    v_denied := false;
    begin
      delete from public.ai_reads where user_id = v_user;
    exception when insufficient_privilege then
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'FAIL 0013: مستخدم مسجّل قدر يمسح عدّاده';
    end if;
    reset role;

    raise exception '0013_ROLLBACK';
  exception when raise_exception then
    reset role;
    if sqlerrm <> '0013_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0013 OK — ai_reads مقفول على العميل، والعدّ بيوم القاهرة، والفاشلة ما بتتحسبش';
end $$;
