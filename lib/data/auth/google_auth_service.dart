import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Google → Supabase — **شقيق نايم**: مكتوب ومتأجّل، مفيش حد بيبنيه دلوقتي
/// (الجولة دي بتستخدم [AnonymousAuthService]). لما جوجل ترجع للخطة، ده
/// بيتوصّل في supabase_init من غير أي refactor — وده كان الغرض من العقد.
///
/// الملف ده وأشقاؤه هما بس اللي يعرفوا حزم الـSDK —
/// أي حد برّه lib/data/auth/ بيتعامل مع [AuthService] وخلاص.
///
/// google_sign_in v7 (مقروءة من المصدر المثبّت، مش من الذاكرة):
/// `initialize()` مرة واحدة، وبعدها `authenticate()` بترجع حساب أو بترمي
/// [GoogleSignInException] بكود واضح — مفيش null-يعني-إلغاء زي زمان.
class GoogleAuthService implements AuthService {
  GoogleAuthService(
    this._supabase, {
    this.serverClientId,
    this.iosClientId,
  });

  final SupabaseClient _supabase;

  /// Web client ID بتاع مشروع Google Cloud — هو نفسه الـaudience اللي
  /// Supabase بتتحقق منه.
  final String? serverClientId;

  final String? iosClientId;

  Future<void>? _googleReady;

  Future<void> _ensureGoogleReady() => _googleReady ??= GoogleSignIn.instance
      .initialize(clientId: iosClientId, serverClientId: serverClientId);

  @override
  Stream<FakkarniUser?> get authState =>
      // gotrue بيبعت INITIAL_SESSION لأي مشترك جديد — يعني البث بيبدأ
      // بالحالة الحالية لوحده، والجلسة المنتهية بتوصل هنا null بهدوء.
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
    );
  }

  @override
  Future<void> signInToLink() async {
    final GoogleSignInAccount account;
    try {
      await _ensureGoogleReady();
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      throw SignInException(_mapGoogleCode(e), e);
    } on SocketException catch (e) {
      throw SignInException(SignInFailure.offline, e);
    } catch (e) {
      throw SignInException(SignInFailure.other, e);
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const SignInException(SignInFailure.other, 'idToken == null');
    }

    try {
      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } on AuthRetryableFetchException catch (e) {
      throw SignInException(SignInFailure.offline, e);
    } on SocketException catch (e) {
      throw SignInException(SignInFailure.offline, e);
    } catch (e) {
      throw SignInException(SignInFailure.other, e);
    }
  }

  static SignInFailure _mapGoogleCode(GoogleSignInException e) =>
      switch (e.code) {
        GoogleSignInExceptionCode.canceled => SignInFailure.aborted,
        // «الواجهة المطلوبة مش متاحة» — عملياً: مفيش حساب/خدمات جوجل هنا.
        GoogleSignInExceptionCode.uiUnavailable => SignInFailure.noGoogleAccount,
        _ => SignInFailure.other,
      };

  @override
  Future<void> signOut() async {
    // محلي بس عن قصد: الخروج لازم يشتغل من غير نت. إبطال التوكن على
    // السيرفر بييجي مع جولة الجلسات الجاية.
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Auth: google signOut: $e');
    }
    try {
      await _supabase.auth.signOut(scope: SignOutScope.local);
    } catch (e) {
      debugPrint('Auth: supabase signOut: $e');
    }
  }
}
