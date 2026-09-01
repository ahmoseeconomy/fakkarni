import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// دخول مجهول — **بديل تطويري مؤقت** (شوف «دين تقني» في CLAUDE.md).
///
/// المستخدم المجهول مربوط بالجهاز ده وبيضيع مع مسح بيانات التطبيق.
/// قبل أي رفع للمتجر لازم يتترقّى بـlinkIdentity لجوجل — النزول بيه ممنوع.
/// Google وApple هييجوا كملفات شقيقة بنفس [AuthService].
class AnonymousAuthService implements AuthService {
  AnonymousAuthService(this._supabase);

  final SupabaseClient _supabase;

  @override
  Stream<FakkarniUser?> get authState =>
      // gotrue بيبعت INITIAL_SESSION لأي مشترك جديد، والجلسة المنتهية
      // بتوصل هنا null بهدوء — مفيش crash ومفيش stack trace.
      _supabase.auth.onAuthStateChange.map((state) => _toUser(state.session));

  @override
  FakkarniUser? get currentUser => _toUser(_supabase.auth.currentSession);

  static FakkarniUser? _toUser(Session? session) {
    final user = session?.user;
    if (user == null) return null;
    return FakkarniUser(
      id: user.id,
      email: user.email,
      displayName: user.userMetadata?['full_name'] as String?,
      // gotrue بيقراها من claim الـis_anonymous في الـJWT
      isAnonymous: user.isAnonymous,
    );
  }

  @override
  Future<void> signInToLink() async {
    try {
      await _supabase.auth.signInAnonymously();
    } on AuthRetryableFetchException catch (e) {
      throw SignInException(SignInFailure.offline, e);
    } on SocketException catch (e) {
      throw SignInException(SignInFailure.offline, e);
    } catch (e, stack) {
      // السبب الحقيقي لازم يبان في الترمنال — الرسالة العربية للمستخدم
      // بتخفيه، وده اللي ضيّع علينا وقت في 404 بتاع Gemini.
      debugPrint('Auth: signInAnonymously فشلت: $e\n$stack');
      throw SignInException(SignInFailure.other, e);
    }
  }

  @override
  Future<void> signOut() async {
    // محلي بس عن قصد: الخروج لازم يشتغل من غير نت.
    try {
      await _supabase.auth.signOut(scope: SignOutScope.local);
    } catch (e) {
      debugPrint('Auth: supabase signOut: $e');
    }
  }
}
