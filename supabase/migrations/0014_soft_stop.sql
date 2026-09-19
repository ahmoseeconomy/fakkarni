-- 0014 — الإيقاف الناعم: دوا اتشال، وجرعة اتوقفت. **ومفيش مسح.**
--
-- الجهاز بقى (نسخة ١٦) بيكتب `medications.removed_at` و
-- `dose_schedules.stopped_at` بدل ما يمسح صف. السبب مش ذوق:
--
--   * المزامنة بترفع بس — مفيش مسح خالص (الدين ١). صف اتمسح على الموبايل
--     بيفضل في السحابة للأبد.
--   * و`dose_events` بتتمسح محلياً بالـcascade. يعني المسح الحقيقي بيشيل
--     الدليل من ناحية، والسحابة تفضل شايلة نفس الأحداث `pending` من
--     الناحية التانية — والساعة +٦٠ الابن بيتقاله إن أبوه نسي جرعة الأب
--     شالها بنفسه، وموبايل الأب مش قادر يصحّح الصف لأنه مسحه.
--
-- فالملف ده بيعمل حاجتين:
--   ١. العمودين في السحابة عشان الرفع يلاقي مكانهم.
--   ٢. `private.due_escalations` ما تختارش حدث دواه متشال أو جرعته موقوفة.
--
-- الجهاز كمان بيعلّم الأحداث الجاية `superseded` وقت الإيقاف، والاختيار
-- أصلاً ما بياخدش `superseded` (٠٠١١). الشرطين هنا هما **الحزام التاني**:
-- موبايل قديم، أو صف اتعلّم قبل ما المزامنة توصل، أو حدث اتكتب بعد
-- الإيقاف من صحوة خلفية — كلهم بيتمسكوا هنا.
--
-- idempotent زي كل الملفات: `if not exists` و`create or replace`.

alter table public.medications    add column if not exists removed_at timestamptz;
alter table public.dose_schedules add column if not exists stopped_at timestamptz;

-- فهارس جزئية: الأغلبية الساحقة null، فبتفضل صغيرة للأبد.
create index if not exists medications_removed_idx
  on public.medications (patient_uuid) where removed_at is not null;
create index if not exists dose_schedules_stopped_idx
  on public.dose_schedules (medication_uuid) where stopped_at is not null;

-- ------------------------------------------------- الاختيار: نفس ٠٠١١ + شرطين
--
-- **التعريف الوحيد لـ«مين يستاهل تنبيه»** (القاعدة من ٠٠٠٦): الكرون والدالة
-- والاختبار كلهم بينادوا الدالة دي. أي شرط بيقرر استحقاق عايش هنا أو مش موجود.
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
  -- 0011: «ما اتأخدتش» ليها اسمين. pending = لسه محدش علّمه؛ missed = الجهاز
  -- علّمه بعد مهلته (+٤٥). نفس الواقعة، والفرق مين كتب الصف.
  where ev.state in ('pending', 'missed')
    and ev.scheduled_at <= now() - private.server_grace_window()
    and ev.scheduled_at >  now() - interval '2 days'
    and m.stopped_at is null
    -- 0014: دوا الأب شاله، أو جرعة وقّفها — مفيش تنبيه على حاجة مابقتش موجودة
    and m.removed_at is null
    and s.stopped_at is null
    and not exists (
      select 1
      from public.escalations e
      where e.dose_event_uuid = ev.uuid
        and e.caregiver_id    = cr.caregiver_id
        and e.rung            = 'caregiver'
        and (
          -- قرار اتكتب — مش بنلمسه تاني مهما طال الزمن
          e.delivery_status <> 'claimed'
          -- أو حجز لسه شغّال، سيبه لصاحبه
          or e.created_at > now() - private.escalation_retry_after()
        )
    )
  order by ev.scheduled_at
  limit p_limit;
$$;

-- `create or replace` بيحافظ على الصلاحيات؛ بنأكّدها برضه عشان الملف
-- يبقى صحيح لوحده.
revoke execute on function private.due_escalations(integer) from anon, public, authenticated;
grant  execute on function private.due_escalations(integer) to service_role;

-- ================================================================ تأكيد
-- بيانات مؤقتة جوّه sub-transaction، وفي الآخر استثناء مقصود عشان كله يترجع.
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_son   uuid := gen_random_uuid();
  v_pat   uuid := gen_random_uuid();
  v_med   uuid;
  v_sched uuid;
  v_event uuid;
  v_due   boolean;
  r       record;
begin
  -- العمودين موجودين وnullable
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'medications'
                   and column_name = 'removed_at' and is_nullable = 'YES') then
    raise exception 'FAIL 0014: medications.removed_at مش موجود أو مش nullable';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'dose_schedules'
                   and column_name = 'stopped_at' and is_nullable = 'YES') then
    raise exception 'FAIL 0014: dose_schedules.stopped_at مش موجود أو مش nullable';
  end if;

  begin
    insert into auth.users (id, email) values
      (v_owner, 'owner-' || v_owner || '@0014.check'),
      (v_son,   'son-'   || v_son   || '@0014.check');
    insert into public.patients (uuid, owner_id, name) values (v_pat, v_owner, '0014');
    insert into public.care_relationships (patient_uuid, caregiver_id, status)
      values (v_pat, v_son, 'accepted');

    -- أربع حالات: شغّال (مستحق)، متشال، جرعته موقوفة، وموقوف كله (٠٠١١)
    for r in
      select * from (values
        ('live',    true),
        ('removed', false),
        ('stopped_schedule', false),
        ('stopped_med', false)
      ) as t(kind, should_be_due)
    loop
      v_med   := gen_random_uuid();
      v_sched := gen_random_uuid();
      v_event := gen_random_uuid();

      insert into public.medications (uuid, patient_uuid, name, removed_at, stopped_at)
        values (
          v_med, v_pat, 'Concor ' || r.kind,
          case when r.kind = 'removed'     then now() else null end,
          case when r.kind = 'stopped_med' then now() else null end
        );
      insert into public.dose_schedules
        (uuid, medication_uuid, timing_kind, anchor, offset_minutes, repeat, start_date, stopped_at)
        values (
          v_sched, v_med, 'anchor', 'breakfast', -30, 'daily', current_date - 7,
          case when r.kind = 'stopped_schedule' then now() else null end
        );
      insert into public.dose_events
        (uuid, dose_schedule_uuid, routine_day, scheduled_at, state)
        values (v_event, v_sched, current_date, now() - interval '61 minutes', 'pending');

      v_due := exists (select 1 from private.due_escalations(100000) d
                       where d.dose_event_uuid = v_event);
      if v_due <> r.should_be_due then
        raise exception 'FAIL 0014: % — مستحق=% والمفروض %', r.kind, v_due, r.should_be_due;
      end if;
    end loop;

    -- والحدث القديم بتاع دوا متشال بيفضل مكانه — تاريخ، مش مسح
    if not exists (select 1 from public.dose_events ev
                   join public.dose_schedules s on s.uuid = ev.dose_schedule_uuid
                   join public.medications m on m.uuid = s.medication_uuid
                   where m.patient_uuid = v_pat and m.removed_at is not null) then
      raise exception 'FAIL 0014: حدث دوا متشال اتمسح — المفروض يفضل تاريخ';
    end if;

    raise exception '0014_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> '0014_ROLLBACK' then
      raise;
    end if;
  end;

  raise notice '0014 OK — المتشال والموقوف مش بيصعّدوا، وتاريخهم مكانه';
end $$;
