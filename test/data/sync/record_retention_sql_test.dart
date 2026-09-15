// «هيتمسح نهائي بعد ٣٠ يوم» مكتوبة مرتين — `RecordsRepository.retentionDays`
// على موبايل الأب، و`private.record_retention()` في السحابة (0012). Postgres
// ما بيقراش دارت. لو انحرفوا، الشاشة بتقول رقم والسحابة بتعمل رقم تاني —
// يا إما سجل ممسوح بيفضل عند الابن بعد الوعد، يا إما بيتمسح قبله.
//
// بيقرا ملف الترحيل نفسه، زي `server_grace_sql_test`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/repositories/records_repository.dart';

const _migration = 'supabase/migrations/0012_health_file.sql';

final _retentionInSql = RegExp(
  r"function\s+private\.record_retention\s*\(\s*\)[\s\S]*?interval\s*'(\d+)\s*days'",
);
final _anyDaysInterval = RegExp(r"interval\s*'(\d+)\s*days'");

void main() {
  late String sql;

  setUp(() => sql = File(_migration).readAsStringSync());

  test('الـ٣٠ يوم في SQL = retentionDays في دارت', () {
    final match = _retentionInSql.firstMatch(sql);
    expect(match, isNotNull, reason: 'private.record_retention() مش لاقيها في $_migration');
    expect(int.parse(match!.group(1)!), RecordsRepository.retentionDays);
  });

  test('المسح بيعدّي على الدالة — مفيش نسخة تانية من الرقم في الملف', () {
    // التأكيد في آخر الملف بيستعمل ٣١ و٢٩ يوم كحدود، مش كمهلة
    final values = {
      for (final m in _anyDaysInterval.allMatches(sql)) int.parse(m.group(1)!),
    }..removeAll({RecordsRepository.retentionDays + 1, RecordsRepository.retentionDays - 1});
    expect(values, {RecordsRepository.retentionDays});
    expect(
      RegExp(r'deleted_at\s*<\s*now\(\)\s*-\s*private\.record_retention\(\)').hasMatch(sql),
      isTrue,
      reason: 'purge_deleted_records لازم تستعمل الدالة، مش رقم مكتوب',
    );
  });
}
