import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/auth/auth_service.dart';
import 'package:fakkarni/features/link/sign_in_screen.dart';

import '../../data/auth/auth_service_test.dart' show FakeAuthService;
import '../scan/scan_test_support.dart' show settle, screenTest, expectNoRedAndMinSize;

void main() {
  late FakeAuthService auth;

  setUp(() => auth = FakeAuthService());
  tearDown(() => auth.dispose());

  Future<void> pumpSignIn(WidgetTester tester, {AuthService? service}) async {
    // الشاشة بقت أطول (علامة ف وصفوف الدخول) — نكبّر النافذة بدل السكرول
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SignInScreen(auth: service),
                    ),
                  ),
                  child: const Text('host-open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('host-open'));
    await settle(tester);
  }

  screenTest('الشرح بالعربي، «كمّل بحساب تجريبي» ٦٤، و«مش دلوقتي» ≥٥٦ — ومفيش أحمر', (tester) async {
    await pumpSignIn(tester, service: auth);

    expect(find.textContaining('عشان لو جرعة مهمة فاتت'), findsOneWidget);
    expect(find.text('حساب تجريبي'), findsOneWidget, reason: 'الدخول مجهول — بنسمّيه باسمه');
    expect(tester.getSize(find.widgetWithText(FilledButton, 'كمّل بحساب تجريبي')).height,
        F.primaryButtonHeight);
    expect(
      tester.getSize(find.ancestor(of: find.text('مش دلوقتي'), matching: find.byType(TextButton))).height,
      F.minTapTarget,
    );
    expectNoRedAndMinSize(tester);
  });

  screenTest('«مش دلوقتي» بترجّع جوّه التطبيق كامل — مش عالقة', (tester) async {
    await pumpSignIn(tester, service: auth);

    await tester.tap(find.text('مش دلوقتي'));
    await settle(tester);

    expect(find.byType(SignInScreen), findsNothing);
    expect(find.text('host-open'), findsOneWidget);
    expect(auth.currentUser, isNull);
  });

  screenTest('الإلغاء بإيده: صامت تماماً — ولا رسالة ولا لون', (tester) async {
    auth.nextFailure = const SignInException(SignInFailure.aborted);
    await pumpSignIn(tester, service: auth);

    await tester.tap(find.text('كمّل بحساب تجريبي'));
    await settle(tester);

    expect(find.textContaining('مقدرناش'), findsNothing);
    expect(find.textContaining('مفيش نت'), findsNothing);
    expect(find.text('كمّل بحساب تجريبي'), findsOneWidget);
  });

  screenTest('أوفلاين وباقي الأسباب: الجملة المحددة، مش رسالة SDK', (tester) async {
    await pumpSignIn(tester, service: auth);

    for (final (failure, message) in [
      (SignInFailure.offline, 'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.'),
      (SignInFailure.noGoogleAccount, 'مفيش حساب جوجل على الجهاز ده.'),
      (SignInFailure.other, 'مقدرناش نكمّل التسجيل. جرّب تاني.'),
    ]) {
      auth.nextFailure = SignInException(failure, 'PlatformException(raw sdk text)');
      await tester.tap(find.text('كمّل بحساب تجريبي'));
      await settle(tester);

      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
    }
  });

  screenTest('نجاح → طريقا الأب والابن وزرار خروج', (tester) async {
    auth.signedInUser = const FakkarniUser(id: 'anon-1', isAnonymous: true);
    await pumpSignIn(tester, service: auth);

    await tester.tap(find.text('كمّل بحساب تجريبي'));
    await settle(tester);

    // الدورين من البيانات: نفس الشاشة بتعرض الطريقين بعد الدخول (كروت المخطط ٢)
    expect(find.text('اعرض كود الربط'), findsOneWidget);
    expect(find.text('عندي كود من والدي'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'كمّل بحساب تجريبي'), findsNothing);
    expect(find.text('المتابعة بحساب Google'), findsNothing, reason: 'بعد الدخول مفيش صفوف دخول');

    await tester.ensureVisible(find.text('تسجيل الخروج'));
    await tester.tap(find.text('تسجيل الخروج'));
    await settle(tester);
    expect(find.widgetWithText(FilledButton, 'كمّل بحساب تجريبي'), findsOneWidget);
  });

  // ⚠️ ممنوع زرار Google أو Apple شكله شغّال وهو مش شغّال.
  screenTest('Google و Apple معروضين ومعطّلين — مش أزرار، وكل واحد بسببه هو', (tester) async {
    await pumpSignIn(tester, service: auth);

    final google = find.text('المتابعة بحساب Google');
    final apple = find.text('المتابعة بحساب Apple');
    expect(google, findsOneWidget);
    expect(apple, findsOneWidget);

    // مش جوّه أي زرار ولا InkWell — مفيش حاجة تتداس
    for (final row in [google, apple]) {
      expect(find.ancestor(of: row, matching: find.byType(ButtonStyleButton)), findsNothing);
      expect(find.ancestor(of: row, matching: find.byType(InkWell)), findsNothing);
    }

    // السبب بتاع كل صف جنبه هو — مش سبب أبل على صف جوجل
    Finder rowOf(Finder title) =>
        find.ancestor(of: title, matching: find.byType(Row)).first;
    expect(find.descendant(of: rowOf(google), matching: find.text('قريباً')), findsOneWidget);
    expect(find.descendant(of: rowOf(google), matching: find.textContaining('Apple Developer')), findsNothing);
    expect(find.descendant(of: rowOf(apple), matching: find.text('محتاج حساب Apple Developer')), findsOneWidget);
    expect(find.descendant(of: rowOf(apple), matching: find.text('قريباً')), findsNothing);

    // الدوس عليهم ما بيعملش حاجة
    await tester.tap(google, warnIfMissed: false);
    await tester.tap(apple, warnIfMissed: false);
    await settle(tester);
    expect(auth.signInCalls, 0);
    expect(find.widgetWithText(FilledButton, 'كمّل بحساب تجريبي'), findsOneWidget,
        reason: 'الزرار الشغّال الوحيد');
    expect(find.byType(FilledButton), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('من غير إعداد Supabase → رسالة الناقص، ومفيش زرار جوجل', (tester) async {
    await pumpSignIn(tester, service: null);

    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.text('كمّل بحساب تجريبي'), findsNothing);
    expect(find.text('مش دلوقتي'), findsOneWidget);
  });
}
