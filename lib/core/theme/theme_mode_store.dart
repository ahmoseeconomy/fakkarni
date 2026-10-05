import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// وضع الشاشة — تلات اختيارات (مراجعة المالك، ٥ أكتوبر ٢٠٢٦).
enum DisplayMode {
  /// نهاري من الشروق للغروب، ليلي من الغروب للشروق — **الافتراضي** على
  /// تنزيلة جديدة.
  auto('auto', 'تلقائي'),
  light('light', 'نهاري على طول'),
  dark('dark', 'ليلي على طول');

  const DisplayMode(this.wire, this.label);

  final String wire;
  final String label;

  static DisplayMode fromWire(String? w) => values.firstWhere((m) => m.wire == w, orElse: () => auto);
}

/// وضع الشاشة متخزّن محلياً — زي عدّاد المية، مفتاح واحد في
/// `shared_preferences`. **مش في السكيما**: ده تفضيل عرض على الموبايل ده،
/// ومالوش علاقة بالجرعات ولا بالمزامنة.
///
/// **منذ ٥ أكتوبر ٢٠٢٦ المصدر هو [DisplayMode]** (`ui.displayMode`):
/// «تلقائي» بيتبع الشمس ([DayNight]) عند الإقلاع والرجوع للمقدمة،
/// و«نهاري/ليلي على طول» بيفرض. المفتاح القديم `ui.dark` فضل زي ما هو:
/// زرار القمر في الشريط لسه بيكتبه وبيقلب فوراً — **سلوكه ما اتغيّرش**
/// (قرار معلّق عند المالك)، والوضع المختار بيرجع يتطبّق مع أول رجوع
/// للمقدمة. الهجرة: `ui.dark` متخزّنة (يعني الزرار اتداس قبل كده) →
/// «على طول» المطابق؛ مفيش ولا ده ولا ده → «تلقائي».
abstract final class ThemeModeStore {
  static const _key = 'ui.dark';
  static const modeKey = 'ui.displayMode';

  /// «دلوقتي ليل؟» — `main` بيحطّها على [DayNight.isDaytime] قبل [load]:
  /// الطبقة دي (core) ما بتستوردش app، فالقرار بييجي من برّه. الافتراضي
  /// نهار — من غير توصيل «تلقائي» = نهاري، ومفيش وقعة.
  static bool Function(DateTime now) isNight = (_) => false;

  static DisplayMode _mode = DisplayMode.auto;
  static DisplayMode get mode => _mode;

  /// بيتندَه مرة عند الإقلاع، قبل `runApp`، فأول فريم بيطلع بالوضع الصح.
  static Future<void> load({DateTime Function() clock = DateTime.now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(modeKey);
      if (stored != null) {
        _mode = DisplayMode.fromWire(stored);
      } else if (prefs.getBool(_key) case final dark?) {
        // اختار قبل كده بزرار القمر — اختياره بيتحترم: «على طول» المطابق
        _mode = dark ? DisplayMode.dark : DisplayMode.light;
        await prefs.setString(modeKey, _mode.wire);
      } else {
        _mode = DisplayMode.auto;
      }
      apply(clock());
    } catch (error) {
      // التفضيل مش أهم من إن التطبيق يفتح
      debugPrint('وضع الشاشة: القراءة فشلت — بنكمّل بالنهاري: $error');
    }
  }

  /// بيطبّق الوضع على الثيم — عند الإقلاع والرجوع للمقدمة، وبعد تغيير
  /// الاختيار. «تلقائي» بيقرا الشمس؛ **مفيش مؤقّت**: التطبيق المفتوح عبر
  /// الغروب بيقلب مع أول رجوع للمقدمة.
  static void apply(DateTime now) {
    final dark = switch (_mode) {
      DisplayMode.auto => isNight(now),
      DisplayMode.light => false,
      DisplayMode.dark => true,
    };
    F.setDark(on: dark);
  }

  /// اختيار من «وضع الشاشة» في الإعدادات — بيتخزّن وبيتطبّق فوراً.
  static Future<void> setMode(DisplayMode mode, {DateTime Function() clock = DateTime.now}) async {
    _mode = mode;
    apply(clock());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(modeKey, mode.wire);
    } catch (error) {
      debugPrint('وضع الشاشة: الحفظ فشل — هيرجع لما كان بعد القفل: $error');
    }
  }

  /// زرار القمر — زي ما كان بالحرف: بيقلب فوراً وبيتخزّن في `ui.dark`.
  /// (تحت «تلقائي» ده بيعيش لحد أول رجوع للمقدمة — شوف ملاحظة الصف فوق.)
  static Future<void> set({required bool on}) async {
    F.setDark(on: on);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (error) {
      debugPrint('الوضع الليلي: الحفظ فشل — هيرجع نهاري بعد القفل: $error');
    }
  }

  /// للاختبار.
  static void resetForTest() => _mode = DisplayMode.auto;
}
