// **ده كان مرآة، وبقى شبكة أمان.**
//
// «هيتمسح نهائي بعد ٣٠ يوم» كانت مكتوبة مرتين — `RecordsRepository
// .retentionDays` على موبايل الأب و`private.record_retention()` في السحابة
// (0012) — والاختبار ده كان بيمسك انحرافهم.
//
// المهلة اتشالت من التطبيق: المسح بقى بيمسح، والمزامنة بتشيل الصف السحابي
// في الدفعة الجاية (`_pushRecords`). فمفيش رقم في دارت يتقارن بيه، ومفيش
// وعد للمستخدم بالرقم ده خالص.
//
// اللي فاضل في السحابة بيفضل مكانه **عن قصد**، لحالة واحدة: موبايل مسح
// سجل وما نجحش يوصل السحابة تاني أبداً — اتكسر، اتباع، أو الشبكة ما رجعتش.
// ساعتها الشاهدة اللي اترفعت قبل المسح هي كل اللي هناك، والكرون هو اللي
// بيشيلها. من غير الكرون الصف ده بيقعد في ملف الابن للأبد.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migration = 'supabase/migrations/0012_health_file.sql';

void main() {
  late String sql;

  setUp(() => sql = File(_migration).readAsStringSync());

  test('شبكة الأمان لسه موجودة: purge_deleted_records بتمسح الشواهد القديمة', () {
    expect(
      RegExp(r'create or replace function private\.purge_deleted_records').hasMatch(sql),
      isTrue,
      reason: 'الدالة اتشالت — يبقى صف اتمسح على موبايل مات هيفضل عند الابن للأبد',
    );
    expect(
      RegExp(r'deleted_at\s*<\s*now\(\)\s*-\s*private\.record_retention\(\)').hasMatch(sql),
      isTrue,
      reason: 'لازم تعدّي على الدالة، مش رقم مكتوب في نص الاستعلام',
    );
  });

  test('والكرون بينده عليها — دالة من غير جدول ما بتشتغلش', () {
    expect(sql, contains('fakkarni-purge-records'));
    expect(
      RegExp(r'\$job\$\s*select private\.purge_deleted_records\(\)\s*\$job\$').hasMatch(sql),
      isTrue,
    );
  });
}
