import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fakkarni/core/images/shrink_for_ai.dart';

/// C1 — الصورة بتتصغّر قبل ما تتبعت، لأن Gemini بتحاسب بالأبعاد.
///
/// الاختبار ده بيبني صور حقيقية ويقرا **بكسل** الناتج — مش الوسوم. وسم
/// الاتجاه ممكن يبقى مظبوط والصورة مقلوبة، وده بالظبط اللي بيبوّظ القراءة.

/// صورة بيضا فيها مربع أحمر في ركن معيّن — عشان نعرف الصورة لفّت ولا لأ.
img.Image _marked(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(image, x1: 0, y1: 0, x2: width ~/ 8, y2: height ~/ 8,
      color: img.ColorRgb8(230, 20, 20));
  return image;
}

bool _isRed(img.Pixel p) => p.r > 180 && p.g < 110 && p.b < 110;
bool _isWhite(img.Pixel p) => p.r > 180 && p.g > 180 && p.b > 180;

void main() {
  test('صورة كاميرا ٤٠٣٢×٣٠٢٤ بترجع ضلعها الأطول ١٦٠٠', () {
    // من غير علامة ولا ملء: الاختبار ده على الأبعاد بس، وبناء ١٢ ميجابكسل
    // ومليها وترميزها بيتكلّف ثواني في الاختبار نفسه.
    final source = Uint8List.fromList(img.encodeJpg(img.Image(width: 4032, height: 3024)));

    final out = img.decodeImage(shrinkForAi(source))!;

    expect(out.width > out.height ? out.width : out.height, aiMaxSide);
    // النسبة محفوظة — مش بنمطّ الورقة
    expect(out.width / out.height, closeTo(4032 / 3024, 0.01));
  });

  test('صورة ٨٠٠×٦٠٠ بترجع هي بنفسها — ما بنكبّرش وما بنعيدش ترميز', () {
    final source = Uint8List.fromList(img.encodeJpg(_marked(800, 600), quality: 92));

    final out = shrinkForAi(source);

    // نفس الكائن، مش نسخة متساوية: يعني ولا بايت اتغيّر ووسم الاتجاه
    // بتاعها لسه جوّه ملفها.
    expect(identical(out, source), isTrue);
  });

  test('صورة اتصوّرت بالعرض (EXIF 6) بترجع واقفة — بالبكسل مش بالوسم', () {
    // ٢٠٠٠ × ١٠٠٠ عشان تعدّي حد التصغير وتتعاد ترميزها فعلاً
    final landscape = _marked(2000, 1000)..exif.imageIfd.orientation = 6;
    final source = Uint8List.fromList(img.encodeJpg(landscape, quality: 92));

    final out = img.decodeImage(shrinkForAi(source))!;

    // اتلفّت ربع لفة: الضلعين اتبدلوا
    expect(out.height, greaterThan(out.width), reason: 'المفروض بقت طولية');
    expect(out.height, aiMaxSide);

    // والعلامة مشيت من فوق-يمين الملف لفوق-شمال الشاشة... يعني بالبكسل:
    // مربع فوق-الشمال في المصدر بيروح فوق-اليمين بعد لفة ٩٠ مع عقرب الساعة.
    expect(_isRed(out.getPixel(out.width - 20, 20)), isTrue, reason: 'العلامة فوق-يمين');
    expect(_isWhite(out.getPixel(20, 20)), isTrue, reason: 'فوق-شمال بقى فاضي');

    // الوسم نفسه اتشال — الـJPEG اللي طلعناه مش محتاجه، وسيبه معناه لفّة تانية
    expect(out.exif.imageIfd.orientation, anyOf(isNull, 1));
  });

  test('من غير وسم اتجاه العلامة ما بتتحركش — الضابط اللي بيثبت إن اللفّة مش عشوائية', () {
    final source = Uint8List.fromList(img.encodeJpg(_marked(2000, 1000), quality: 92));

    final out = img.decodeImage(shrinkForAi(source))!;

    expect(out.width, greaterThan(out.height));
    expect(_isRed(out.getPixel(20, 20)), isTrue, reason: 'فضلت فوق-شمال');
  });

  test('بايتات معطوبة بترجع زي ما هي ومش بترمي', () {
    final rubbish = Uint8List.fromList(List<int>.generate(5000, (i) => i % 251));

    late Uint8List out;
    expect(() => out = shrinkForAi(rubbish), returnsNormally);
    expect(identical(out, rubbish), isTrue);
  });

  group('سؤال خيط الواجهة — ترويسة بس، من غير فك', () {
    test('JPEG: الأبعاد من علامة SOF، حتى لو قبلها APP1 فيه EXIF', () {
      final plain = Uint8List.fromList(img.encodeJpg(img.Image(width: 2000, height: 1000)));
      final withExif = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 1234, height: 567)..exif.imageIfd.orientation = 6),
      );

      expect(quickImageSizeOf(plain), (width: 2000, height: 1000));
      // أبعاد الملف نفسه — الاتجاه ما بيغيّرش الضلع الأطول
      expect(quickImageSizeOf(withExif), (width: 1234, height: 567));
    });

    test('PNG: الأبعاد من IHDR', () {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 1700, height: 300)));
      expect(quickImageSizeOf(png), (width: 1700, height: 300));
    });

    test('بايتات معطوبة أو JPEG مقطوع → null، ومفيش رمي ولا قراية برّه الحدود', () {
      expect(quickImageSizeOf(Uint8List.fromList(List<int>.generate(5000, (i) => i % 251))), isNull);
      expect(quickImageSizeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isNull);
      // علامة بطول بيشاور برّه الملف
      expect(quickImageSizeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0])), isNull);
    });

    test('البوّابة: صغيرة لأ، كبيرة آه، صيغة مش معروفة آه (العزلة تقرر)، فاضية لأ', () {
      expect(mayNeedShrinkForAi(Uint8List.fromList(img.encodeJpg(img.Image(width: 800, height: 600)))), isFalse);
      expect(mayNeedShrinkForAi(Uint8List.fromList(img.encodeJpg(img.Image(width: 2560, height: 1920)))), isTrue);
      expect(mayNeedShrinkForAi(Uint8List.fromList(List<int>.generate(5000, (i) => i % 251))), isTrue);
      expect(mayNeedShrinkForAi(Uint8List(0)), isFalse);
    });

    test('تقرير العزلة: bytes = null لما مفيش تغيير، والحجمين والوصف دايماً', () {
      final small = Uint8List.fromList(img.encodeJpg(img.Image(width: 800, height: 600)));
      final big = Uint8List.fromList(img.encodeJpg(img.Image(width: 2000, height: 1000)));
      final untouched = shrinkForAiOrNull(small);
      expect(untouched.bytes, isNull);
      expect(untouched.afterBytes, small.length);
      expect(describeShrink(untouched), contains('800×600'));

      final shrunk = shrinkForAiOrNull(big);
      expect(shrunk.bytes, isNotNull);
      expect(shrunk.beforeBytes, big.length);
      expect(shrunk.afterBytes, shrunk.bytes!.length);
      expect(describeShrink(shrunk), contains('2000×1000 → 1600×800'));
    });
  });

  test('بايتات فاضية بترجع زي ما هي', () {
    final empty = Uint8List(0);
    expect(identical(shrinkForAi(empty), empty), isTrue);
  });
}
