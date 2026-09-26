import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// كلام تقني ممنوع في أي نص بيوصل شاشة (٢٦ سبتمبر ٢٠٢٦، آيفون): «جدول
/// النهاردة» كان تحته «المراسي ثابتة، والجرعات معلّقة عليها» — كلمة من
/// الكود وقعت على الشاشة. «مرساة» اسم المفهوم في الكود؛ المريض بيقول «مواعيد
/// يومك» و«الأكلة». وبنفس المنطق «توكن» و«مزامنة» و«isolate» وأخواتهم.
///
/// نفس شكل `no_middle_dot_test`: بيقرا كل نص بين علامتي تنصيص في ملفات
/// الواجهة، والتعليقات وسطور التشخيص (`diag`/`debugPrint`) مستثناة.
void main() {
  test('مفيش كلام تقني في نص الواجهة', () {
    const roots = ['lib/features', 'lib/app', 'lib/core/widgets'];
    final banned = RegExp(r'مرسى|مراسي|مرساة|المرساه|توكن|مزامنة|isolate|payload|anchor|offset', caseSensitive: false);
    final literal = RegExp(r"""('((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""");
    final offenders = <String>[];
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final t = lines[i].trimLeft();
          if (t.startsWith('//') || t.startsWith('*')) continue;
          if (t.contains('diag(') || t.contains('debugPrint(') || t.startsWith('import ')) continue;
          for (final m in literal.allMatches(lines[i])) {
            // اللي جوّه ${…} و$اسم ده كود مش كلام بيتعرض
            final text = (m.group(2) ?? m.group(3) ?? '')
                .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
                .replaceAll(RegExp(r'\$[A-Za-z_]\w*'), '')
                // ${…} فيه علامة تنصيص جوّاه — النص اتقطع عندها، والباقي كود
                .replaceAll(RegExp(r'\$\{.*'), '');
            // مفاتيح وأسامي كود (لاتيني بس، من غير مسافات) مش نص بيتعرض
            if (RegExp(r'^[A-Za-z0-9_.\-/$]*$').hasMatch(text)) continue;
            if (banned.hasMatch(text)) offenders.add('${entity.path}:${i + 1}: $text');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
