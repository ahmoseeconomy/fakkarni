import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/lab_range.dart';

/// **مفيش في التطبيق جدول قيم طبيعية، ومش هيبقى فيه.**
///
/// النطاقات بتختلف من معمل لمعمل، وبطريقة التحليل، وبالسن والنوع. جدول
/// مكتوب عندنا معناه إننا بنقول لواحد إن رقمه «فوق المعدل» على أساس معيار
/// ما حدش أدهولنا — وده كلام دكتور (القاعدة ٦). النطاق الوحيد المسموح هو
/// اللي **مطبوع على ورقة المعمل اللي في إيده**، وبييجي من `lab_results`.
///
/// الاختبار بيدوّر على الشكل اللي الجدول ده بيجي بيه: اسم تحليل معروف
/// مكتوب كنص في الكود وجنبه رقم.
const _knownTestNames = [
  'hba1c', 'glucose', 'cholesterol', 'triglyceride', 'creatinine', 'urea',
  'hemoglobin', 'haemoglobin', 'hgb', 'wbc', 'rbc', 'platelet', 'tsh', 't3', 't4',
  'ldl', 'hdl', 'alt', 'ast', 'albumin', 'bilirubin', 'ferritin', 'uric',
  'sodium', 'potassium', 'calcium', 'vitamin', 'crp', 'esr', 'psa', 'inr',
  'كوليسترول', 'هيموجلوبين', 'كرياتينين', 'سكر صايم', 'تراي جليسريد',
];

void main() {
  test('ولا اسم تحليل معروف مكتوب في lib جنب رقم — يعني مفيش جدول قيم طبيعية', () {
    final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final number = RegExp(r'\b\d+(\.\d+)?\b');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('.g.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i];
        final line = raw.trimLeft();
        if (line.startsWith('//') || line.startsWith('*')) continue;
        for (final m in literal.allMatches(raw)) {
          final text = m.group(1)!.toLowerCase();
          for (final name in _knownTestNames) {
            // بحدود كلمة: «last» فيها «ast»، و«ألت» مش «ALT».
            if (!RegExp('(?<![a-z0-9])$name(?![a-z0-9])').hasMatch(text)) continue;
            // اسم تحليل في نص + رقم في نفس السطر = بداية جدول.
            if (number.hasMatch(raw)) {
              offenders.add('$path:${i + 1}: $raw');
            }
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'ده شكل جدول قيم طبيعية — النطاق بييجي من ورقة المعمل، مش من عندنا');
  });

  test('قاعدة المقارنة مفيهاش ولا رقم من عندنا غير نسبة «قريب من الحد»', () {
    final source = File('lib/domain/health/lab_range.dart').readAsLinesSync();
    final numbers = <String>[];
    final literal = RegExp(r'(?<![\w.])\d+(\.\d+)?(e-?\d+)?');
    for (final raw in source) {
      final line = raw.trimLeft();
      if (line.startsWith('//') || line.startsWith('///')) continue;
      for (final m in literal.allMatches(line)) {
        numbers.add(m.group(0)!);
      }
    }
    // ٠.١٠ = نسبة «قريب من الحد»، و1e-9 = هامش الـfloat على الحافة. وبس.
    expect(numbers.toSet(), {'0.10', '1e-9'},
        reason: 'رقم جديد في قاعدة المقارنة — من فين جه؟ لازم يكون من الورقة');
    expect(nearBoundaryFraction, 0.10);
  });
}
