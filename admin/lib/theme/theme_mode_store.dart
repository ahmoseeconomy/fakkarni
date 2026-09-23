import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// اختيار المستخدم: يمشي مع النظام، أو نهاري، أو ليلي.
enum ThemePreference { system, light, dark }

/// فين الاختيار بيتحفظ — واجهة، عشان الاختبار يحط ذاكرة مكانها.
abstract interface class ThemeStore {
  Future<ThemePreference> load();
  Future<void> save(ThemePreference preference);
}

/// على الويب `shared_preferences` بيكتب في localStorage — وده اللي مطلوب.
///
/// **بيبلع أي فشل**: قراية مقفولة أو تخزين مش متاح معناها «امشي مع النظام»،
/// مش شاشة بيضا. الاختبارات اللي ما بتظبطش mock بتعدّي من هنا برضه.
class SharedPrefsThemeStore implements ThemeStore {
  static const key = 'ui.theme';

  @override
  Future<ThemePreference> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      return ThemePreference.values.firstWhere(
        (p) => p.name == raw,
        orElse: () => ThemePreference.system,
      );
    } catch (_) {
      return ThemePreference.system;
    }
  }

  @override
  Future<void> save(ThemePreference preference) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, preference.name);
    } catch (_) {
      // الاختيار بيفضل شغّال للجلسة دي؛ الحفظ كان زيادة.
    }
  }
}

bool resolveDark(ThemePreference preference, Brightness platform) =>
    switch (preference) {
      ThemePreference.system => platform == Brightness.dark,
      ThemePreference.light => false,
      ThemePreference.dark => true,
    };

/// صاحب القرار الواحد: بيقرا الاختيار، بيسمع للنظام، وبيقلب [F.darkMode] —
/// اللي كل الألوان بتتقري منه.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController(this._store);

  final ThemeStore _store;
  ThemePreference preference = ThemePreference.system;

  bool get isDark => F.isDark;

  Future<void> load() async {
    preference = await _store.load();
    _apply();
  }

  Future<void> toggle() async {
    preference = isDark ? ThemePreference.light : ThemePreference.dark;
    _apply();
    await _store.save(preference);
  }

  bool _disposed = false;

  void _apply() {
    final platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    F.setDark(on: resolveDark(preference, platform));
    // التحميل async — ممكن يخلص بعد ما الشاشة اتقفلت (في الاختبارات بالذات).
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (preference == ThemePreference.system) _apply();
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({required super.notifier, required super.child, super.key});

  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}
