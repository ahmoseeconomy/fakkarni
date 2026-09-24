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
5. `migrations/0005_fix_patients_select.sql` — **إصلاح حرج، لازم يتشغّل**:
   `patients_select` كانت بتنادي `can_access_patient(uuid)` — دالة
   بتستعلم عن `public.patients` نفسه — فكل `INSERT ... RETURNING` لمريض
   جديد كان بيقع بـ42501. من غير الملف ده التطبيق ما بيقدرش يعمل مريض
   أصلاً.
6. `migrations/0006_push.sql` — جولة ٤.٢ب جزء ٢: `device_tokens` +
   `escalations`، ثابت مهلة السيرفر `private.server_grace_window()`،
   واستعلام الاختيار `private.due_escalations` — **التعريف الوحيد** الذي
   يناديه الكرون والدالة السحابية والاختبار.
7. `migrations/0007_escalate_rpc.sql` — غلاف `public` رفيع حوالين
   `private.due_escalations`، تنفيذه لـ`service_role` بس. موجود لأن
   `private` **مش مكشوفة عبر PostgREST**، فالدالة السحابية مش قادرة
   تنادي الجوّانية مباشرة. الغلاف مالوش جسم خاص بيه — التعريف فضل واحد.
8. `tests/escalation_test.sql` — يثبت الاختيار قبل وجود أي كود إرسال:
   يُطبع `ALL ESCALATION TESTS PASSED` ثم ROLLBACK. **شغّله بعد ٠٠٠٧**،
   لأن قسمه السابع بيفحص الغلاف اللي الدالة السحابية بتناديه فعلاً.
9. `migrations/0008_escalation_cron.sql` — pg_cron + pg_net كل ٥ دقايق.
   **قبله خطوة يدوية واحدة**: حطّ `escalate_function_url` و
   `escalate_service_role_key` في Vault (التعليمات في أول الملف). المفتاح
   بيتقرا وقت التشغيل جوّه الدالة، مش وقت الجدولة — عشان ما يتخزّنش في
   `cron.job.command` حيث أي حد يقراه.
10. `migrations/0009_escalation_retry.sql` — محاولة اتقطعت نصّها بترجع
    مستحقة بعد ٥ دقايق، والحجز بقى عملية واحدة ذرّية
    (`claim_escalation_for_service`). **الدالة السحابية لازم تتلصق من
    جديد بعده** — النسخة القديمة بتحجز بـ`insert` وبتعتبر التعارض
    «اتنبّه خلاص»، فالإصلاح ما بيبانش أثره من غيرها.
11. `migrations/0010_dose_superseded.sql` — حالة `superseded` («اتغيّرت
    القاعدة») على `dose_events`. **قبل** ما نسخة التطبيق v15 توصل موبايل
    مربوط — من غيره الـcheck القديم بيرفض الصف ودفعة المزامنة كلها بتفشل.
12. `migrations/0011_escalate_missed.sql` — الاختيار بياخد `missed` زي
    `pending` (الاتنين «ما اتأخدتش»). بيطبع `0011 OK` في الآخر، وبعده
    شغّل `tests/escalation_test.sql`.
13. `migrations/0012_health_file.sql` — الملف الصحي (records, readings,
    lab_results, visit_questions, emergency_profile) + RLS +
    `patient_of_record` + مسح يومي للمحذوف من ٣٠ يوم. بيطبع `0012 OK` في
    الآخر. **قبل** ما نسخة D5.1 توصل موبايل مربوط — من غيره الدفع بيقع عند
    `records` في كل مرة.
14. `migrations/0013_ai_reads.sql` — سجل قرايات الذكاء (C2): جدول `ai_reads`
    مقفول على العميل بالكامل (RLS من غير ولا policy) + عدّاد
    `ai_reads_today_for_service` بيوم القاهرة، لـ`service_role` وبس. بيطبع
    `0013 OK` في الآخر. **قبل** لصق دالة `ai-read` — من غيره الدالة بترد
    `503 cap_check_failed` على كل قراية. (`0014` محجوز للفهرس والتنظيف.)
    بعده، بالترتيب: سر `GEMINI_API_KEY` في Edge Functions → Secrets، وبعدين
    الصق `functions/ai-read/index.ts` و`verify_jwt` **مفعّل**.
