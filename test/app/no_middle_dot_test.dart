import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// النقطة الوسطى «·» ممنوعة في أي نص بيوصل الشاشة (ولا في ملف الـPDF).
///
/// السبب مش ذوق: الصفر العربي «٠» شكله نقطة. جنب أرقام عربي، الفاصل
/// والصفر بيبقوا نفس الحاجة بالظبط، والمستخدم بيقرا رقم تاني خالص:
///
///   «الحاج عاشور · ٦٢ سنة»       بتتقري «الحاج عاشور ٦٢٠ سنة»
///   «كمان ١٠ ساعات · ٧:٣٠ م»     بتتقري «٧:٣٠٠ م»
///
/// البديل «—» بمسافات (أو سطر تاني لما يبقى أنضف). التعليقات
/// والـdocstrings مستثناة — النقطة مشكلة على الشاشة بس.
///
/// الاختبار بيقرا الكود نفسه (زي `red_only_in_emergency_test`): أي نص
/// بين علامتي تنصيص في السطور اللي مش تعليق.
void main() {
  test('«·» ما بتظهرش في أي نص بيتعرض', () {
    const roots = ['lib/features', 'lib/data', 'lib/core', 'lib/app', 'lib/domain', 'lib/ai'];
    final literal = RegExp(r"""('((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""");
    final offenders = <String>[];

    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final m in literal.allMatches(line)) {
            if (m.group(0)!.contains('·')) {
              offenders.add('${entity.path}:${i + 1}: ${trimmed.trim()}');
            }
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'الصفر العربي «٠» شكله نقطة — استعمل « — » أو اكسر السطر',
    );
  });
}
