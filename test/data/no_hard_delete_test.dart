import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **مفيش مسح لدوا ولا لجرعة — في أي مكان في `lib/`.**
///
/// السبب مكتوب في `0014_soft_stop.sql` وفي عمودي [Medications.removedAt] و
/// [DoseSchedules.stoppedAt]: المزامنة بترفع بس (دين ١)، و`dose_events`
/// بتتمسح بالـcascade. فالمسح بيشيل الدليل من على الموبايل والسحابة تفضل
/// تنبّه الابن على جرعة مابقتش موجودة — وموبايل الأب مش قادر يصحّح صف مسحه.
///
/// الحارس ده بيقرا الكود زي حارس الأحمر وحارس النقطة. لو جه يوم وفيه مسح
/// حقيقي، هيبقى بعد ما المزامنة تتعلّم تمسح — والسطر ده هو اللي هيفكّرنا.
void main() {
  /// النداء اللي ممنوع — بنفس الشكل في الحارس وفي الـmutation-check تحته.
  bool isDelete(String line) =>
      RegExp(r'\.delete\(\s*_db\.(medications|doseSchedules)\b').hasMatch(line) ||
      RegExp(r'delete\s+from\s+(medications|dose_schedules)\b', caseSensitive: false).hasMatch(line);

  test('ولا نداء مسح على medications أو dose_schedules', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') || line.startsWith('*') || line.startsWith('///')) continue;
        if (isDelete(line)) {
          offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'الإيقاف الناعم هو الطريق: removedAt / stoppedAt — مش مسح',
    );
  });

  test('الحارس بيمسك المسح فعلاً (mutation-check مكتوب)', () {
    expect(isDelete('await (_db.delete(_db.medications)..where((t) => t.id.equals(id))).go();'), isTrue);
    expect(isDelete('await (_db.delete(_db.doseSchedules)..where((t) => t.id.equals(id))).go();'), isTrue);
    expect(isDelete("await customStatement('DELETE FROM dose_schedules WHERE id = ?');"), isTrue);
    // والمسموح ما بيتمسكش
    expect(isDelete('await (_db.delete(_db.fixedTimings)..where((t) => t.id.equals(id))).go();'), isFalse);
    expect(isDelete('.write(MedicationsCompanion(removedAt: Value(at)));'), isFalse);
  });

  test('الترحيل ٠٠١٤ بيستنى العمودين وبيستثنيهم من التصعيد', () {
    final sql = File('supabase/migrations/0014_soft_stop.sql').readAsStringSync();
    expect(sql, contains('add column if not exists removed_at'));
    expect(sql, contains('add column if not exists stopped_at'));
    expect(sql, contains('and m.removed_at is null'));
    expect(sql, contains('and s.stopped_at is null'));
    // التعريف الوحيد للاختيار لسه واحد
    expect('create or replace function private.due_escalations'.allMatches(sql), hasLength(1));
  });
}
