import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fakkarni/core/images/med_photo.dart';

/// صورة مولّدة في الكود — **مفيش ولا صورة حباية أو مريض حقيقية في الريبو.**
/// عليها EXIF فيه المكان (GPS) واسم الموبايل واتجاه «لفّ ٩٠».
Uint8List photoWithExif({int width = 1600, int height = 1200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(240, 240, 240));
  // علامة في الركن الشمال فوق عشان نعرف الاتجاه اتلفّ فعلاً
  img.fillRect(image, x1: 0, y1: 0, x2: 200, y2: 200, color: img.ColorRgb8(20, 120, 90));
  image.exif.imageIfd.make = 'FakkarniTestPhone';
  image.exif.imageIfd.orientation = 6; // لفّ ٩٠ مع عقارب الساعة
  image.exif.gpsIfd.gpsLatitude = 30.0444;
  image.exif.gpsIfd.gpsLongitude = 31.2357;
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

bool containsAscii(Uint8List bytes, String text) => latin1.decode(bytes, allowInvalid: true).contains(text);

void main() {
  test('الصورة المولّدة فيها EXIF فعلاً — الحارس متجرّب', () {
    final raw = photoWithExif();
    expect(containsAscii(raw, 'FakkarniTestPhone'), isTrue);
    final decoded = img.decodeJpg(raw)!;
    expect(decoded.exif.gpsIfd.hasGPSLatitude, isTrue);
    expect(decoded.exif.imageIfd.make, 'FakkarniTestPhone');
  });

  test('بعد التجهيز: مفيش EXIF خالص — لا مكان ولا اسم موبايل ولا اتجاه', () {
    final out = prepareMedPhoto(photoWithExif())!;
    expect(containsAscii(out, 'FakkarniTestPhone'), isFalse);
    expect(containsAscii(out, 'Exif'), isFalse, reason: 'مفيش APP1 Exif أصلاً');
    final decoded = img.decodeJpg(out)!;
    expect(decoded.exif.isEmpty, isTrue);
    expect(decoded.exif.gpsIfd.hasGPSLatitude, isFalse);
  });

  test('بتتصغّر لأطول ضلع ٨٠٠، والاتجاه اتلفّ في البكسل', () {
    final decoded = img.decodeJpg(prepareMedPhoto(photoWithExif())!)!;
    // ١٦٠٠×١٢٠٠ متلفّة ٩٠ = ١٢٠٠×١٦٠٠ → ٦٠٠×٨٠٠
    expect((decoded.width, decoded.height), (600, 800));
    // العلامة كانت فوق شمال؛ بعد لفّة ٩٠ مع عقارب الساعة بقت فوق يمين
    final topRight = decoded.getPixel(decoded.width - 10, 10);
    final topLeft = decoded.getPixel(10, 10);
    expect(topRight.g, greaterThan(topRight.r + 40), reason: 'العلامة الخضرا اتنقلت يمين');
    expect(topLeft.r, greaterThan(200), reason: 'الشمال بقى فاتح');
  });

  test('صورة صغيرة ما بتتكبّرش — بس الـEXIF بيتشال برضه', () {
    final decoded = img.decodeJpg(prepareMedPhoto(photoWithExif(width: 400, height: 300))!)!;
    expect(decoded.width <= 800 && decoded.height <= 800, isTrue);
    expect((decoded.width, decoded.height), (300, 400));
    expect(decoded.exif.isEmpty, isTrue);
  });

  test('بايتس بايظة → null، مش استثناء', () {
    expect(prepareMedPhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
