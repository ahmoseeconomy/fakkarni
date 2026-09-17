/// تصغير الصورة قبل ما تتبعت لـGemini (C1).
///
/// **Gemini بتحاسب بالأبعاد مش بالبايتات.** صورة كاميرا ١٢ ميجابكسل بتتقسم
/// مربعات أكتر بأضعاف من نفس الروشتة وضلعها الأطول ١٦٠٠ — نفس الورقة، نفس
/// القراءة، فاتورة مضروبة. ومكسب تاني مجاني: الرفع أسرع بكتير على شبكة
/// موبايل مصرية، وده أكتر مكان المستخدم بيستنى فيه.
///
/// الملف ده **دارت خالص** — مفيش Flutter ولا IO — عشان يتختبر في مللي
/// ثانية زي `domain/`.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// الضلع الأطول بعد التصغير.
const int aiMaxSide = 1600;

/// جودة JPEG بعد التصغير.
const int aiJpegQuality = 80;

/// أبعاد الصورة من **ترويسة** الملف فعلاً — مشي على علامات JPEG لحد SOF،
/// أو IHDR في PNG — من غير أي فك.
///
/// الحزمة عندها `startDecode`، واتقاس: **١٦٩ مللي** على JPEG ٢٥٦٠×١٩٢٠ —
/// مش «ترويسة» خالص، وده كان بيتنفّذ على خيط الواجهة في كل تصويرة (حوالي
/// ١٠ فريمات واقعة). المشي على العلامات بيقف قبل بيانات الصورة نفسها،
/// وبيتخطّى APP1 كله بطوله فمصغّرة EXIF جوّاه ما بتلخبطوش. null = صيغة
/// تانية أو بايتات معطوبة.
({int width, int height})? quickImageSizeOf(Uint8List b) => _jpegSize(b) ?? _pngSize(b);

({int width, int height})? _jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // بايت حشو
      continue;
    }
    // علامات من غير طول
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      i += 2;
      continue;
    }
    // بداية البيانات أو نهاية الملف قبل ما نلاقي SOF
    if (marker == 0xDA || marker == 0xD9) return null;
    final isSof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
    if (isSof) {
      return (width: (b[i + 7] << 8) | b[i + 8], height: (b[i + 5] << 8) | b[i + 6]);
    }
    i += 2 + ((b[i + 2] << 8) | b[i + 3]);
  }
  return null;
}

({int width, int height})? _pngSize(Uint8List b) {
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length < 24) return null;
  for (var i = 0; i < 8; i++) {
    if (b[i] != sig[i]) return null;
  }
  int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (width: be(16), height: be(20));
}

/// الأبعاد بأي طريقة: الترويسة السريعة الأول، وبعدين الحزمة (WebP، GIF…).
/// التانية **تقيلة** — مكانها جوّه العزلة بس.
({int width, int height})? imageSizeOf(Uint8List source) {
  final quick = quickImageSizeOf(source);
  if (quick != null) return quick;
  try {
    final info = img.findDecoderForData(source)?.startDecode(source);
    return info == null ? null : (width: info.width, height: info.height);
  } catch (_) {
    return null;
  }
}

/// سؤال خيط الواجهة: نفتح عزلة ولا لأ؟ **رخيص بجد** — ترويسة بس.
///
/// * أبعاد معروفة وصغيرة → لأ، الصورة بتتبعت زي ما هي.
/// * أبعاد معروفة وكبيرة → آه.
/// * صيغة مش JPEG ولا PNG → آه برضه: العزلة هي اللي تحاول بالحزمة، مش
///   الخيط ده. أسوأ حالة عزلة اتفتحت ورجّعت «ما اتغيّرش».
bool mayNeedShrinkForAi(Uint8List source) {
  if (source.length < 4) return false;
  final size = quickImageSizeOf(source);
  if (size == null) return true;
  return (size.width > size.height ? size.width : size.height) > aiMaxSide;
}

/// اللي حصل للصورة: البايتات الجديدة (null = «ما اتغيّرش») + وصف وحجمين
/// للّوج. **الملف ده ما بيطبعش حاجة بنفسه**: الشغل بيتعمل جوّه عزلة
/// `compute`، واللي بيتطبع هناك ما بيوصلش ترمنال `flutter run`. فالتقرير
/// بيرجع مع البايتات، و`generate` هو اللي بيطبعه بـ`debugPrint` على العزلة
/// الرئيسية — نفس قناة باقي سطور Gemini.
///
/// الـnull في [bytes] مش تفصيلة: البايتات اللي بتعدّي بين عزلتين بتتنسخ،
/// فـ`identical` على الناحية التانية دايماً false — ومن غيره صورة PNG رجعت
/// زي ما هي كانت هتتبعت بنوع `image/jpeg`.
typedef ShrinkReport = ({Uint8List? bytes, String what, int beforeBytes, int afterBytes});

