// 0033: الحسابات اللي اتمسحت بتختفي من كل قايمة — اللي فاضل عدّ مجهول.
import 'package:fakkarni_admin/data/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('صف admin_counts بعد 0033 بيقرا العدّين، وقبلها صفر', () {
    final after = AdminCounts.fromRow({
      'total_patients': 3,
      'total_followers': 4,
      'active_7d': 2,
      'battery_restricted': 0,
      'deleted_total': 5,
      'deleted_30d': 2,
    });
    expect(after.deletedTotal, 5);
    expect(after.deleted30d, 2);
    final before = AdminCounts.fromRow({'total_patients': 3, 'total_followers': 4, 'active_7d': 2, 'battery_restricted': 0});
    expect(before.deletedTotal, 0);
  });

  test('السطر أرقام وبس', () {
    expect(deletedAccountsLine(AdminCounts.empty), 'مفيش حسابات اتمسحت لسه.');
    expect(
      deletedAccountsLine(const AdminCounts(
          totalPatients: 0, totalFollowers: 0, active7d: 0, batteryRestricted: 0, deletedTotal: 12, deleted30d: 3)),
      'حسابات اتمسحت: ١٢ — منهم ٣ في آخر ٣٠ يوم.',
    );
  });
}
