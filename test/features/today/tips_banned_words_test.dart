import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/adherence/adherence.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/features/today/tips/tips_ar.dart';

/// **الخطوط الحمرا بتاعة «معلومة ليك»** — على كل جملة في `tips_ar.dart`،
/// الثابتة والقوالب بعيّناتها: مفيش جرعات ولا تغيير جرعة، مفيش تفاعلات،
/// مفيش أعراض ولا تشخيص، مفيش «الأفضل لحالتك»، ومفيش «وقّف الدوا».
/// أي حاجة طبية بتقف عند «اسأل دكتورك».
///
/// الكلمات مكتوبة بالحرف عشان اللي بيراجع النصوص يعرف إيه الممنوع —
/// والاختبار بيقرا الملف كمان، فجملة اتضافت من غير ما تدخل
/// [allTipTexts] بتتفحص برضه.
const bannedInTips = [
  // جرعات وتغييرها
  'مجم', 'ملجم', 'ملّيجرام', 'ملليجرام', ' مل ', 'قرص', 'قرصين', 'حبة', 'حبتين', 'حباية', 'نص قرص',
  'زوّد', 'زود الجرعة', 'قلّل', 'قلل الجرعة', 'ضاعف', 'غيّر الجرعة', 'غير الجرعة', 'جرعة أكبر', 'جرعة أقل',
  // تفاعلات
  'تفاعل', 'يتعارض', 'يتفاعل', 'مع بعض', 'ما تاخدوش مع', 'ماتاخدوش مع',
  // أعراض وتشخيص وأحكام
  'صداع', 'دوخة', 'ألم', 'وجع', 'أعراض', 'عرض جانبي', 'آثار جانبية', 'تشخيص', 'مرض', 'ممكن يكون', 'قد يكون',
  'يدل على', 'مرتفع', 'منخفض', 'طبيعي', 'خطر', 'خطير', 'مقلق',
  // «الأفضل لحالتك»
  'الأفضل لحالتك', 'أحسن لحالتك', 'لحالتك', 'الأنسب ليك', 'أنسب دوا',
  // وقف الدوا
  'وقّف الدوا', 'وقف الدوا', 'بطّل الدوا', 'بطل الدوا', 'اوقف الدوا', 'أوقف الدوا', 'توقّف عن', 'توقف عن',
  'ما تاخدش الدوا', 'ماتاخدش الدوا', 'سيب الدوا',
  // جرعتين ورا بعض — حتى بالنفي: الجملة نفسها بتزرع الفكرة
  'جرعتين',
  // إنجليزي — أي كلمة طبية إنجليزية مش مكانها هنا
  'mg', 'dose', 'stop', 'interaction',
];

/// كلمة مسموحة **بس** لو الجملة بتحوّل للدكتور أو الصيدلي: «بديل» من غير
/// «اسأل» / «تسأل» هي نصيحة استبدال دوا — وده حكم طبي.
const bannedUnlessAsking = ['بديل'];
const askingWords = ['اسأل', 'تسأل', 'اسألي', 'تسألي'];

List<String> offendersIn(String text) => [
      for (final w in bannedInTips)
        if (RegExp(r'^[a-z]+$').hasMatch(w.trim())
            ? RegExp('\\b${w.trim()}\\b', caseSensitive: false).hasMatch(text)
            : text.contains(w))
          '«$w» في: $text',
      for (final w in bannedUnlessAsking)
        if (text.contains(w) && !askingWords.any(text.contains)) '«$w» من غير «اسأل» في: $text',
    ];

void main() {
  test('«إنت ماشي إزاي»: نفس الخطوط الحمرا على كل جملة في الكارت', () {
    final offenders = [for (final text in adherenceSampleTexts()) ...offendersIn(text)];
    expect(offenders, isEmpty);
    expect(adherenceSampleTexts(), isNotEmpty);
  });

  test('ولا كلمة ممنوعة في أي معلومة — الثابتة والقوالب بعيّناتها', () {
    final offenders = [for (final text in allTipTexts()) ...offendersIn(text)];
    expect(offenders, isEmpty);
  });

  test('«بديل» من غير «اسأل» بتقع، ومعاها بتعدّي — الحارس متجرّب', () {
    expect(offendersIn('لو الدوا خلص خد بديل بنفس المادة.'), isNotEmpty);
    expect(offendersIn('ماتاخدش بديل غير لما تسأل الصيدلي.'), isEmpty);
    expect(offendersIn('ما تاخدش جرعتين ورا بعض.'), isNotEmpty);
  });

  test('وكل جملة في الملف نفسه — عشان اللي يتضاف بعدين ما يفلتش', () {
    final source = File('lib/features/today/tips/tips_ar.dart').readAsLinesSync();
    final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final offenders = <String>[];
    for (final line in source) {
      if (line.trimLeft().startsWith('//')) continue;
      for (final m in literal.allMatches(line)) {
        offenders.addAll(offendersIn(m.group(1)!));
      }
    }
    expect(offenders, isEmpty);
  });

  test('كل غرض ليه نصيحة إلا «حاجة تانية» — ونص الجملة فيه «{name}» بالشكل اللي القالب بيبدّله', () {
    for (final p in MedicationPurpose.values) {
      final tips = purposeTips[p] ?? const [];
      if (p == MedicationPurpose.other) {
        expect(tips, isEmpty, reason: '«حاجة تانية» ما بتقولش لنا إيه');
      } else {
        expect(tips, isNotEmpty, reason: p.label);
      }
      for (final t in tips) {
        if (t.contains('{name}')) expect(t, contains('({name})'), reason: 'الاسم بين قوسين عشان يتشال نضيف');
      }
    }
    expect(generalTips, isNotEmpty);
    // مفيش نص بيتولّد: القالب الوحيد هو «{name}»، والباقي حروف مكتوبة
    expect(allTipTexts().every((t) => !t.replaceAll('{name}', '').contains('{')), isTrue);
  });
}
