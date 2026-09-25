-- ============================================================================
-- 0030 — حدود باكت `patient-papers` (ملف بس — ما اتطبّقش)
-- ============================================================================
-- 0026 عمل الباكت خاص، بس **من غير حد حجم ولا قايمة أنواع** — يعني أي حد
-- عنده صلاحية كتابة (المالك، أو الممرض تحت pending/ من 0029) يقدر يرمي
-- أي ملف بأي حجم.
--
-- اللي التطبيق بيرفعه فعلاً، من الكود نفسه:
--   * صور الورق (`SupabasePaperUploads`): بايتس الكاميرا زي ما هي —
--     `pickWithSystemCamera` بـ2560×2560 وجودة 92 — `image/jpeg`.
--     روشتة أو تحليل بالحجم ده بيطلع ~١–٤ ميجا.
--   * صور الأدوية (`SupabaseMedPhotos`): بعد `prepareMedPhoto` — أطول ضلع
--     ≤800 وجودة 82، من غير EXIF — `image/jpeg`، أقل من ميجا بكتير.
--   * الاتنين بيبعتوا `contentType: 'image/jpeg'` ثابت.
--
-- فالحد: **10 ميجا** (ضعف أسوأ ورقة تقريباً — ورقة مليانة كلام بدقة
-- كاملة ما تترفضش)، والأنواع: **`image/jpeg` بس** (القايمة بالظبط اللي
-- التطبيق بيبعتها؛ أي نوع تاني = حاجة التطبيق ما بيعملهاش).
-- idempotent: `update` على نفس القيم.

update storage.buckets
set file_size_limit    = 10485760,          -- 10 MiB
    allowed_mime_types = array['image/jpeg']
where id = 'patient-papers';

-- فحص ذاتي — **كـpostgres بس**، من غير أي إدخال في storage.objects.
do $$
declare
  v_limit bigint;
  v_types text[];
begin
  select file_size_limit, allowed_mime_types into v_limit, v_types
  from storage.buckets where id = 'patient-papers';
  if not found then
    raise exception 'FAIL 0030: الباكت patient-papers مش موجود — شغّل 0026 الأول';
  end if;
  if v_limit is distinct from 10485760 then
    raise exception 'FAIL 0030: حد الحجم % مش 10 ميجا', v_limit;
  end if;
  if v_types is distinct from array['image/jpeg'] then
    raise exception 'FAIL 0030: الأنواع % مش image/jpeg بس', v_types;
  end if;
  if exists (select 1 from storage.buckets where id = 'patient-papers' and public) then
    raise exception 'FAIL 0030: الباكت بقى عام';
  end if;
  raise notice '0030 OK — patient-papers: خاص، ١٠ ميجا، image/jpeg بس';
end $$;