15. أعمدة على جداول موجودة — مفيش فيهم سياسة جديدة ولا لمسة في
    `private.due_escalations`، وكل واحد بيطبع `OK` بعد تأكيد بيترجع:
    `migrations/0014_soft_stop.sql` (الإيقاف الناعم — بيعيد تعريف
    `due_escalations` عشان الموقوف والمتشال ما يتصعّدوش)،
    `migrations/0015_checkup_dates.sql` (مواعيد متابعة التحليل)،
    و`migrations/0016_lab_ranges.sql` (نطاق ورقة المعمل: `ref_low` /
    `ref_high` / `ref_text` على `lab_results` — نقل من الورقة، مش جدول قيم
    طبيعية؛ السطر اللي الورقة مفيهاش نطاق ليه بيفضل null).
16. `migrations/0017_visit_follow.sql` — نوع المتابعة (`follow_kind`) على
    `records`؛ الصف القديم من غير نوع لسه تحليل. بيطبع `0017 OK`.
17. `migrations/0018_device_health.sql` — نبضة فحص السلامة: صف لكل (مريض،
    تنزيلة)، **أكواد سلامة وبس** من غير أي محتوى طبي، و
    `private.broken_devices()` بتجيب المكسور **والساكت**. بيطبع `0018 OK`.
18. `migrations/0019_battery_state.sql` — عمود واحد (`battery_state`) بتلات
    قيم. بيطبع `0019 OK`.
19. `migrations/0020_caregiver_preferences.sql` — تفضيلات المتابع،
    `public.followers_of_patient` وسكّة الاشتراك، وبيعيد تعريف
    `private.due_escalations` عشان تعدّي عليها. **`moddatetime` من غير
    سكيما** — `extensions.moddatetime()` مش موجودة على المشروع الحقيقي.
    المتوقّع `Success. No rows returned` و`0020 OK` في Messages.
20. `migrations/0021_admin.sql` — لوحة الأدمن: `private.admins` (قايمة
    إيميلات)، `private.is_admin()` (إيميل في القايمة **وجلسة مش مجهولة**)،
    و`private.admin_account_rows()` + أربع دوال `public.admin_*` قراية بس
    لـ`authenticated`. **ولا دالة بترجّع اسم دوا ولا أي بيان طبي.**
    المتوقّع `Success. No rows returned` و`0021 OK` في Messages. بعده،
    بالإيد، إيميل صاحب المنتج:
    `insert into private.admins (email) values (lower('…')) on conflict do nothing;`
    وتفعيل مزوّد Email + إنشاء المستخدم **من لوحة Supabase**، مش من SQL.
21. `migrations/0022_admin_devices.sql` — `public.admin_devices()`: صف لكل
    (مريض، تنزيلة) من `device_health` بأكواد السلامة وأعمدة النبضة، قراية
    بس ومحروسة بـ`private.is_admin()` زي 0021. **ولا بيان طبي.** المتوقّع
    `Success. No rows returned` و`0022 OK` في Messages.
22. `migrations/0023_nurse_role.sql` — الدور والصلاحيات على العلاقة،
    `proxy_confirmations`، و`due_escalations` بتستبعد المؤكَّد نيابةً.
    **لسه ما اتشغّلتش.**
23. `migrations/0024_medication_changes.sql` — التغييرات المعلّقة من
    الممرض. **لسه ما اتشغّلتش.**
24. `migrations/0025_family_subscription.sql` — اشتراك العيلة: جدول
    `family_subscriptions`، تجربة ١٤ يوم (٣٠ للموجودين)، و`due_escalations`
    بتمشي على `follower_subscription_active(caregiver, patient)`، وسقف
    الدائرة ٥. **لسه ما اتشغّلتش** — بعد 0023 و0024. وبعدها الـEdge
    Function `verify-purchase` بأسرار المتجرين (HANDOVER B7).
25. `verify_migrations.sql` — **بيقرا بس** (SELECT واحد، مفيش DDL ولا
    كتابة): صف لكل ترحيل من 0001 لـ0025 بـ`expected`/`found`/`ok`/
    `missing`. شغّله **قبل** أي جولة بتلمس السحابة — `0014` عمرها ما
    اتشغّلت واكتشافها كلّف ساعة، والسكريبت ده بيجاوب نفس السؤال بلصقة
    واحدة. آخر تأكيد: ٢٢ سبتمبر ٢٠٢٦، ٢٠ صف كلهم تمام (قبل ٠٠٢١).
