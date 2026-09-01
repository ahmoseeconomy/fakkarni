-- 0003_invites.sql — البوابة الضيقة الوحيدة في جدار 3.2b.
--
-- care_relationships بلا سياسة INSERT عمداً: المفتاح المنشور علني، وأي
-- سياسة إدخال كانت تسمح لمهاجم عرف patient_uuid واحد أن يُدخل لنفسه
-- علاقة accepted ويقرأ ملفاً طبياً كاملاً. الطريق الوحيد للداخل هو
-- redeem_invite: دالة SECURITY DEFINER لأن المُستبدِل تحت RLS لا يستطيع
-- أياً من الثلاثة — قراءة صف الكود (سرّ لمالكه)، إدخال العلاقة، حرق
-- الكود — والدالة تفعلها الثلاثة في معاملة واحدة: لا حالة نصف-استبدال.

create table public.invite_codes (
  code         text primary key check (code ~ '^[0-9]{6}$'),
  patient_uuid uuid not null references public.patients (uuid) on delete cascade,
  created_by   uuid not null references auth.users (id) on delete cascade,
  expires_at   timestamptz not null,
  used_by      uuid references auth.users (id),
  used_at      timestamptz,
  created_at   timestamptz not null default now()
);

alter table public.invite_codes enable row level security;
revoke all on public.invite_codes from anon, public;

-- المالك يرى أكواده هو فقط. لا INSERT ولا UPDATE لأحد — الدالتان فقط.
create policy invite_codes_select on public.invite_codes
  for select to authenticated
  using (created_by = (select auth.uid()));

-- ---------------------------------------------------------- create_invite
create or replace function public.create_invite(p_patient_uuid uuid)
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

  -- كود واحد حي لكل مريض: القديم غير المستخدم يموت الآن
  update public.invite_codes
     set expires_at = now()
   where patient_uuid = p_patient_uuid
     and created_by = (select auth.uid())
     and used_at is null
     and expires_at > now();

  -- تنظيف: الأكواد الميتة من أكثر من يوم لا تحجز أرقاماً
  delete from public.invite_codes
   where expires_at < now() - interval '1 day' and used_at is null;

  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    begin
      insert into public.invite_codes (code, patient_uuid, created_by, expires_at)
      values (v_code, p_patient_uuid, (select auth.uid()),
              now() + interval '15 minutes');
      exit;
    exception when unique_violation then
      -- تصادم مع كود قائم — جرّب رقماً آخر
    end;
  end loop;

  return v_code;
end;
$$;

-- ---------------------------------------------------------- redeem_invite
-- الرسائل رموز ثابتة يترجمها التطبيق للعربية — لا نص SDK يصل للشاشة:
--   invalid_code   → «الكود مش مضبوط أو خلّص وقته»
--   own_code       → لا يمكن أن تكون مقدّم رعاية لنفسك
--   already_linked → مربوطان بالفعل
create or replace function public.redeem_invite(p_code text)
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

  -- كود جديد من الأب = موافقة جديدة: علاقة revoked سابقة ترجع accepted
  insert into public.care_relationships (patient_uuid, caregiver_id, status)
  values (v_invite.patient_uuid, v_uid, 'accepted')
  on conflict (patient_uuid, caregiver_id)
    do update set status = 'accepted';

  update public.invite_codes
     set used_by = v_uid, used_at = now()
   where code = p_code;

  return v_invite.patient_uuid;
end;
$$;

revoke execute on function public.create_invite(uuid), public.redeem_invite(text)
  from anon, public;
grant execute on function public.create_invite(uuid), public.redeem_invite(text)
  to authenticated;
