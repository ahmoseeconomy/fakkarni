import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/care/follower_role.dart';

/// الدور والصلاحيات — دارت نقية.
void main() {
  test('دورين بكلمتهم، والقديم (null) متابع', () {
    expect(FollowerRole.fromStored(null), FollowerRole.follower);
    expect(FollowerRole.fromStored('follower'), FollowerRole.follower);
    expect(FollowerRole.fromStored('nurse'), FollowerRole.nurse);
    expect(FollowerRole.follower.label, 'متابع');
    expect(FollowerRole.nurse.label, 'ممرض / مرافق');
  });

  test('الممرض بيأكّد افتراضياً، والمتابع لأ — وتعديل الأدوية مقفول للاتنين', () {
    expect(FollowerRole.nurse.confirmsByDefault, isTrue);
    expect(FollowerRole.follower.confirmsByDefault, isFalse);
    expect(FollowerPermissions.plainFollower.canConfirm, isFalse);
    expect(FollowerPermissions.plainFollower.canEditMeds, isFalse);
  });

  test('«أكّدها {اسم}» — ومن غير اسم مفيش اسم مخترع', () {
    expect(proxyConfirmedLine('سارة'), 'أكّدها سارة');
    expect(proxyConfirmedLine(' '), 'أكّدها حد بيتابعك');
    expect(proxyConfirmedLine(null), 'أكّدها حد بيتابعك');
    expect(proxyPendingLine, contains('مستنية موبايله'));
  });
}
