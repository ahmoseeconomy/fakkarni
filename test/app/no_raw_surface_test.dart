import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الأسطح بتتاخد من الرموز الدلالية، مش بالإيد.
///
/// قبل الجولة دي كان فيه ١٣٣ موضع بيختار لونه بنفسه (`F.ivory` ٦٩ مرة،
/// `Colors.white` ٦٤)، فتغيير أرضية التطبيق كان شغل يوم — وده السبب
/// الحقيقي إن الأرضية فضلت عاجي والمخططات بيضا.
///
/// دلوقتي الشاشة بتقول **دور** السطح: `pageGround` / `cardGround` /
/// `railGround` / `fieldGround` / `dialogGround` / `onDark`، والقيم في
/// `tokens.dart` وحده. تغيير أرضية التطبيق كله بقى سطرين هناك.
///
/// الاختبار بيقرا الكود زي حارس النقطة وحارس الأحمر.
void main() {
  test('مفيش Colors.white ولا F.ivory* برّه tokens.dart', () {
    // `PdfColors.white` لوحة حزمة الـPDF نفسها، مش أسطحنا — بتتستثنى بالاسم.
    final raw = RegExp(r'(?<!Pdf)Colors\.white|F\.ivory\w*|F\.white\b|F\.cardGrey\b|F\.quietGrey\b');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == 'lib/core/theme/tokens.dart') continue; // التعريف نفسه
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') || line.startsWith('*')) continue;
        if (raw.hasMatch(line)) offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل السطح الدلالي: pageGround / cardGround / railGround / '
          'fieldGround / dialogGround / onDark',
    );
  });
}
