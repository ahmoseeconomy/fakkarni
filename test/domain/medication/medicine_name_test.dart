// «لا» ظهرت دوا على «يومك» — كلمة إجابة لوحدها عمرها ما تبقى اسم دوا.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/medication/medicine_name.dart';
import 'package:fakkarni/features/voice/command_parser.dart';
import 'package:fakkarni/features/voice/cloud_tools.dart';
import 'package:fakkarni/ai/command_reader.dart';

void main() {
  group('isNotAMedicineName', () {
    for (final w in ['لا', 'لأ', 'لاء', 'أيوه', 'ايوه', 'آه', 'اه', 'مش عارف', 'مش عارفة', 'نعم', 'تمام', 'لا مش عايز', 'بعدين', '', '  ', 'عدّي']) {
      test('«$w» مش اسم', () => expect(isNotAMedicineName(w), isTrue));
    }
    for (final w in ['Concor 5mg', 'كونكور', 'بنادول', 'Eltroxin', 'دوا الضغط', 'لازكس', 'Augmentin 1g']) {
      test('«$w» اسم', () => expect(isNotAMedicineName(w), isFalse));
    }
  });

  group('القارئ المحلي ما بيطلّعش «لا» اسم', () {
    for (final s in ['ضيف دوا لا', 'ضيفلي دوا أيوه', 'ضيف دوا مش عارف', 'ضيف دوا آه', 'ضيف دوا لا مش عايز']) {
      test(s, () {
        final c = parseCommand(s, now: DateTime(2026, 9, 27, 10));
        expect(c.intent, CommandIntent.addMed);
        expect(c.medWords, isNull);
      });
    }
    test('والاسم الحقيقي بيعدّي', () {
      expect(parseCommand('ضيف دوا كونكور', now: DateTime(2026, 9, 27, 10)).medWords, 'كونكور');
    });
  });

  test('القاعدة نفسها بترفض «لا» اسم — آخر حاجز من أي باب', () {
    // الحاجز في medication_repository قبل أي كتابة؛ هنا بنثبت الحكم اللي بيستعمله
    expect(medicineNameOrNull('لا'), isNull);
    expect(medicineNameOrNull(' Concor '), 'Concor');
  });

  test('السحابة بترجّع «لا» اسم → مش مفهوم، مش دوا', () {
    final c = commandFromCloudTool(const CloudTool(tool: 'add_medication', args: {'name': 'لا'}), now: DateTime(2026, 9, 27, 10));
    expect(c, isNull);
  });
}
