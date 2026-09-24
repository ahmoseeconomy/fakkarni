import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/care_circle_service.dart';
import 'package:fakkarni/domain/care/follower_role.dart';
import 'package:fakkarni/features/entry/entry_screen.dart';
import 'package:fakkarni/features/link/redeem_code_screen.dart';

import '../../data/care/care_circle_service_test.dart' show FakeCareCircleService;
import '../scan/scan_test_support.dart' show screenTest, settle;

/// سيرفر وهمي بيعمل زي `redeem_invite(p_code, p_expect_role)` في ٠٠٢٦:
/// كود من نوع تاني في الباب بيترفض **من غير ما يتحرق**.
class _RoleCare extends FakeCareCircleService implements RoleRedeem {
  _RoleCare(this.codes);

  /// الكود ← نوعه.
  final Map<String, FollowerRole> codes;
  final burned = <String>[];
  final doors = <FollowerRole>[];

  @override
  Future<String> redeemInviteAt(String code, FollowerRole door) async {
    doors.add(door);
    final role = codes[code];
    if (role == null) throw const CareCircleException(CareCircleFailure.invalidOrExpiredCode);
    if (role != door) {
      throw CareCircleException(role == FollowerRole.follower
          ? CareCircleFailure.followerCodeAtNurseDoor
          : CareCircleFailure.nurseCodeAtFollowerDoor);
    }
    burned.add(code);
    return patientName;
  }
}

void main() {
  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: home,
    ));
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField), code);
    await settle(tester);
    await tester.tap(find.text('اربط'));
    await settle(tester);
  }

  final codes = {'111111': FollowerRole.follower, '222222': FollowerRole.nurse};

  group('شاشة البداية', () {
    screenTest('تلات أبواب، والتاني بالاسم الجديد، والتالت بيروح لطريق الممرض', (tester) async {
      var nurse = 0;
      var follower = 0;
      await pump(tester, EntryScreen(onSelf: () {}, onHaveCode: () => follower++, onNurse: () => nurse++));
      expect(find.text('معايا كود متابعة'), findsOneWidget);
      expect(find.text('ابن، بنت أو قريب'), findsOneWidget);
      expect(find.text('أنا ممرض / مرافق'), findsOneWidget);
      expect(find.text('هتابع مريض وأساعده في أدويته'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('entry-nurse')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('entry-start')));
      await settle(tester);
      expect((nurse, follower), (1, 0));
    });
  });

  group('الكود بيطابق الباب', () {
    screenTest('باب الممرض + كود متابع: الجملة البسيطة، والكود ما اتحرقش', (tester) async {
      final care = _RoleCare(codes);
      await pump(tester, RedeemCodeScreen(care: care, door: FollowerRole.nurse));
      await type(tester, '111111');
      expect(find.text('الكود ده لمتابع — اطلب من المريض كود ممرض'), findsOneWidget);
      expect(care.burned, isEmpty);
      expect(care.doors, [FollowerRole.nurse]);
    });

    screenTest('باب الممرض + كود ممرض: بيتربط', (tester) async {
      final care = _RoleCare(codes);
      await pump(tester, RedeemCodeScreen(care: care, door: FollowerRole.nurse));
      await type(tester, '222222');
      expect(care.burned, ['222222']);
      expect(find.textContaining('الحاج أحمد'), findsWidgets);
    });

    screenTest('باب المتابع + كود ممرض: بيقوله يرجع لباب الممرض', (tester) async {
      final care = _RoleCare(codes);
      await pump(tester, RedeemCodeScreen(care: care, door: FollowerRole.follower));
      await type(tester, '222222');
      expect(find.textContaining('الكود ده لممرض'), findsOneWidget);
      expect(care.burned, isEmpty);
    });

    screenTest('من غير باب (الطريق القديم): الاستبدال العادي زي ما هو', (tester) async {
      final care = _RoleCare(codes);
      await pump(tester, RedeemCodeScreen(care: care));
      await type(tester, '111111');
      expect(care.doors, isEmpty);
      expect(care.redeemed, ['111111']);
    });
  });

  test('الكلام مش تقني والدائرة الكاملة ليها جملة', () {
    expect(const CareCircleException(CareCircleFailure.circleFull).message, contains('خمسة'));
    for (final f in [CareCircleFailure.followerCodeAtNurseDoor, CareCircleFailure.nurseCodeAtFollowerDoor]) {
      expect(CareCircleException(f).message, isNot(contains('role')));
    }
  });
}
