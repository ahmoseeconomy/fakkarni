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

import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// الضلع الأطول بعد التصغير.
const int aiMaxSide = 1600;

/// جودة JPEG بعد التصغير.
const int aiJpegQuality = 80;

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
/// أبعاد الصورة من **ترويسة** الملف — من غير ما نفكّها كلها.
///
/// مش تحسين متأخّر: فك صورة ٢٥٦٠×١٩٢٠ بيتكلّف ثواني، وكنا بندفعها عشان
/// نجاوب سؤال «هي كبيرة أصلاً؟» اللي الترويسة بترد عليه في ميكروثانية.
/// بترجّع null لو الصيغة مش معروفة أو البايتات معطوبة.
({int width, int height})? imageSizeOf(Uint8List source) {
  try {
    final info = img.findDecoderForData(source)?.startDecode(source);
    return info == null ? null : (width: info.width, height: info.height);
  } catch (_) {
    return null;
  }
}

/// هل [shrinkForAi] هتشتغل فعلاً على البايتات دي؟
///
/// النداء بيسأل الأول عشان ما يفتحش عزلة لصورة أصلاً مش محتاجة حاجة.
bool needsShrinkForAi(Uint8List source) {
  final size = imageSizeOf(source);
  if (size == null) return false;
  return (size.width > size.height ? size.width : size.height) > aiMaxSide;
}

Uint8List shrinkForAi(Uint8List source) {
  try {
    final size = imageSizeOf(source);
    if (size == null) {
      _log('مقدرناش نقرا ترويسة الصورة — بتتبعت زي ما هي', source.length, source.length);
      return source;
    }
    if ((size.width > size.height ? size.width : size.height) <= aiMaxSide) {
      _log('${size.width}×${size.height} — أصغر من الحد، ما اتغيّرتش',
          source.length, source.length);
      return source;
    }

    final decoded = img.decodeImage(source);
    if (decoded == null) {
      _log('الترويسة قريت والصورة لأ — بتتبعت زي ما هي', source.length, source.length);
      return source;
    }

    // الاتجاه الأول، بعدين التصغير — الترتيب ده هو اللي المواصفة بتقوله،
    // والناتج بيبقى صورة واقفة صح من غير ما تعتمد على وسم إحنا هنرميه.
    final upright = img.bakeOrientation(decoded);
    final resized = upright.width >= upright.height
        ? img.copyResize(upright, width: aiMaxSide, interpolation: img.Interpolation.average)
        : img.copyResize(upright, height: aiMaxSide, interpolation: img.Interpolation.average);

    final bytes = Uint8List.fromList(img.encodeJpg(resized, quality: aiJpegQuality));
    _log('${decoded.width}×${decoded.height} → ${resized.width}×${resized.height}',
        source.length, bytes.length);
    return bytes;
  } catch (e) {
    // مش بنطبع الاستثناء كتحذير مفزع: النداء كمّل، والتكلفة بس هي اللي زادت.
    _log('التصغير وقع ($e) — بتتبعت زي ما هي', source.length, source.length);
    return source;
  }
}

void _log(String what, int beforeBytes, int afterBytes) {
  final before = (beforeBytes / 1024).round();
  final after = (afterBytes / 1024).round();
  final ratio = beforeBytes == 0 ? 1.0 : afterBytes / beforeBytes;
  developer.log(
    'shrinkForAi: $what — ${before}KB → ${after}KB (${(ratio * 100).round()}%)',
    name: 'fakkarni.ai',
  );
}
