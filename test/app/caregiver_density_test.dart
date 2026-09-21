import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';

/// **تدرّج الابن جنب تدرّج الأب — مش بدالُه.**
///
/// المريض ~٧٢ سنة بنضارة قراية وبيستعمل التطبيق تحت ضغط؛ الابن شاب شغّال
/// بيبص تلات ثواني بين اجتماعين. الاتنين على نفس الهوية بالظبط — نفس
/// اللوحة ونفس الخطوط العربية ونفس الـRTL — بس مش على نفس الكثافة.
///
/// الملف ده بابين، والاتنين بيقعوا بصوت:
///  ١. **مقاسات الأب ما اتغيّرتش.** القيَم متثبّتة برقمها هنا، فأي تصغير
///     في `tokens.dart` بيوقّع الاختبار بدل ما يعدّي في مراجعة.
///  ٢. **مقاسات الابن ما بتخرجش من `lib/features/care/`.** أي `F.care…`
///     أو ودجت من `caregiver_ui.dart` في شاشة مريض = أحمر.
void main() {
  /// كل ملفات `lib/` بمسارها النسبي.
  Map<String, String> libFiles() {
    final out = <String, String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      out[entity.path.replaceAll(r'\', '/')] = entity.readAsStringSync();
    }
    return out;
  }

  group('حدود الأب ما اتلمستش', () {
    // **الأرقام مكتوبة بالحرف عن قصد.** قراية القيمة من `F` هنا كانت
    // هتخلّي الاختبار يوافق على أي تغيير — بيقارن الحاجة بنفسها.
    test('الحد الأدنى للنص والمتن وهدف اللمس زي ما هم', () {
      expect(F.minTextSize, 17.0);
      expect(F.minBodySize, 20.0);
      expect(F.minTapTarget, 56.0);
      expect(F.primaryButtonHeight, 64.0);
    });

    test('نمط كبار السن زي ما هو', () {
      expect(F.elderTextSize, 24.0);
      expect(F.elderTitleSize, 34.0);
      expect(F.elderNameSize, 32.0);
      expect(F.elderPrimaryButtonHeight, 80.0);
      expect(F.elderSecondaryButtonHeight, 64.0);
    });

    test('سلّم عناوين الشاشات زي ما هو', () {
      expect(F.screenTitleSize, 25.0);
      expect(F.subtitleSize, 23.0);
      expect(F.sectionHeadSize, 19.0);
      expect(F.gap, 16.0);
    });
  });

  group('تدرّج الابن: أصغر، ومحبوس في مكانه', () {
    test('أكثف من تدرّج الأب فعلاً — وإلا مفيش داعي له', () {
      expect(F.careBodySize, lessThan(F.minBodySize));
      expect(F.careTextSize, lessThan(F.minTextSize));
      expect(F.careTapTarget, lessThan(F.minTapTarget));
      // وبرضه في المدى القياسي للمنصّات، مش صغير عشان يصغّر
      expect(F.careBodySize, greaterThanOrEqualTo(15.0));
      expect(F.careTapTarget, greaterThanOrEqualTo(44.0));
      expect(F.careMinTextSize, greaterThanOrEqualTo(12.0));
    });

    test('ولا `F.care…` برّه lib/features/care/', () {
      final offenders = <String>[];
      for (final MapEntry(key: path, value: source) in libFiles().entries) {
        if (path.startsWith('lib/features/care/')) continue;
        // `tokens.dart` هو اللي بيعرّفهم — التعريف مش استعمال.
        if (path == 'lib/core/theme/tokens.dart') continue;
        for (final m in RegExp(r'F\.care[A-Za-z]*').allMatches(source)) {
          offenders.add('$path → ${m.group(0)}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'مقاسات الابن على شاشة مريض — الحدود دي اتكتبت لراجل '
            'عنده ٧٢ سنة:\n${offenders.join('\n')}',
      );
    });

    test('ولا ودجت من caregiver_ui برّه lib/features/care/', () {
      const widgets = [
        'careAppBar',
        'CareCard',
        'CareHead',
        'CarePanel',
        'CareTextAction',
        'CareStateMark',
      ];
      final offenders = <String>[];
      for (final MapEntry(key: path, value: source) in libFiles().entries) {
        if (path.startsWith('lib/features/care/')) continue;
        for (final name in widgets) {
          if (RegExp('\\b$name\\b').hasMatch(source)) offenders.add('$path → $name');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('وشاشات الابن ما بتستعملش حدود الأب', () {
      final offenders = <String>[];
      for (final MapEntry(key: path, value: source) in libFiles().entries) {
        if (!path.startsWith('lib/features/care/')) continue;
        for (final m in RegExp(r'F\.(minTextSize|minBodySize|minTapTarget|elder[A-Za-z]*)')
            .allMatches(source)) {
          offenders.add('$path → ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'شاشة الابن بمقاس الأب — الكثافة نصّها إن ده ما يحصلش:\n'
              '${offenders.join('\n')}');
    });
  });
}
