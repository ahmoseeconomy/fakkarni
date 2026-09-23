# لوحة أدمن فكرني

تطبيق **ويب، قراية بس**، لصاحب المنتج وحده. بيجاوب على سؤال واحد: «المنتج
شغّال ولا لأ» — نبضة كل موبايل، البطارية، مدى التذكير، الجرعات اللي ما
اتأكدتش، والتنبيهات اللي اتبعتت.

**مفيش أي بيانات طبية هنا**: ولا اسم دوا، ولا سجل، ولا نتيجة تحليل، ولا
قياس، ولا بيانات طوارئ، ولا رقم تليفون. قايمة الأعمدة مقفولة في
`supabase/migrations/0021_admin.sql` نفسه، مش في الشاشة.

## التشغيل

```bash
cd admin
flutter run -d chrome \
  --dart-define=SUPABASE_URL=… \
  --dart-define=SUPABASE_ANON_KEY=…
# أو
flutter run -d chrome --dart-define-from-file=../secrets.json
```

من غير المفاتيح اللوحة بتفتح وبتقول اللي ناقص بالنص — ما بتحاولش تتصل.

## الحاجز

الحساب لازم يكون إيميله في `private.admins` **والجلسة مش مجهولة** —
`private.is_admin()` في السيرفر، مش في الشاشة. اللوحة عميل عادي بمفتاح
النشر؛ **مفيش مفتاح خدمة هنا خالص** و`test/no_privileged_key_test.dart`
بيوقع لو دخل، حتى في تعليق.

## حزمة مستقلة

ما بتستوردش `package:fakkarni/` أبداً (`test/no_mobile_import_test.dart`).
اللي محتاجينه من التطبيق **متنسخ** وفوق كل نسخة سطر بيقول مصدرها:

| النسخة | الأصل |
|---|---|
| `lib/theme/tokens.dart` | `lib/core/theme/tokens.dart` |
| `lib/format/arabic_time.dart` | `lib/core/format/arabic_time.dart` |
| `lib/model/follower_profile.dart` | `lib/domain/care/follower_profile.dart` |
| `lib/format/relative_time.dart` | مستخرَج من `lib/features/care/caregiver_words.dart` |
| `assets/fonts/` | `assets/fonts/` |

تعديل في الأصل بيتنقل هنا **بالإيد**. واللوحة برّه كل حرّاس التطبيق
(اللي بيمشوا على `lib/` بتاعته) — حرّاسها هي في `admin/test/`.

## الاختبارات

```bash
cd admin && flutter test
```
