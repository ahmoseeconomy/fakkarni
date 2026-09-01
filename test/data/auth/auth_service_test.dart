import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/auth/auth_service.dart';

/// خدمة وهمية بنفس العقد — الاختبارات عمرها ما بتلمس Google ولا Supabase.
class FakeAuthService implements AuthService {
  final _controller = StreamController<FakkarniUser?>.broadcast();
  FakkarniUser? _current;

  /// اللي المحاولة الجاية هترميه — null يعني نجاح.
  SignInException? nextFailure;
  FakkarniUser signedInUser =
      const FakkarniUser(id: 'u1', email: 'a@b.c', isAnonymous: true);

  /// حارس «مش بوابة»: عدد مرات النداء — لازم يفضل صفر لحد ما الزرار يتداس.
  int signInCalls = 0;

  @override
  Stream<FakkarniUser?> get authState async* {
    yield _current; // INITIAL_SESSION — زي gotrue بالظبط
    yield* _controller.stream;
  }

  @override
  FakkarniUser? get currentUser => _current;

  @override
  Future<void> signInToLink() async {
    signInCalls++;
    final failure = nextFailure;
    if (failure != null) throw failure;
    _current = signedInUser;
    _controller.add(_current);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  /// الجلسة انتهت من نفسها — السيرفر رفض التجديد.
  void expireSession() {
    _current = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}

void main() {
  late FakeAuthService auth;

  setUp(() => auth = FakeAuthService());
  tearDown(() => auth.dispose());

  test('البث بيبدأ بالحالة الحالية — مفيش جلسة = null', () async {
    expect(await auth.authState.first, isNull);
    expect(auth.currentUser, isNull);
  });

  test('دخول ناجح → المستخدم في البث وفي currentUser', () async {
    final states = <FakkarniUser?>[];
    final sub = auth.authState.listen(states.add);
    // البث async* — لازم القيمة الأولى تنزل قبل ما نغيّر الحالة
    await pumpEventQueue();

    await auth.signInToLink();
    await pumpEventQueue();

    expect(states, [null, const FakkarniUser(id: 'u1', email: 'a@b.c', isAnonymous: true)]);
    expect(auth.currentUser?.id, 'u1');
    expect(auth.currentUser?.isAnonymous, isTrue, reason: 'من claim الـJWT');
    await sub.cancel();
  });

  test('الإلغاء بإيده: استثناء صامت — مفيش رسالة، والحالة زي ما هي', () async {
    auth.nextFailure = const SignInException(SignInFailure.aborted);

    await expectLater(
      auth.signInToLink(),
      throwsA(
        isA<SignInException>()
            .having((e) => e.reason, 'reason', SignInFailure.aborted)
            .having((e) => e.message, 'message', isNull),
      ),
    );
    expect(auth.currentUser, isNull);
  });

  test('أوفلاين: الرسالة المتفق عليها بالحرف', () async {
    auth.nextFailure = const SignInException(SignInFailure.offline);

    await expectLater(
      auth.signInToLink(),
      throwsA(
        isA<SignInException>().having(
          (e) => e.message,
          'message',
          'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.',
        ),
      ),
    );
  });

  test('كل سبب ليه جملته العربية — ومفيش إنجليزي فيها', () {
    expect(const SignInException(SignInFailure.noGoogleAccount).message,
        'مفيش حساب جوجل على الجهاز ده.');
    expect(const SignInException(SignInFailure.other).message,
        'مقدرناش نكمّل التسجيل. جرّب تاني.');
    for (final reason in SignInFailure.values) {
      final message = SignInException(reason).message;
      if (message == null) continue;
      expect(RegExp('[a-zA-Z]').hasMatch(message), isFalse,
          reason: 'رسالة SDK خام ماينفعش توصل للشاشة: $message');
    }
  });

  test('الخروج بيمسح الحالة وبيبعت null', () async {
    await auth.signInToLink();
    final states = <FakkarniUser?>[];
    final sub = auth.authState.listen(states.add);

    await auth.signOut();
    await pumpEventQueue();

    expect(auth.currentUser, isNull);
    expect(states.last, isNull);
    await sub.cancel();
  });

  test('جلسة منتهية (refresh token مرفوض) → خروج هادي، مش crash', () async {
    await auth.signInToLink();
    final states = <FakkarniUser?>[];
    final sub = auth.authState.listen(states.add);

    auth.expireSession();
    await pumpEventQueue();

    expect(auth.currentUser, isNull);
    expect(states.last, isNull, reason: 'بترجع signed-out بهدوء');
    await sub.cancel();
  });
}
