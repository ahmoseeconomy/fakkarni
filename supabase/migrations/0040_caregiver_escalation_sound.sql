-- 0040 — صوت تصعيد المتابع/الممرض.
--
-- الإشعار نفسه يفضل مستحقاً دائماً؛ العمود ده بيقرر نغمة الإرسال فقط.
-- default true مهم للحسابات والصفوف القديمة: ما ينفعش تحديث يسكّت آخر
-- درجة في السلّم من غير ما صاحب الموبايل يختار كده بنفسه.

alter table public.caregiver_preferences
  add column if not exists escalation_sound boolean not null default true;

-- تحقق قابل للإعادة: العمود defaultه مفتوح. `ADD COLUMN ... DEFAULT true`
-- يملأ الصفوف الموجودة من غير إنشاء صف تفضيلات جديد لأي متابع.
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'caregiver_preferences'
      and column_name = 'escalation_sound'
      and is_nullable = 'NO'
      and column_default is not null
  ) then
    raise exception 'FAIL 0040: caregiver_preferences.escalation_sound ناقص أو بلا default';
  end if;

  raise notice '0040 OK';
end $$;
