import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **مفتاح الخدمة عمره ما يدخل اللوحة دي.**
///
/// اللوحة عميل عادي بمفتاح النشر، والحاجز كله في السيرفر
/// (`private.is_admin()` جوّه كل دالة في `0021_admin.sql`). مفتاح خدمة في
/// تطبيق ويب معناه إن أي حد يفتح اللوحة يقدر يقرا ويكتب أي حاجة في القاعدة
/// — الـRLS بيتخطّى خالص. ومفيش دخول مجهول كمان: الحساب لازم يبقى إنسان
/// في `private.admins`.
///
/// الاختبار بيمشي على الحزمة كلها — مش `lib/` بس — لأن مفتاح ممكن يتحطّ
/// في `web/index.html` أو في سكربت جنبه.
void main() {
  // **الكلمة نفسها متجمّعة**: لو مكتوبة حرفياً هنا، الاختبار بيمسك نفسه.
  final forbidden = <String, String>{
    ['service', 'role'].join('_'): 'مفتاح خدمة بيتخطّى الـRLS كله',
    'signIn${'Anonymously'}': 'دخول مجهول — `is_admin()` بيرفضه، ومالوش لازمة هنا',
  };

  final files = [
    for (final entity in Directory('.').listSync(recursive: true))
      if (entity is File) entity,
  ].where((f) {
    final path = f.path.replaceAll(r'\', '/');
    if (path.contains('/build/') || path.contains('/.dart_tool/')) return false;
    if (path.endsWith('pubspec.lock')) return false;
    return const ['.dart', '.html', '.js', '.json', '.yaml']
        .any((suffix) => path.endsWith(suffix));
  }).toList();

  test('فيه ملفات تتقرا أصلاً', () {
    // حارس بيمشي على فاضي مش حارس.
    expect(files.length, greaterThanOrEqualTo(10),
        reason: 'لو المسار اتغيّر، الاختبار ده بيبقى بيمرّ على فراغ');
  });

  for (final MapEntry(key: token, value: why) in forbidden.entries) {
    test('مفيش «$token» في أي ملف — $why', () {
      // **مفيش استثناء للملف ده نفسه**: الكلمة متجمّعة وقت التشغيل، فهي
      // مش مكتوبة حرفياً في أي مكان — ولا في اسم الملف.
      final offenders = <String>[];
      for (final file in files) {
        if (file.readAsStringSync().toLowerCase().contains(token.toLowerCase())) {
          offenders.add(file.path.replaceAll(r'\', '/'));
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  }
}
