import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// أيقونات الويب متولّدة من الشعار الرسمي بـ`dart run tool/generate_icons.dart`.
///
/// **الأيقونة اللي جت مع `flutter create` هي اللي بنمنعها** — صفحة الأدمن
/// بشعار فلاتر الأزرق في التبويب معناها إن التوليد ما اتشغّلش. المقارنة
/// بالهاش، مش بالحجم: حجم مختلف ممكن يبقى صدفة.
///
/// FNV-1a 64 للملف الأصلي، متحسوب قبل ما يتكتب فوقه (٢٣ سبتمبر ٢٠٢٦).
const int stockFlutterFaviconFnv = 0xe6e1f4e735564d9c;

int fnv1a64(List<int> bytes) {
  var h = 0xcbf29ce484222325;
  for (final b in bytes) {
    h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h;
}

/// عرض وارتفاع PNG من IHDR — من غير ما نفكّ الصورة.
(int, int) pngSize(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  return (d.getUint32(16), d.getUint32(20));
}

void main() {
  const expected = {
    'web/favicon.png': 32,
    'web/favicon-16.png': 16,
    'web/apple-touch-icon.png': 180,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
  };

  for (final MapEntry(key: path, value: size) in expected.entries) {
    test('$path موجودة و$size×$size', () {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'شغّل dart run tool/generate_icons.dart');
      expect(pngSize(file.readAsBytesSync()), (size, size));
    });
  }

  test('favicon مش بتاعة فلاتر — الهاش مختلف', () {
    final bytes = File('web/favicon.png').readAsBytesSync();
    expect(fnv1a64(bytes), isNot(stockFlutterFaviconFnv),
        reason: 'الأيقونة لسه اللي جت مع flutter create');
  });

  test('الماسكابل: الحشو بلون الشعار نفسه، والشعار جوّه المنطقة الآمنة', () {
    final icon = img.decodePng(File('web/icons/Icon-maskable-512.png').readAsBytesSync())!;
    final corner = icon.getPixel(4, 4);
    // #0A4638 — لون الشعار نفسه، مش رقم تاني: فرق ٤ درجات كان هيرسم مربع
    // جوّه الدايرة اللي أندرويد بيقصّها.
    expect((corner.r, corner.g, corner.b), (0x0A, 0x46, 0x38));
    // الدهبي لازم يبقى جوّه ٨٠٪ من المنتصف — على الحافة كان هيتقصّ.
    var goldInside = 0;
    var goldOutside = 0;
    for (var y = 0; y < icon.height; y += 2) {
      for (var x = 0; x < icon.width; x += 2) {
        final p = icon.getPixel(x, y);
        if (p.r > 200 && p.g > 140 && p.g < 200 && p.b < 110) {
          final inside = x > 51 && x < 461 && y > 51 && y < 461;
          inside ? goldInside++ : goldOutside++;
        }
      }
    }
    expect(goldInside, greaterThan(0));
    expect(goldOutside, 0);
  });

  test('index.html بيربط الأيقونات المتولّدة، مش بتاعة فلاتر', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('href="favicon.png"'));
    expect(html, contains('href="favicon-16.png"'));
    expect(html, contains('href="apple-touch-icon.png"'));
    expect(html, isNot(contains('icons/Icon-192.png')), reason: 'apple-touch-icon كان بيشاور على أيقونة فلاتر');
  });

  test('manifest: الاسم والاتجاه واللغة ولون الشعار', () {
    final m = File('web/manifest.json').readAsStringSync();
    for (final needle in ['"لوحة فكرني"', '"short_name": "فكرني"', '"dir": "rtl"', '"lang": "ar"', '"theme_color": "#0A4638"', '"background_color": "#0A4638"']) {
      expect(m, contains(needle));
    }
  });
}
