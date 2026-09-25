// روابط سياسة الخصوصية والشروط — **المكان الوحيد** اللي فيه الرابطين.
//
// الافتراضي علامة مكان (`[PRIVACY_URL]`) لحد ما الصفحات تتنشر. قبل أي
// رفع للمتجر بيتمرّروا من غير تعديل كود:
//   --dart-define=PRIVACY_URL=https://… --dart-define=TERMS_URL=https://…
// المسودّات في docs/legal/ — ومحتاجة مراجعة قانونية قبل النشر.

const privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: '[PRIVACY_URL]');
const termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: '[TERMS_URL]');

/// رابط حقيقي ولا لسه علامة مكان — الزرار ما بيفتحش علامة مكان.
bool legalUrlReady(String url) => url.startsWith('https://');
