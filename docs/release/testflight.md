# نسخة TestFlight — على سجل التطبيق القديم في App Store Connect

**الهوية**: `com.fakrny.app` (هدف `Runner`؛ `RunnerTests` = `com.fakrny.app.RunnerTests`،
ومفيش أي extension). **النسخة**: `2.0.0+1` في `pubspec.yaml` — أكبر من `1.12.1` آخر
نسخة للتطبيق القديم على المتجر. الفريق في المشروع: `Z27KMZ3GD3`.

> **ملحوظتين قبل أي رفع** (من «دين تقني» في `CLAUDE.md`):
> - **الدين ٢**: الدخول المجهول (`AnonymousAuthService`) هو الدخول الوحيد الشغّال.
>   النزول به على المتجر ممنوع بنص القاعدة — TestFlight داخلي قرار المالك.
> - **الدين 2b**: مفتاح Gemini جوّه الـIPA (`--dart-define`). أي حد يفك الملف
>   بياخده. نفس القاعدة: مش للمتجر.

## ١. قبل البناء — مرة واحدة

1. Xcode → Runner target → Signing & Capabilities: الفريق `Z27KMZ3GD3`، Automatically
   manage signing، الـBundle ID لازم يقرا `com.fakrny.app`.
2. في بوابة Apple Developer، على App ID `com.fakrny.app`: capability
   **Time Sensitive Notifications** مفعّلة (الـentitlement على Release بس) —
   وإلا التذكير بيوصل كإشعار عادي في صمت. **Push Notifications مش مطلوبة
   في النسخة دي** (مفيش APNs لسه — الدين ٣؛ `Runner.entitlements` ما فيهاش
   `aps-environment` عن قصد، ولو اتضافت من غير الـcapability التوقيع بيقع).
3. Supabase → Authentication → Providers → **Allow new users to sign up = ON**
   (الدخول المجهول بيعدّي على `/signup`؛ لو اتقفلت «اربط ابني» بيقع عند الكل).
4. `secrets.json` موجود محلي ومش متتبَّع (`git status --short | grep secrets` فاضي).

## ٢. البناء

```bash
flutter clean && flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release \
  --build-name=2.0.0 --build-number=1 \
  --dart-define=APP_VERSION=2.0.0 \
  --dart-define=SUPABASE_URL=… \
  --dart-define=SUPABASE_ANON_KEY=… \
  --dart-define=GEMINI_API_KEY=… \
  --dart-define=PRIVACY_URL=… \
  --dart-define=TERMS_URL=…
```

أو بملف واحد (نفس الأسامي): `--dart-define-from-file=secrets.json`.

**التعريفات كلها** (الأسامي بس — القيم عمرها ما تتكتب هنا):

| الاسم | لازم؟ | من غيره |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | للربط والمزامنة | التطبيق كامل محلياً؛ شاشة الربط بتقول اللي ناقص |
| `GEMINI_API_KEY` | لقراية الروشتة/العلبة/التحليل و«كلّمني» بالسحابة | شاشات التصوير بتقول «مش متظبطة»؛ «كلّمني» محلي بس |
| `APP_VERSION` | لنبضة السلامة ولسطر النسخة في الإعدادات | `dev` |
| `PRIVACY_URL`, `TERMS_URL` | روابط السياسات | العلامة ما بتتفتحش |
| `GEMINI_MODEL`, `GEMINI_FALLBACK_MODEL`, `GEMINI_THINKING_BUDGET` | لأ | الافتراضي في `GeminiConfig` |
| `GOOGLE_SERVER_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` | لأ (جوجل مش شغّالة — الدين ٢) | — |

الناتج: `build/ios/ipa/fakkarni.ipa` وأرشيف في `build/ios/archive/Runner.xcarchive`.

## ٣. الرفع — من Xcode، مش من هنا

1. `open build/ios/archive/Runner.xcarchive` → Xcode Organizer.
2. **Distribute App** → **App Store Connect** → Upload → Automatically manage
   signing → Upload.
3. App Store Connect → التطبيق القديم (`com.fakrny.app`) → TestFlight → البناء
   `2.0.0 (1)` يظهر بعد المعالجة → Export Compliance: التطبيق بيستخدم HTTPS
   بس (مفيش تشفير خاص) → ضيف المختبرين.

## ٤. اللي بيتغيّر في نسخة release — وإزاي تشوف التشخيص

- **قسم «للمطوّر» مخفي** (`developerVisible` = `!kReleaseMode`) — **والباب**:
  الإعدادات → آخر سطر «فكرني ٢٫٠٫٠» → **٧ دوسات ورا بعض** → «باب المطوّر
  اتفتح» وبيظهر «سجل التشخيص» و«اطمن إن التذكير هيشتغل». من لحظتها `diag`
  بيكتب في `Documents/fkdiag.log` (ملف بس، من غير طباعة على الكونسول)، ومعاه
  سطور سويفت اللي بتتكتب دايماً. ٧ دوسات تاني بتقفله. الاختيار محفوظ.
- **`voiceCommandsCloud` مقفول**: «كلّمني» بيفهم محلي بس؛ اللي مش مفهوم
  «معلش، مافهمتش» — مفيش «ثانية واحدة» ولا سحابة.
- **الدخول المجهول شغّال زي debug بالظبط** — مفيش فرق في الكود بين الوضعين:
  الربط والمزامنة ومسح الحساب بيشتغلوا، بس المستخدم مربوط بالتنزيلة (مسح
  بيانات التطبيق = مستخدم جديد).
- **Time Sensitive** بيشتغل في Release بس، ولو الـcapability مش على الـApp ID
  بيوصل كإشعار عادي من غير أي خطأ.
- التشخيصات اللي على الشاشة (`kDebugMode`: لوحة Gemini الخام، `modelWarning`،
  شرايح محاكاة الاشتراك، `TestHook`) مش موجودة.
- `debugPrint` مش بتتقفل لوحدها في release — عشان كده كل سطر تشخيص بيعدّي من
  `diag`، وهو اللي بيقرر.
