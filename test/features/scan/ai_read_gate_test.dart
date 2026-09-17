import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/auth/auth_service.dart';
import 'package:fakkarni/features/link/sign_in_screen.dart';
import 'package:fakkarni/features/scan/ai_read_gate.dart';

import 'scan_test_support.dart';

/// C2 — قراية الصور محتاجة جلسة. من غيرها الشاشة **ما بتفشلش في صمت**:
/// سطر صريح وزرار لباب الدخول الموجود، والإدخال بالإيد دايماً موجود.
class _Auth implements AuthService {
  FakkarniUser? user;
  int signInCalls = 0;
  final _changes = StreamController<FakkarniUser?>.broadcast();

  void becomes(FakkarniUser? next) {
    user = next;
    _changes.add(next);
  }

  @override
  Stream<FakkarniUser?> get authState => _changes.stream;
  @override
  FakkarniUser? get currentUser => user;
  @override
  Future<void> signInToLink() async => signInCalls++;
  @override
  Future<void> signOut() async => becomes(null);
}

const _someone = FakkarniUser(id: 'u1', isAnonymous: true);
const _line = 'سجّل دخول عشان نقرا الروشتة';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  var byHand = 0;
  var closed = 0;
  setUp(() {
    byHand = 0;
    closed = 0;
  });

  Widget gate({required bool hasReader, AuthService? auth, bool needsSignIn = false}) => Scaffold(
        backgroundColor: F.inkDeep,
        body: AiReadGate(
          hasReader: hasReader,
          auth: auth,
          needsSignIn: needsSignIn,
          signInLine: _line,
          byHandLabel: 'أكتبها بإيدي',
          onByHand: () => byHand++,
          onSignInClosed: () => closed++,
          child: const Text('الكاميرا'),
        ),
      );

  screenTest('السحابة مش متظبطة → سطر صريح، الإدخال بالإيد شغّال، ومفيش كاميرا ولا زرار دخول', (tester) async {
    await h.pump(tester, gate(hasReader: false, auth: _Auth()));

    expect(find.text(AiReadGate.notConfiguredLine), findsOneWidget);
    expect(find.text('الكاميرا'), findsNothing);
    expect(find.text('سجّل دخول'), findsNothing);

    await tester.tap(find.text('أكتبها بإيدي'));
    expect(byHand, 1);
  });

  screenTest('مفيش جلسة → السطر وزرار «سجّل دخول» ٦٤، والكاميرا مقفولة — وبعد الدخول بتفتح لوحدها', (tester) async {
    final auth = _Auth();
    await h.pump(tester, gate(hasReader: true, auth: auth));

    expect(find.text(_line), findsOneWidget);
    expect(find.text('الكاميرا'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('ai-sign-in'))).height, F.primaryButtonHeight);
    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'أكتبها بإيدي')).height,
        greaterThanOrEqualTo(F.minTapTarget));
    expect(auth.signInCalls, 0, reason: 'الباب ما بيسجّلش دخول بنفسه — الشاشة الموجودة هي اللي بتعمل كده');

    auth.becomes(_someone);
    await settle(tester);

    expect(find.text('الكاميرا'), findsOneWidget);
    expect(find.text(_line), findsNothing);
  });

  screenTest('فيه جلسة بس السحابة ردّت ٤٠١ → مقفول برضه', (tester) async {
    final auth = _Auth()..user = _someone;
    await h.pump(tester, gate(hasReader: true, auth: auth, needsSignIn: true));

    expect(find.text(_line), findsOneWidget);
    expect(find.text('الكاميرا'), findsNothing);
  });

  screenTest('فيه جلسة → الكاميرا على طول', (tester) async {
    final auth = _Auth()..user = _someone;
    await h.pump(tester, gate(hasReader: true, auth: auth));

    expect(find.text('الكاميرا'), findsOneWidget);
    expect(find.text('سجّل دخول'), findsNothing);
  });

  screenTest('«سجّل دخول» بيفتح شاشة الدخول الموجودة — ومن غير ولا نداء دخول من الباب نفسه', (tester) async {
    final auth = _Auth();
    await h.pump(tester, gate(hasReader: true, auth: auth));

    await tester.tap(find.text('سجّل دخول'));
    await settle(tester);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(auth.signInCalls, 0);

    Navigator.of(tester.element(find.byType(SignInScreen))).pop();
    await settle(tester);
    expect(closed, 1, reason: 'الشاشة بتصفّر حالة الفشل لما يرجع');
  });
}
