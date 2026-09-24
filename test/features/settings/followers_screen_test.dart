import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/care_circle_service.dart';
import 'package:fakkarni/domain/care/follower_profile.dart';
import 'package:fakkarni/domain/care/follower_role.dart';
import 'package:fakkarni/features/settings/followers_screen.dart';

import '../scan/scan_test_support.dart' show settle, screenTest, expectNoRedAndMinSize;

/// «اللي بيتابعوك» (٠٠٢٣): الدور، وتغييره، و«يعدّل الأدوية»، والشيل — كل
/// كتابة دالة على السيرفر للمالك بس.
class _FakeAdmin implements CareCircleAdmin {
  final rows = <FollowerWithPermissions>[];
  final writes = <String>[];

  @override
  Future<InviteCode> createRoleInvite(String patientUuid, FollowerRole role, {bool canEditMeds = false}) async =>
      InviteCode(code: '123456', expiresAt: DateTime(2026, 9, 1));

  @override
  Future<List<FollowerWithPermissions>> followersWithPermissions(String patientUuid) async => List.of(rows);

  @override
  Future<void> setFollowerPermissions(String patientUuid, String caregiverId, FollowerPermissions permissions) async {
    writes.add('set:$caregiverId:${permissions.role.name}:${permissions.canConfirm}:${permissions.canEditMeds}');
    final i = rows.indexWhere((r) => r.caregiverId == caregiverId);
    rows[i] = FollowerWithPermissions(caregiverId: caregiverId, profile: rows[i].profile, permissions: permissions);
  }

  @override
  Future<void> removeFollower(String patientUuid, String caregiverId) async {
    writes.add('remove:$caregiverId');
    rows.removeWhere((r) => r.caregiverId == caregiverId);
  }
}

void main() {
  late _FakeAdmin admin;
  setUp(() {
    admin = _FakeAdmin()
      ..rows.addAll([
        const FollowerWithPermissions(
          caregiverId: 'u-son',
          profile: FollowerProfile(name: 'محمد', relation: FollowerRelation.son),
          permissions: FollowerPermissions.plainFollower,
        ),
        const FollowerWithPermissions(
          caregiverId: 'u-nurse',
          profile: null,
          permissions: FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: false),
        ),
      ]);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: FollowersScreen(admin: admin, patientUuid: 'p1'),
      ),
    ));
    await settle(tester);
  }

  screenTest('كل واحد بدوره — واللي ما كتبش اسمه بيتقال كده', (tester) async {
    await pump(tester);
    expect(find.text('محمد ابنك'), findsOneWidget);
    expect(find.text('من غير اسم لسه'), findsOneWidget);
    expect(find.text('بيقدر يأكّد الجرعة بدالك.'), findsOneWidget);
    expect(find.text('ما بيقدرش يأكّد الجرعة بدالك.'), findsOneWidget);
    expect(find.text('يعدّل الأدوية — مقفول'), findsNWidgets(2));
    expectNoRedAndMinSize(tester);
  });

  screenTest('تغيير الدور لممرض بيفتح التأكيد معاه، و«يعدّل الأدوية» زرار لوحده', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('follower-role-u-son-nurse')));
    await settle(tester);
    expect(admin.writes, ['set:u-son:nurse:true:false']);
    await tester.tap(find.byKey(const ValueKey('follower-edit-meds-u-son')));
    await settle(tester);
    expect(admin.writes.last, 'set:u-son:nurse:true:true');
    expect(find.text('يعدّل الأدوية — شغّال'), findsOneWidget);
  });

  screenTest('«شيله» بيسأل بالاسم — و«لأ، سيبه» ما بتشيلش', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('follower-remove-u-son')));
    await settle(tester);
    expect(find.text('تشيل محمد؟'), findsOneWidget);
    await tester.tap(find.text('لأ، سيبه'));
    await settle(tester);
    expect(admin.writes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('follower-remove-u-son')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('follower-remove-confirm')));
    await settle(tester);
    expect(admin.writes, ['remove:u-son']);
    expect(find.text('محمد ابنك'), findsNothing);
  });
}
