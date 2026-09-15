import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// إعداد `flutter_launcher_icons` في pubspec.yaml بيشاور على ملفات حقيقية.
///
/// المولّد ما بيتشغّلش في كل build — بيتشغّل بالإيد. فمسار اتغيّر لملف مش
/// موجود ما بيوقّعش حاجة لحد ما حد يشغّله قبل رفع نسخة، وساعتها يا إما
/// بيقع يا إما بيطلع الأيقونة القديمة في صمت.
void main() {
  final config = (loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap)['flutter_launcher_icons'] as YamlMap?;

  test('فيه إعداد flutter_launcher_icons', () {
    expect(config, isNotNull);
  });

  for (final key in ['image_path', 'adaptive_icon_foreground']) {
    test('$key بيشاور على ملف موجود', () {
      final path = config?[key];
      expect(path, isA<String>(), reason: '$key مش مكتوب');
      expect(File(path as String).existsSync(), isTrue, reason: '$key → $path مش موجود');
    });
  }
}
