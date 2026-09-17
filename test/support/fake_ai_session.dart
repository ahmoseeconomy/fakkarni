import 'package:fakkarni/ai/ai_session.dart';

/// جلسة مزيّفة للقارئ (C2). `token: null` = مفيش جلسة.
///
/// العنوان مش مشروع حقيقي، والاختبارات بتعدّي من `MockClient` — **الحزمة
/// عمرها ما بتنادي الدالة الحقيقية**.
class FakeAiSession implements AiSession {
  FakeAiSession({this.token = 'user-access-token'});

  String? token;
  int tokenRequests = 0;

  @override
  final Uri endpoint = Uri.parse('https://proj.supabase.test/functions/v1/ai-read');

  @override
  final String publishableKey = 'sb_publishable_test';

  @override
  Future<String?> accessToken() async {
    tokenRequests++;
    return token;
  }
}
