import 'package:flutter/material.dart';

/// ألوان هوية فكرني.
///
/// الذهبي محجوز للتذكير والحالة النشطة فقط — لو ظهر في أي مكان تاني
/// بيفقد وظيفته ويبقى مجرد زينة.
abstract final class F {
  static const ink = Color(0xFF122E28);
  static const green = Color(0xFF10715E);
  static const greenDeep = Color(0xFF0A4638);
  static const gold = Color(0xFFE9A93B);
  static const ivory = Color(0xFFF1EFE6);
  static const ground = Color(0xFFF2F5F3);
  static const line = Color(0xFFD4DFDB);
  static const muted = Color(0xFF617E78);

  /// كبار السن أول مستخدم — الأحجام دي حد أدنى مش اقتراح.
  static const minBodySize = 20.0;
  static const minTapTarget = 56.0;
  static const primaryButtonHeight = 64.0;

  /// أصغر نص مسموح بيه في أي مكان في التطبيق.
  static const minTextSize = 17.0;

  static const questionSize = 27.0;
  static const screenTitleSize = 25.0;
  static const bigTimeSize = 40.0;
  static const labelSize = 17.0;
  static const chipHeight = 64.0;
  static const radius = 14.0;
  static const gap = 16.0;

  /// خط الأدوية — أسماء لاتينية بترتاح في mono.
  ///
  /// IBM Plex Mono مفيهوش حروف عربي، ومن غير البديل العربي الحروف بتتفصل
  /// عن بعضها. عشان كده أي استخدام لـmono لازم يشيل الاحتياطي ده معاه.
  static const monoFamily = 'IBM Plex Mono';
  static const monoFallback = <String>['Noto Sans Arabic', 'Arial'];

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: ground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          primary: green,
          secondary: gold,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: minBodySize, height: 1.7),
          bodyMedium: TextStyle(fontSize: 18, height: 1.7),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(primaryButtonHeight),
            textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(minTapTarget),
            textStyle: const TextStyle(fontSize: 17),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
}
