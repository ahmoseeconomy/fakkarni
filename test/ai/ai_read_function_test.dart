import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C2 — البرومبت والـschema وحدود الصرف بقوا في دالة السحابة، فحراسهم بقوا
/// بيقروا ملفها — زي `push_channel_test` و`server_grace_sql_test`.
///
/// قبل C2 اختبار Dart كان بيثبّت إن تعليمة قارئ التحاليل بتمنع النطاق
/// والتفسير والنصيحة (القاعدة ٦)، وإن الـschema مفيهوش مكان ليهم. التعليمة
/// اتنقلت؛ لو الحارس ما اتنقلش معاها، أول تعديل «بريء» في الـTypeScript كان
/// هيفتح قناة نصيحة طبية من غير ما ولا اختبار يقع.
void main() {
  final source = File('supabase/functions/ai-read/index.ts').readAsStringSync();

  String block(String tag) {
    final start = source.indexOf('// <$tag>');
    final end = source.indexOf('// </$tag>');
    expect(start, greaterThanOrEqualTo(0), reason: 'العلامة <$tag> اتشالت من الدالة');
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  test('تعليمة قارئ التحاليل بتمنع النطاق والعلامات والتفسير والنصيحة — ومربوطة بالنوع lab', () {
    final instruction = block('lab-system-instruction');
    for (final phrase in [
      'not a doctor',
      'Do NOT return reference ranges',
      'Do NOT return H/L',
      'Do NOT interpret, diagnose, recommend, or advise',
      'Never say a value is high, low, normal, abnormal',
      'Never suggest seeing a doctor',
      'Never guess a digit',
    ]) {
      expect(instruction, contains(phrase));
    }
    expect(
      source,
      contains('lab: { prompt: LAB_PROMPT, schema: LAB_SCHEMA, systemInstruction: LAB_SYSTEM_INSTRUCTION }'),
      reason: 'التعليمة موجودة بس مش متبعتة مع نوع lab',
    );
  });

  test('schema التحليل مفيهوش مكان لنطاق مرجعي ولا علامة ولا تفسير ولا نص حر', () {
    final schema = block('lab-schema')
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n')
        .toLowerCase();
    for (final forbidden in ['range', 'reference', 'flag', 'interpret', 'normal', 'comment', 'note']) {
      expect(schema.contains(forbidden), isFalse, reason: forbidden);
    }
  });

  test('برومبت الروشتة: ما تخمّنش، ما تنصحش، والغامض «اسأل الصيدلي»', () {
    final prompt = block('prescription-prompt');
    for (final phrase in [
      'Extract ONLY what is literally written. Never guess',
      'Do not give medical advice',
      'مش متأكد — اسأل الصيدلي',
      'a missing duration is not an error',
    ]) {
      expect(prompt, contains(phrase));
    }
  });

  test('الحدّين ثوابت مسمّاة فوق، والجملة اللي التطبيق بيعرضها بالحرف', () {
    expect(source, contains('const DAILY_CAP_PER_USER = 20;'));
    expect(source, matches(RegExp(r'const DAILY_CAP_GLOBAL = \d+;')));
    expect(source, contains("'وصلت لحد القراءات النهارده — جرّب بكرة'"));
  });

  test('المفتاح: من سر الدالة، في header وبس — ولا سطر لوج ولا رد بيلمسه', () {
    expect(source, contains("Deno.env.get('GEMINI_API_KEY')"));
    expect(source, contains("'x-goog-api-key': key"));
    for (final line in source.split('\n')) {
      final code = line.trimLeft();
      if (code.startsWith('//')) continue;
      if (code.contains('console.') || code.contains('json(') || code.contains('new Response(')) {
        expect(code.contains('geminiKey'), isFalse, reason: 'المفتاح في لوج أو رد: $code');
      }
    }
    // وعمره ما يبقى في الرابط
    expect(source.contains('?key='), isFalse);
  });

  test('من غير أي import — بتتلصق في محرر اللوحة زي escalate', () {
    final imports = source.split('\n').where((l) => RegExp(r'^\s*import\s').hasMatch(l));
    expect(imports, isEmpty);
  });

  test('العميل ما يقدرش يبعت برومبت: الطلب بيتقرا منه kind وimage وmime وبس', () {
    expect(source, contains('input.kind'));
    for (final field in ['input.prompt', 'input.schema', 'input.model', 'input.systemInstruction']) {
      expect(source.contains(field), isFalse, reason: field);
    }
  });
}
