// «دورة» ممنوعة في أي نص بيوصل الشاشة.
//
// الاسم اللي الراجل بيقراه بقى «تابع تحليل» / «متابعة التحليل». «دورة
// فحص» كانت بتوصف عملية إدارية — والراجل اللي طالع من عند الدكتور بورقة
// مش بيفكّر إنه بيبدأ «دورة»، هو عايز حد يمشي معاه لحد ما النتيجة توصل.
//
// الأسماء في الكود زي ما هي عن قصد: `CheckupStage`، `records.checkup_stage`،
// `CheckupService`. دي لغة الكود، وتغييرها كان هيبقى ترحيل مالوش لازمة.
// فالاختبار ده بيقرا **النصوص بين علامتي التنصيص بس** — زي
// `no_middle_dot_test` بالظبط — والتعليقات مستثناة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('«دورة» ما بتظهرش في أي نص بيتعرض', () {
    const roots = ['lib/features', 'lib/data', 'lib/core', 'lib/app', 'lib/domain', 'lib/ai'];
    final literal = RegExp(r"""('((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""");

    /// الكلمة نفسها بأي تصريف بيقراه الناس: دورة، الدورة، دورات، لدورة…
    final word = RegExp('دور(ة|ات)');
    final offenders = <String>[];

    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final m in literal.allMatches(line)) {
            if (word.hasMatch(m.group(0)!)) {
              offenders.add('${entity.path}:${i + 1}: ${trimmed.trim()}');
            }
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'الاسم للمستخدم «تابع تحليل» / «متابعة التحليل» — مش «دورة»',
    );
  });
}