/// سطر اللوج الواحد: «٢٥٦٠×١٩٢٠ → ١٦٠٠×١٢٠٠ — 584KB → 418KB (72%)».
String describeShrink(ShrinkReport r) {
  final before = (r.beforeBytes / 1024).round();
  final after = (r.afterBytes / 1024).round();
  final ratio = r.beforeBytes == 0 ? 100 : (r.afterBytes / r.beforeBytes * 100).round();
  return 'shrinkForAi: ${r.what} — ${before}KB → ${after}KB ($ratio%)';
}

/// تقرير الصورة اللي البوّابة قالت إنها مش محتاجة عزلة — من الترويسة، رخيص.
ShrinkReport unchangedShrinkReport(Uint8List source) {
  final size = quickImageSizeOf(source);
  return _unchanged(
    source,
    size == null ? 'فاضية — بتتبعت زي ما هي' : '${size.width}×${size.height} — أصغر من الحد، ما اتغيّرتش',
  );
}

ShrinkReport _unchanged(Uint8List source, String what) =>
    (bytes: null, what: what, beforeBytes: source.length, afterBytes: source.length);

/// بترجّع الصورة مصغّرة لـ[aiMaxSide] على ضلعها الأطول، أو **هي بنفسها**
/// لو مش محتاجة تصغير أو مقدرناش نفكّها.
///
/// القواعد اللي مش بتتكسر:
/// * **ما بتكبّرش أبداً.** صورة ضلعها الأطول أصلاً ≤ [aiMaxSide] بترجع زي ما
///   هي بالبايت — وده كمان بيحافظ على وسم الاتجاه بتاعها جوّه ملفها.
/// * **الاتجاه بيتطبّق قبل التصغير.** روشتة اتصوّرت بالعرض جوّه ملفها وسم
///   EXIF بيقول «لفّها»؛ إحنا بنعيد الترميز، والـJPEG اللي بنطلعه مش شايل
///   الوسم ده — فلو ما لفّناهاش بإيدينا بتوصل Gemini مقلوبة والقراءة بتبوظ.
///   ([img.bakeOrientation] بيلف البكسل نفسه وبيشيل الوسم.)
/// * **ما بترميش أبداً.** ده طريق بين مريض ودواه: بايتات معطوبة، صيغة مش
///   معروفة، أي استثناء — بترجع الأصل زي ما هو والنداء بيكمل. أسوأ حالة
///   إننا دفعنا تمن صورة كبيرة، مش إن الروشتة ما اتقرتش.
Uint8List shrinkForAi(Uint8List source) => shrinkForAiOrNull(source).bytes ?? source;

/// الشغل نفسه — ودي اللي `compute` بتناديها. نفس قواعد [shrinkForAi].
ShrinkReport shrinkForAiOrNull(Uint8List source) {
  try {
    final size = imageSizeOf(source);
    if (size == null) return _unchanged(source, 'مقدرناش نقرا أبعاد الصورة — بتتبعت زي ما هي');
    if ((size.width > size.height ? size.width : size.height) <= aiMaxSide) {
      return _unchanged(source, '${size.width}×${size.height} — أصغر من الحد، ما اتغيّرتش');
    }

    final decoded = img.decodeImage(source);
    if (decoded == null) return _unchanged(source, 'الترويسة قريت والصورة لأ — بتتبعت زي ما هي');

    // الاتجاه الأول، بعدين التصغير — الترتيب ده هو اللي المواصفة بتقوله،
    // والناتج بيبقى صورة واقفة صح من غير ما تعتمد على وسم إحنا هنرميه.
    final upright = img.bakeOrientation(decoded);
    final resized = upright.width >= upright.height
        ? img.copyResize(upright, width: aiMaxSide, interpolation: img.Interpolation.average)
        : img.copyResize(upright, height: aiMaxSide, interpolation: img.Interpolation.average);

    final bytes = Uint8List.fromList(img.encodeJpg(resized, quality: aiJpegQuality));
    return (
      bytes: bytes,
      what: '${decoded.width}×${decoded.height} → ${resized.width}×${resized.height}',
      beforeBytes: source.length,
      afterBytes: bytes.length,
    );
  } catch (e) {
    // النداء بيكمّل، والتكلفة بس هي اللي زادت — والسبب بيوصل اللوج.
    return _unchanged(source, 'التصغير وقع ($e) — بتتبعت زي ما هي');
  }
}
