import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/care_circle_service.dart';
import 'package:fakkarni/domain/care/follower_role.dart';
import 'package:fakkarni/features/link/link_code_screen.dart';

import '../../data/care/care_circle_service_test.dart' show FakeCareCircleService;
import '../scan/scan_test_support.dart' show settle, screenTest, expectNoRedAndMinSize;

void main() {
  late FakeCareCircleService care;

  setUp(() => care = FakeCareCircleService());

  Future<void> pumpCode(WidgetTester tester) async {
    // الشاشة بقت أطول من ٦٠٠ بكسل — نكبّر النافذة بدل السكرول
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LinkCodeScreen(
            care: care,
            patientUuid: 'p-uuid-1',
            patientName: 'الحاج أحمد',
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('صف المريض بيترفع الأول وبعده الكود — ستة أرقام عربي في سطر واحد، والشرح بالبساطة', (tester) async {
    await pumpCode(tester);

    expect(care.upserts, [(uuid: 'p-uuid-1', name: 'الحاج أحمد')]);
    expect(care.createdFor, ['p-uuid-1']);

    // «١٢٣٤٥١» — عربي زي باقي التطبيق، ستة أرقام في تتابع واحد من غير مسافة
    expect(find.text('١٢٣٤٥١'), findsOneWidget);
    final code = tester.widget<Text>(find.text('١٢٣٤٥١'));
    expect(code.style?.letterSpacing, greaterThan(0), reason: 'أرقام — التباعد مسموح');
    expect(code.style?.fontSize, greaterThanOrEqualTo(48), reason: 'بيتقري عبر أوضة');
    expect(find.text('دائرة الرعاية'), findsOneWidget);
    expect(find.textContaining('يشوف أدويتك ومواعيدك'), findsOneWidget);
    expect(find.textContaining('صالح ١٥ دقيقة'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«انسخ الكود» بتنسخ الأرقام الغربية — اللي كيبورد الابن بيكتبها', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpCode(tester);

    final copy = find.widgetWithText(OutlinedButton, 'انسخ الكود');
    expect(copy, findsOneWidget);
    expect(tester.getSize(copy).height, F.minTapTarget);
    await tester.tap(copy);
    await settle(tester);

    expect(copied, '123451');
    expect(find.textContaining('اتنسخ'), findsOneWidget);
  });

  screenTest('«ابعته» بكلمة، وبتسلّم رسالة فيها الكود لورقة المشاركة لو موجودة', (tester) async {
    String? shared;
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LinkCodeScreen(
            care: care,
            patientUuid: 'p-uuid-1',
            patientName: 'الحاج أحمد',
            share: (text) async => shared = text,
          ),
        ),
      ),
    );
    await settle(tester);

    final send = find.widgetWithText(OutlinedButton, 'ابعته');
    expect(send, findsOneWidget);
    expect(find.byIcon(Icons.send_outlined), findsOneWidget, reason: 'أيقونة وكلمة');
    await tester.tap(send);
    await settle(tester);

    expect(shared, contains('123451'));
    expect(shared, contains('عندي كود'));
  });

  screenTest('«كود جديد» ٦٤ وبيجيب كوداً مختلفاً', (tester) async {
    await pumpCode(tester);

    expect(tester.getSize(find.widgetWithText(FilledButton, 'كود جديد')).height,
        F.primaryButtonHeight);

    await tester.tap(find.text('كود جديد'));
    await settle(tester);

    expect(find.text('١٢٣٤٥٢'), findsOneWidget);
    expect(find.text('١٢٣٤٥١'), findsNothing);
    expect(care.createdFor.length, 2);
  });

  screenTest('أوفلاين → الجملة المتفق عليها، من غير أحمر', (tester) async {
    care.nextFailure = const CareCircleException(CareCircleFailure.offline);
    await pumpCode(tester);

    expect(
      find.text('مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.'),
      findsOneWidget,
    );
    expectNoRedAndMinSize(tester);
  });
  screenTest('شريحتين كبار: «متابع» افتراضياً، و«ممرض / مرافق» بيعمل كود جديد بدوره', (tester) async {
    final roles = _FakeRoles();
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: LinkCodeScreen(care: care, patientUuid: 'p-uuid-1', patientName: 'الحاج أحمد', roles: roles),
      ),
    ));
    await settle(tester);

    expect(find.text('الكود ده لمين؟'), findsOneWidget);
    expect(find.text('متابع'), findsOneWidget);
    expect(find.text('ممرض / مرافق'), findsOneWidget);
    expect(roles.created, [FollowerRole.follower], reason: 'الافتراضي متابع — زي كل الأكواد القديمة');
    expect(care.createdFor, isEmpty, reason: 'مع الأدوار الكود بيتعمل من الدالة اللي بتاخد الدور');

    await tester.tap(find.byKey(const ValueKey('invite-role-nurse')));
    await settle(tester);
    // ٠٠٢٦: بيسأل مرة «يقدر يعدّل الأدوية والمواعيد؟» قبل ما الكود يتعمل
    expect(find.text('يقدر يعدّل الأدوية والمواعيد؟'), findsOneWidget);
    expect(roles.created, [FollowerRole.follower], reason: 'مفيش كود قبل الإجابة');
    await tester.tap(find.byKey(const ValueKey('nurse-edit-yes')));
    await settle(tester);
    expect(roles.created, [FollowerRole.follower, FollowerRole.nurse]);
    expect(roles.canEdit.last, isTrue, reason: 'الإجابة بتروح مع الكود');
    expect(find.text('٦٥٤٣٢٢'), findsOneWidget, reason: 'كود جديد بدوره');
    expect(find.byKey(const ValueKey('invite-nurse-edit-line')), findsOneWidget);
    expect(find.textContaining('يأكّد الجرعة بدالك'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('٠٠٢٦: «لأ» بتعمل كود ممرض من غير تعديل، وقفل الورقة ما بيغيّرش الدور', (tester) async {
    final roles = _FakeRoles();
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: LinkCodeScreen(care: care, patientUuid: 'p-uuid-1', patientName: 'الحاج أحمد', roles: roles),
      ),
    ));
    await settle(tester);

    // قفل الورقة من غير إجابة
    await tester.tap(find.byKey(const ValueKey('invite-role-nurse')));
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(roles.created, [FollowerRole.follower], reason: 'الدور ما اتغيّرش');

    await tester.tap(find.byKey(const ValueKey('invite-role-nurse')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nurse-edit-no')));
    await settle(tester);
    expect(roles.created.last, FollowerRole.nurse);
    expect(roles.canEdit.last, isFalse);
    expect(find.textContaining('بيشوف ويأكّد بس'), findsOneWidget);
  });
}

/// الكود بدور (٠٠٢٣): «متابع» افتراضياً، و«ممرض / مرافق» بيعمل كود بدوره.
class _FakeRoles implements CareCircleAdmin {
  final created = <FollowerRole>[];
  final canEdit = <bool>[];

  @override
  Future<InviteCode> createRoleInvite(String patientUuid, FollowerRole role, {bool canEditMeds = false}) async {
    created.add(role);
    canEdit.add(canEditMeds);
    return InviteCode(code: '65432${created.length}', expiresAt: DateTime(2026, 9, 1, 10));
  }

  @override
  Future<List<FollowerWithPermissions>> followersWithPermissions(String patientUuid) async => const [];
  @override
  Future<void> setFollowerPermissions(String patientUuid, String caregiverId, FollowerPermissions permissions) async {}
  @override
  Future<void> removeFollower(String patientUuid, String caregiverId) async {}
}
