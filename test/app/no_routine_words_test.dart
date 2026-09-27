// **الروتين اتشال — وكلامه اتشال معاه** (قرار المالك، ٢٧ سبتمبر ٢٠٢٦).
//
// بيقرا كل نص حرفي في شاشات المريض ويوقّع لو كلمة من الروتين أو الجنس
// رجعت: الصحيان / الفطار / الغدا / العشا / النوم / مواعيد يومك / روتين /
// راجل / ست. نفس شكل `no_middle_dot_test` — التعليقات برّه.
//
// المسموح بالاسم: الكتالوج الصوتي (المالك بيعيد تسجيله — الجمل اللي
// بتذكر الأكل متسجّلة في التقرير)، وقارئ الكلام (بيفهم «بعد الفطار» من
// المريض ويحوّلها لكلمة أكل — ده سماع مش عرض)، وقراية الروشتة (كلمة الورقة).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _banned = ['الصحيان', 'الفطار', 'الغدا', 'العشا', 'النوم', 'مواعيد يومك', 'روتين', 'راجل', 'ست؟', 'ولا ست'];

const _allowed = {
  'lib/domain/voice/voice_catalog.dart',
  'lib/features/voice/command_parser.dart',
  'lib/features/voice/cloud_tools.dart',
  'lib/domain/voice/arabic_dates.dart',
  'lib/domain/voice/answer_parser.dart', // بيفهم «٨ العشا» من الكلام — سماع مش عرض
  'lib/ai/prescription_reader.dart',
  // بيقرا كلام الروشتة («بعد الفطار»، «قبل النوم») ويقول اللي الورقة قالته — مش روتين
  'lib/ai/prescription_timing.dart',
  'lib/ai/prescription_reading.dart',
  'lib/ai/command_reader.dart',
  'lib/data/care/supabase_caregiver_remote.dart', // صف قديم من موبايل لسه ما اترقّاش — بيتقال بكلمته
};

Iterable<String> _stringLiterals(String source) sync* {
  final noComments = source.replaceAll(RegExp(r'//[^\n]*'), '').replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  for (final m in RegExp(r"'((?:[^'\\]|\\.)*)'|" '"((?:[^"\\\\]|\\\\.)*)"').allMatches(noComments)) {
    yield (m.group(1) ?? m.group(2))!;
  }
}

void main() {
  test('ولا كلمة روتين أو جنس في نصوص شاشات المريض', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      if (_allowed.contains(f.path)) continue;
      for (final s in _stringLiterals(f.readAsStringSync())) {
        for (final w in _banned) {
          if (s.contains(w)) offenders.add('${f.path}: «$s» ($w)');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
