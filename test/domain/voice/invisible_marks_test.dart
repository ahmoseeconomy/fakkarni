// علامات الاتجاه المخفية (قياس ٦ أكتوبر ٢٠٢٦): متعرّف الآيفون بيحطها حوالين
// الأرقام اللاتيني في كلام عربي، ومحدش بيشوفها على الشاشة — و`parseTime`
// و`contains('كل يوم')` كانوا بيقعوا عليها في صمت. الشيل في مكان واحد،
// [spokenAnswer]، فكل مايك بيعدّي منه.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/answer_parser.dart';
import 'package:fakkarni/domain/voice/nlu/nlu.dart';
import 'package:fakkarni/domain/voice/nlu/normalize.dart';

void main() {
  // ممثّل من كل مدى في القايمة، وطرفيه
  const marks = {
    'ZWSP U+200B': '\u200B',
    'ZWNJ U+200C': '\u200C',
    'ZWJ U+200D': '\u200D',
    'LRM U+200E': '\u200E',
    'RLM U+200F': '\u200F',
    'LRE U+202A': '\u202A',
    'PDF U+202C': '\u202C',
    'RLO U+202E': '\u202E',
    'LRI U+2066': '\u2066',
    'PDI U+2069': '\u2069',
    'ALM U+061C': '\u061C',
  };

  /// قبل / بعد / جوّه (جنب المسافة، وجوّه الكلمة أو الرقم).
  List<String> placements(String phrase, String m) {
    final space = phrase.indexOf(' ');
    return [
      '$m$phrase',
      '$phrase$m',
      '$m$phrase$m',
      if (space > 0) '${phrase.substring(0, space)}$m${phrase.substring(space)}',
      if (space > 0) '${phrase.substring(0, space + 1)}$m${phrase.substring(space + 1)}',
      '${phrase.substring(0, 2)}$m${phrase.substring(2)}', // جوّه أول كلمة
    ];
  }

  test('stripInvisibleMarks بتشيل كل مدى في القايمة، ومش بتلمس غيره', () {
    for (final m in marks.values) {
      expect(stripInvisibleMarks('ا$mب'), 'اب');
    }
    // الحدود برّه القايمة بتفضل: U+200A (مسافة رفيعة) وU+2010 (شرطة) وU+202F
    expect(stripInvisibleMarks('\u200A\u2010\u202F\u2065'), '\u200A\u2010\u202F\u2065');
  });

  group('الجمل اللي الآيفون رجّعها، بالعلامات', () {
    marks.forEach((name, m) {
      test('«10:00 الصبح» — $name', () {
        for (final s in placements('10:00 الصبح', m)) {
          expect(parseTime(spokenAnswer(s)), const SpokenTime(10, 0), reason: s.runes.map((r) => r.toRadixString(16)).join(' '));
        }
      });
      test('«كل يوم» — $name', () {
        for (final s in placements('كل يوم', m)) {
          expect(spokenAnswer(s), 'كل يوم', reason: s.runes.map((r) => r.toRadixString(16)).join(' '));
        }
      });
      test('«مرتين» — $name', () {
        for (final s in placements('مرتين', m)) {
          final r = understandUtteranceAs(NluIntent.addMedication, 'ضيف دوا X ${spokenAnswer(s)}', now: DateTime(2026, 10, 6));
          expect(r.perDay, 2, reason: s.runes.map((r) => r.toRadixString(16)).join(' '));
        }
      });
    });
  });

  test('«10 الصبح» و«تسعة ونص بالليل» بالعلامات', () {
    expect(parseTime(spokenAnswer('\u200E10\u200E الصبح')), const SpokenTime(10, 0));
    expect(parseTime(spokenAnswer('\u200Fتسعة ونص بالليل.')), const SpokenTime(21, 30));
  });
}
