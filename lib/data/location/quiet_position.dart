/// مكان **من غير سؤال** — لتحية الشروق/الغروب (المالك، ٥ أكتوبر ٢٠٢٦).
///
/// القاعدة اللي الملف ده كله عشانها: **عمرنا ما نطلب إذن مكان جديد عشان
/// التحية**. بنقرا حالة الإذن بس (`checkPermission` — ما بيعرضش أي حوار)؛
/// لو «القريب مني» خد الإذن قبل كده بناخد آخر مكان معروف
/// (`getLastKnownPosition` — من الكاش، بلا GPS وبلا حوار). غير كده null
/// والقاهرة هي الافتراضي. **طلب الإذن ممنوع في الملف ده** —
/// `display_mode_test` بيقرا المصدر ويوقع لو دالة الطلب ظهرت فيه، حتى في تعليق.
library;

import 'package:geolocator/geolocator.dart';

import '../../core/diagnostics.dart';

/// (خط العرض، خط الطول) لو الإذن موجود خلاص ومعانا مكان متخزّن — وإلا null.
Future<({double lat, double lon})?> quietPosition() async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      return null;
    }
    final position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return (lat: position.latitude, lon: position.longitude);
  } catch (error) {
    // التحية مش أهم من إن التطبيق يفتح — القاهرة كفاية
    diag('DayNight: قراية المكان الهادية وقعت — $error');
    return null;
  }
}
