import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C2 — التطبيق **ما عندوش مفتاح Gemini خالص**، وما بيكلّمش جوجل.
///
/// قبل كده المفتاح كان `String.fromEnvironment` — يعني متترجم جوّه كل APK
/// وIPA، واستخراجه شغل عشر دقايق. دلوقتي هو سر عند دالة `ai-read`، والتطبيق
/// بيناديها بجلسة المستخدم.
///
/// الحارس ده بيقرا `lib/` كله (حتى التعليقات — اسم المفتاح مالوش أي سبب يظهر
/// هناك) وبيقع لو حاجة من التلاتة رجعت. اللي يرجّع سطر «مؤقت» عشان يجرّب
/// بسرعة هو بالظبط اللي الحارس ده مكتوب عشانه.
const forbidden = [
  'GEMINI_API_KEY',
  'generativelanguage.googleapis.com',
  "String.fromEnvironment('GEMINI",
];

List<String> offendersIn(Iterable<(String path, String text)> files) => [
      for (final (path, text) in files)
        for (final needle in forbidden)
          if (text.contains(needle)) '$path: $needle',
    ];

void main() {
  test('مفيش مفتاح Gemini ولا عنوان جوجل ولا dart-define ليه في أي مكان تحت lib/', () {
    final files = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          (entity.path, entity.readAsStringSync()),
    ];
    expect(files, isNotEmpty);
    expect(offendersIn(files), isEmpty);
  });

  test('الحارس بيقع فعلاً على كل واحدة من التلاتة (mutation-check مكتوب)', () {
    expect(offendersIn([('a.dart', "const k = String.fromEnvironment('GEMINI_MODEL');")]), hasLength(1));
    expect(offendersIn([('b.dart', "// شغّل بـ --dart-define=GEMINI_API_KEY=...")]), hasLength(1));
    expect(offendersIn([('c.dart', "Uri.https('generativelanguage.googleapis.com', '/v1beta')")]), hasLength(1));
    expect(offendersIn([('d.dart', "final endpoint = session.endpoint;")]), isEmpty);
  });
}
