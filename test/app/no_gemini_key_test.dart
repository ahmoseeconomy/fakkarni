import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **مقلوب عن قصد — ١٨ سبتمبر ٢٠٢٦.**
///
/// الاختبار ده كان بيقع لو مفتاح Gemini ظهر في `lib/` (جولة C2: المفتاح
/// خرج للسحابة، والتطبيق بينادي دالة `ai-read` بجلسة المستخدم). المالك
/// رجّع C2 في نفس اليوم — القراية بقت مباشرة من التطبيق تاني، والمفتاح رجع
/// يتترجم جوّه الـAPK والـIPA.
///
/// فالحارس اتقلب بدل ما يتشال: دلوقتي بيثبّت إن المفتاح **موجود** في نقطة
/// واحدة بس (`gemini_config.dart`) وإن النداء المباشر لجوجل في نقطة واحدة
/// بس. لما C2 ترجع (`git revert` للكوميت اللي رجّعها)، الملف ده بيترجع
/// بنفس الحركة ويرجع يقفل الباب من الناحية التانية.
///
/// **ممنوع النشر على أي متجر والمفتاح في الحالة دي** — مكتوبة في CLAUDE.md
/// جنب قاعدة الدخول المجهول، وللسبب نفسه.
const keyNames = ['GEMINI_API_KEY', 'generativelanguage.googleapis.com'];

void main() {
  List<File> libFiles() => [
        for (final e in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart')) e,
      ];

  test('المفتاح بيتقرا من مكان واحد بس — gemini_config.dart', () {
    final where = [
      for (final f in libFiles())
        if (f.readAsStringSync().contains('GEMINI_API_KEY')) f.path.replaceAll(r'\', '/'),
    ];
    expect(where, ['lib/ai/gemini_config.dart'],
        reason: 'مفتاح في ملف تاني = مكان تاني ينساه اللي هيرجّع C2');
  });

  test('النداء المباشر لجوجل في مكان واحد بس — prescription_reader.dart', () {
    final where = [
      for (final f in libFiles())
        if (f.readAsStringSync().contains('generativelanguage.googleapis.com'))
          f.path.replaceAll(r'\', '/'),
    ];
    expect(where, ['lib/ai/prescription_reader.dart']);
  });

  test('المفتاح من --dart-define وبس — مفيش قيمة مكتوبة في الكود', () {
    final config = File('lib/ai/gemini_config.dart').readAsStringSync();
    expect(config, contains("String.fromEnvironment('GEMINI_API_KEY')"));
    // مفيش أي نص شبه مفتاح حقيقي متكتوب
    expect(RegExp(r"'AIza[0-9A-Za-z_\-]{10,}'").hasMatch(config), isFalse);
    for (final f in libFiles()) {
      expect(RegExp(r"'AIza[0-9A-Za-z_\-]{10,}'").hasMatch(f.readAsStringSync()), isFalse,
          reason: f.path);
    }
  });

  test('دالة ai-read لسه في الشجرة — عشان رجوع C2 يبقى أمر واحد', () {
    expect(File('supabase/functions/ai-read/index.ts').existsSync(), isTrue);
    expect(File('supabase/migrations/0013_ai_reads.sql').existsSync(), isTrue);
  });
}
