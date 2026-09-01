import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// جانب الابن **عمره ما يحل مراسي**: نسخة تانية من المحرّك = جدولين ممكن
/// يختلفوا في صمت، والابن يتصل على جرعة موبايل أبوه ما رنّش عليها أصلاً.
/// المحرّك الوحيد على جهاز الأب؛ الشاشة دي بتعرض اللي هو كتبه أو ما تعرضش.
void main() {
  test('نافذة الابن ما فيهاش ولا استيراد من domain/scheduling', () {
    final files = [
      ...Directory('lib/features/care').listSync(recursive: true),
      File('lib/data/care/caregiver_remote.dart'),
      File('lib/data/care/supabase_caregiver_remote.dart'),
    ];
    for (final entity in files) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(
        source.contains('domain/scheduling'),
        isFalse,
        reason: '${entity.path} بيستورد الجدولة — جانب الابن بيعرض، مش بيحسب',
      );
    }
  });
}
