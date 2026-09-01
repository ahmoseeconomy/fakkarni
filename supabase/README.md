# Supabase — المخطط السحابي وأمن مستوى الصف

مفتاح النشر داخل التطبيق نفسه، يعني علني. **RLS هو الجدار الوحيد** أمام
بيانات المرضى — الملفات هنا تُشغَّل بالترتيب وبدون استثناء.

## الترتيب — في محرر SQL بمشروع Supabase

1. `migrations/0001_schema.sql` — الجداول (المرآة السحابية لمخطط drift؛
   المفتاح الأساسي uuid مولود على الجهاز، والأرقام المحلية لا تغادر الجهاز).
2. `migrations/0002_rls.sql` — تفعيل RLS على كل جدول + دوال الوصول في
   المخطط `private` + السياسات. **لا يوجد وضع بينهما**: 0001 بدون 0002
   يعني جداول مكشوفة.
3. `migrations/0003_invites.sql` — جدول أكواد الدعوة ودالّتا
   `create_invite` / `redeem_invite` — **البوابة الوحيدة** لإنشاء علاقة
   رعاية. لا سياسات INSERT/UPDATE على الجدول؛ كل شيء داخل الدالتين
   (SECURITY DEFINER — المستبدِل تحت RLS لا يرى الكود ولا يُدخل العلاقة
   ولا يحرق الكود، والدالة تفعل الثلاثة ذرّياً).
4. `migrations/0004_sync.sql` — عمود updated_at بتريجر moddatetime على كل
   جدول: طابع السيرفر هو مرجع «آخر ظهور».
5. `tests/rls_test.sql` — يطبع `ALL RLS TESTS PASSED` ثم يُرجِع كل شيء
   (ROLLBACK). قابل للإعادة في أي وقت، وبعد أي تعديل سياسات: شغّله.

## تحقّق إلزامي بعد أي تغيير مخطط

الاستعلام التالي يجب أن يُرجع **صفر صفوف** — أي صف يظهر هو جدول بدون RLS،
أي تسريب:

```sql
select tablename from pg_tables
where schemaname = 'public' and rowsecurity = false;
```

وفي Table Editor يجب أن تظهر كل الجداول بعلامة «RLS enabled».

## قرارات مثبتة (تفصيلها في 0002 وCLAUDE.md)

- كل فحوص الوصول تمرّ عبر `private.can_access_patient` — دالة SECURITY
  DEFINER واحدة تكسر حلقة patients ↔ care_relationships التي كانت سترمي
  «infinite recursion detected in policy».
- `(select auth.uid())` دائماً، ليس `auth.uid()` — مرة لكل استعلام.
- مقدّم الرعاية قراءة فقط هذه الجولة؛ `care_relationships` بلا سياسة
  INSERT عمداً (تدفّق الدعوة جولة 3.3) — الغياب رفضٌ افتراضي.
- دور `anon` مسحوبة منه الامتيازات نفسها، فوق كون السياسات
  `TO authenticated`.
