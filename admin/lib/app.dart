import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/admin_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'theme/theme_mode_store.dart';
import 'theme/tokens.dart';
import 'widgets_missing_config.dart';

/// جذر اللوحة — عربي RTL، نهاري وليلي.
///
/// **الوضع بيقلب كل لون من مكان واحد**: الألوان getters على `F` بتقرا
/// `F.darkMode`، والشجرة كلها مفتاحها على الوضع — نفس اللي التطبيق بيعمله،
/// وبنفس الثمن: التبديل بيعيد بناء الشاشة الحالية (بحثك بيتمسح، واللوحة
/// الجانبية بتتقفل). ودجت `const` ما بتتبنيش تاني لما متغيّر عام يتقلب،
/// والمفتاح هو اللي بيضمن إن ولا لون بيفضل قديم.
class AdminApp extends StatefulWidget {
  const AdminApp({required this.service, this.themeStore, super.key});

  /// null = الإعداد ناقص (`--dart-define`) — الشاشة بتقول ده بالنص.
  final AdminService? service;

  /// للاختبارات — الإنتاج بيحفظ في localStorage.
  final ThemeStore? themeStore;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final ThemeController _theme =
      ThemeController(widget.themeStore ?? SharedPrefsThemeStore());
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _signedIn = widget.service?.currentEmail != null;
    WidgetsBinding.instance.addObserver(_theme);
    _theme.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_theme);
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return ThemeScope(
      notifier: _theme,
      child: ValueListenableBuilder<bool>(
        valueListenable: F.darkMode,
        builder: (context, dark, _) => KeyedSubtree(
          key: ValueKey(dark),
          child: MaterialApp(
            title: 'لوحة فكرني',
            debugShowCheckedModeBanner: false,
            theme: F.light,
            locale: const Locale('ar', 'EG'),
            supportedLocales: const [Locale('ar', 'EG'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: service == null
                ? const MissingConfigScreen()
                : _signedIn
                    ? DashboardScreen(
                        service: service,
                        onSignedOut: () => setState(() => _signedIn = false),
                      )
                    : LoginScreen(
                        service: service,
                        onSignedIn: () => setState(() => _signedIn = true),
                      ),
          ),
        ),
      ),
    );
  }
}
