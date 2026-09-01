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

  screenTest('الشرح بالعربي، زرار جوجل ٦٤، و«مش دلوقتي» ≥٥٦ — ومفيش أحمر', (tester) async {
    await pumpSignIn(tester, service: auth);

    expect(find.textContaining('عشان لو جرعة مهمة فاتت'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'اربط ابني')).height,
        F.primaryButtonHeight);
    expect(find.text('سجّل بحساب جوجل'), findsNothing, reason: 'جوجل متأجّلة');
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

    await tester.tap(find.text('اربط ابني'));
    await settle(tester);

    expect(find.textContaining('مقدرناش'), findsNothing);
    expect(find.textContaining('مفيش نت'), findsNothing);
    expect(find.text('اربط ابني'), findsOneWidget);
  });

  screenTest('أوفلاين وباقي الأسباب: الجملة المحددة، مش رسالة SDK', (tester) async {
    await pumpSignIn(tester, service: auth);

    for (final (failure, message) in [
      (SignInFailure.offline, 'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.'),
      (SignInFailure.noGoogleAccount, 'مفيش حساب جوجل على الجهاز ده.'),
      (SignInFailure.other, 'مقدرناش نكمّل التسجيل. جرّب تاني.'),
    ]) {
      auth.nextFailure = SignInException(failure, 'PlatformException(raw sdk text)');
      await tester.tap(find.text('اربط ابني'));
      await settle(tester);

      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
    }
  });

  screenTest('نجاح → رسالة الربط وزرار خروج', (tester) async {
    // المجهول ملوش إيميل — الرسالة بتاعته مختلفة
    auth.signedInUser = const FakkarniUser(id: 'anon-1', isAnonymous: true);
    await pumpSignIn(tester, service: auth);

    await tester.tap(find.text('اربط ابني'));
    await settle(tester);

    expect(find.textContaining('اتربط الجهاز ده'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'اربط ابني'), findsNothing);

    await tester.tap(find.text('تسجيل الخروج'));
    await settle(tester);
    expect(find.widgetWithText(FilledButton, 'اربط ابني'), findsOneWidget);
  });

  screenTest('من غير إعداد Supabase → رسالة الناقص، ومفيش زرار جوجل', (tester) async {
    await pumpSignIn(tester, service: null);

    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.text('اربط ابني'), findsNothing);
    expect(find.text('مش دلوقتي'), findsOneWidget);
  });
}
