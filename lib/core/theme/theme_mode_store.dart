import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// الوضع الليلي متخزّن محلياً — زي عدّاد المية، مفتاح واحد في
/// `shared_preferences`. **مش في السكيما**: ده تفضيل عرض على الموبايل ده،
/// ومالوش علاقة بالجرعات ولا بالمزامنة.
abstract final class ThemeModeStore {
  static const _key = 'ui.dark';

  /// بيتندَه مرة عند الإقلاع، قبل `runApp`، فأول فريم بيطلع بالوضع الصح.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      F.setDark(on: prefs.getBool(_key) ?? false);
    } catch (error) {
      // التفضيل مش أهم من إن التطبيق يفتح
      debugPrint('الوضع الليلي: القراءة فشلت — بنكمّل بالنهاري: $error');
    }
  }

  static Future<void> set({required bool on}) async {
    F.setDark(on: on);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (error) {
      debugPrint('الوضع الليلي: الحفظ فشل — هيرجع نهاري بعد القفل: $error');
    }
  }
}
