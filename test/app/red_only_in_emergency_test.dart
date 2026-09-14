import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الأحمر للطوارئ بس (CLAUDE.md، PHASE_D3): الشاشتين في `features/emergency/`.
/// الاختبار بيقرا الكود نفسه — لون أحمر في أي شاشة تانية غلط، حتى لو مفيش
/// اختبار واجهة بيعدّي عليها.
void main() {
  test('F.red / F.redDeep / F.redPanel / F.onRed وقيمهم ما بيظهروش برّه شاشات الطوارئ', () {
    final forbidden = RegExp(
      r'F\.(red|redDeep|redPanel|onRed|onRedMuted)\b|0xFFC0202F|0xFFA81E26|0xFF8C1820|Colors\.red',
      caseSensitive: false,
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/features/emergency/')) continue;
      if (path == 'lib/core/theme/tokens.dart') continue; // التعريف نفسه
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (forbidden.hasMatch(line)) offenders.add('$path:${i + 1}: $line');
      }
    }
    expect(offenders, isEmpty);
  });
}