23. `tests/rls_test.sql` — يطبع `ALL RLS TESTS PASSED` ثم يُرجِع كل شيء
   (ROLLBACK). قابل للإعادة في أي وقت، وبعد أي تعديل سياسات: شغّله.

كل الملفات **قابلة لإعادة التشغيل** (`if not exists` / `or replace` /
`drop ... if exists`)، فتشغيل السلسلة كاملة من الأول آمن في أي وقت — وده
المفروض يحصل في نفس الجولة اللي بتكتب الـSQL، قبل ما تتكوميت.

> الجملة اللي فوق كانت **غلط** لحد جولة ٤.٢ب جزء ٢. `0001` كان بيقع من
> أول `create table`، و`0002` و`0003` من أول `create policy`، على أي
> مشروع فيه بيانات. اتصلحت كلها في نفس الجولة اللي اكتشفتها. ملف README
> بيكذب أغلى من ملف README ناقص — لو لقيت وعد هنا مش صحيح، صلّح الوعد أو
> صلّح الكود، وما تسيبهوش.

الثمن المعروف لـ`if not exists`: إعادة التشغيل **ما بتعدّلش** شكل جدول
موجود. وده المطلوب — الترحيلات تاريخ، وتغيير الشكل بياخد ملف جديد
بترقيمه، مش تعديل في ملف قديم.

## قاعدة ثابتة: سياسة جدول لا تنادي دالة تستعلم عن نفس الجدول

أعمدة الصف متاحة داخل السياسة مباشرة — استخدمها
(`owner_id = (select auth.uid())`). الدالة المعرِّفة موجودة لهدف واحد:
الوصول إلى جداول **أخرى** بدون تكرار. كسر القاعدة لا يظهر عند إنشاء
السياسة، بل عند `INSERT ... RETURNING`: Postgres يطبّق سياسة القراءة على
الصف الجديد داخل نفس الأمر، والاستعلام الفرعي لا يراه بعد. هذا بالضبط ما
حدث في `patients_select` قبل 0005.

`tests/rls_test.sql` صار يُدخل مريضاً ودواءً وحدث جرعة **بـRETURNING** —
بنفس شكل ما يكتب به التطبيق، لا بشكل أسهل على الاختبار.

## تحقّق إلزامي بعد أي تغيير مخطط

الاستعلام التالي يجب أن يُرجع **صفر صفوف** — أي صف يظهر هو جدول بدون RLS،
أي تسريب:

```sql
select tablename from pg_tables
where schemaname = 'public' and rowsecurity = false;
```

وفي Table Editor يجب أن تظهر كل الجداول بعلامة «RLS enabled».

## توكن الجهاز ملك صاحبه وحده

`device_tokens` هو الاستثناء الوحيد من نمط `can_access_patient`: مفيش نداء
ليها في أي سياسة هناك، في أي اتجاه. الابن المربوط بيشوف جرعات أبوه، وعمره
ما يشوف توكن موبايله ولا العكس. الكتابة بتمرّ من `public.claim_device_token`
— ونموذج التهديد بتاعها مكتوب صريح جوّه `0006_push.sql`، ومربوط بالبند ٢
في «دين تقني» عشان يتراجع لما المصادقة المجهولة تتشال.

بالمقابل `escalations` **بتتقرا بالدائرة كلها**: أي مقدّم رعاية مقبول
بيشوف كل تنبيه اتبعت عن المريض ده، حتى لو اتبعت لأخوه. ده مقصود لعيلة
بتشارك أب واحد. ونتيجته التانية: علاقة اتلغت = بيبطل يشوف حتى التنبيهات
اللي كان واصلها قبل كده.


## قرارات مثبتة (تفصيلها في 0002 وCLAUDE.md)

- كل فحوص الوصول تمرّ عبر `private.can_access_patient` — دالة SECURITY
  DEFINER واحدة تكسر حلقة patients ↔ care_relationships التي كانت سترمي
  «infinite recursion detected in policy».
- `(select auth.uid())` دائماً، ليس `auth.uid()` — مرة لكل استعلام.
- مقدّم الرعاية قراءة فقط هذه الجولة؛ `care_relationships` بلا سياسة
  INSERT عمداً (تدفّق الدعوة جولة 3.3) — الغياب رفضٌ افتراضي.
- دور `anon` مسحوبة منه الامتيازات نفسها، فوق كون السياسات
  `TO authenticated`.
