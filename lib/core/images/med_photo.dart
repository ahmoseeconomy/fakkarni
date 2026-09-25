import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// **صورة الدوا — تتصغّر ويتشال منها أي بيان قبل ما تتحفظ.** دارت نقية،
/// من غير Flutter: بتتنده جوّه `compute` عشان فكّ صورة كاميرا بياخد ثواني.
///
/// * أطول ضلع ≤ [medPhotoMaxSide] — صورة علبة ولا حباية، مش تقرير يتقري.
/// * الاتجاه بيتلفّ في البكسل الأول (`bakeOrientation`)، وبعدين **كل**
///   الـEXIF بيتشال: المكان (GPS)، ونوع الموبايل، والوقت. `bakeOrientation`
///   لوحده بيشيل وسم الاتجاه بس — والباقي كان هيتكتب تاني في الـJPEG.
/// * ما بترميش أبداً: صورة بايظة = null، والمريض ببساطة من غير صورة.
const int medPhotoMaxSide = 800;
const int medPhotoJpegQuality = 82;

Uint8List? prepareMedPhoto(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final upright = img.bakeOrientation(decoded);
    final longest = upright.width > upright.height ? upright.width : upright.height;
    final sized = longest <= medPhotoMaxSide
        ? upright
        : upright.width >= upright.height
            ? img.copyResize(upright, width: medPhotoMaxSide, interpolation: img.Interpolation.average)
            : img.copyResize(upright, height: medPhotoMaxSide, interpolation: img.Interpolation.average);
    // من غير أي بيانات وصفية — الـJPEG بيتكتب بالبكسل وبس
    sized.exif = img.ExifData();
    sized.iccProfile = null;
    sized.textData = null;
    return Uint8List.fromList(img.encodeJpg(sized, quality: medPhotoJpegQuality));
  } catch (_) {
    return null;
  }
}
