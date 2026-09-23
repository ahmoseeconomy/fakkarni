import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **اللوحة حزمة مستقلة.**
///
/// اللي محتاجينه من التطبيق **متنسخ** (`theme/tokens.dart`،
/// `format/arabic_time.dart`، `model/follower_profile.dart`) وفوق كل نسخة
/// مكتوب إنها نسخة. استيراد من حزمة التطبيق كان هيجرّ معاه drift و
/// flutter_local_notifications و`dart:io` — وولا واحدة منهم بتشتغل على
/// الويب، ولا ليها لازمة في لوحة قراية.
void main() {
  final dartFiles = [
    for (final dir in ['lib', 'test'])
      for (final entity in Directory(dir).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart')) entity,
  ];

  test('فيه ملفات دارت تتقرا أصلاً', () {
    expect(dartFiles.length, greaterThanOrEqualTo(10));
  });

  test('ولا ملف بيستورد حزمة التطبيق ولا بيوصل لملفاته', () {
    const banned = ['package:fakkarni/', '../lib/', '../../lib/', '../../../lib/'];
    final offenders = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      for (final line in source.split('\n')) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) continue;
        for (final needle in banned) {
          if (line.contains(needle)) {
            offenders.add('${file.path.replaceAll(r'\', '/')} → ${line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('و`pubspec.yaml` مفيهوش `path:` على حزمة تانية', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^\s*path:', multiLine: true).hasMatch(pubspec), isFalse,
        reason: 'اعتماد محلي بيربط اللوحة بالتطبيق تاني من الباب الخلفي');
  });

  test('والنسخ مكتوب عليها إنها نسخ', () {
    const copies = [
      'lib/theme/tokens.dart',
      'lib/format/arabic_time.dart',
      'lib/model/follower_profile.dart',
      'lib/format/relative_time.dart',
    ];
    for (final path in copies) {
      final head = File(path).readAsLinesSync().take(4).join('\n');
      expect(head, contains('حزمة التطبيق'), reason: '$path من غير سطر المصدر');
    }
  });
}
