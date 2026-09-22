// **اختبار البرومبت على صور حقيقية — بينده Gemini فعلاً، وبيتخطّى لوحده.**
//
// المواصفة طلبت البرومبت يتجرّب على تلات علب وشريط. **مفيش ولا صورة علبة
// في المستودع ومفيش مفتاح هنا**، فالاختبار ده بيتخطّى — بس هو مكتوب عشان
// أول ما الصور تبقى موجودة يشتغل بأمر واحد من غير ما حد يكتب حاجة:
//
//   GEMINI_API_KEY=… PACKAGE_PHOTOS=test/assets/packages \
//     flutter test test/ai/package_prompt_live_test.dart
//
// **والصور عمرها ما تتكوميت**: `test/assets/packages/` في `.gitignore`.
// علبة لوحدها مفيهاش اسم مريض، بس شريط متصرّف من صيدلية ممكن يكون عليه
// ستيكر باسمه — والقاعدة أسهل ما تتبع لما تبقى «ولا صورة».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/package_reader.dart';

/// كلمات لو ظهرت في أي حقل معناها إن العلبة اتحوّلت لوصفة.
const _dosingWords = [
  'daily', 'twice', 'thrice', 'every', 'hours', 'hour', 'before meal', 'after meal',
  'مرة', 'مرتين', 'يومي', 'يومياً', 'كل ١٢', 'كل 12', 'قبل الأكل', 'بعد الأكل',
];

void main() {
  final key = Platform.environment['GEMINI_API_KEY'];
  final folder = Platform.environment['PACKAGE_PHOTOS'];

  final images = folder == null || !Directory(folder).existsSync()
      ? const <File>[]
      : Directory(folder)
          .listSync()
          .whereType<File>()
          .where((f) => const ['.jpg', '.jpeg', '.png', '.heic']
              .contains(f.path.toLowerCase().substring(f.path.lastIndexOf('.'))))
          .toList();

  final skip = key == null || key.isEmpty
      ? 'مفيش GEMINI_API_KEY — الاختبار ده بينده Gemini فعلاً'
      : images.isEmpty
          ? 'مفيش صور في PACKAGE_PHOTOS — حطّ علب وشريط في فولدر وشغّله'
          : null;

  test('البرومبت على صور علب حقيقية: اسم أو فراغ — وولا موعد', () async {
    final reader = GeminiPackageReader(GeminiConfig(apiKey: key!));
    var named = 0;
    for (final file in images) {
      final reading = await reader.read(await file.readAsBytes());
      final fields = [
        reading.nameField,
        reading.ingredientField,
        reading.formField,
        reading.packSizeField,
      ].whereType<String>().toList();

      // **أهم تأكيد**: ولا حقل فيه كلام عن جرعة ولا ميعاد.
      for (final field in fields) {
        for (final word in _dosingWords) {
          expect(field.toLowerCase(), isNot(contains(word.toLowerCase())),
              reason: '${file.path}: «$field» فيه كلام جرعات');
        }
      }

      // يا اسم واضح، يا «مقدرناش نقرا» — مفيش حالة تالتة.
      if (reading.nothingClear) {
        // ignore: avoid_print
        print('PKG: ${file.path} → مش واضحة (${reading.unclear.join('، ')})');
      } else {
        named++;
        // ignore: avoid_print
        print('PKG: ${file.path} → ${reading.nameField} | '
            '${reading.ingredientField ?? '—'} | ${reading.formField ?? '—'}');
      }
    }
    // علبة واضحة في الصورة لازم تتقرا — وإلا البرومبت مش شغّال أصلاً.
    expect(named, greaterThan(0), reason: 'ولا صورة اتقرا منها اسم');
  }, skip: skip);
}
