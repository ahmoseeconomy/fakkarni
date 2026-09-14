import 'package:flutter/material.dart';

/// توكنز هوية فكرني — الجدول الكامل من `design/handoff/README.md`.
///
/// **كل hex وكل مقاس من هنا، ومفيش hex بيتكتب مرتين.** الذهبي محجوز
/// للتذكير والحالة النشطة فقط؛ الأحمر للطوارئ فقط — ومفيش طوارئ دلوقتي،
/// فالأحمر معرّف هنا ومش مستعمل في أي مكان.
abstract final class F {
  // ------------------------------------------------------------- الألوان
  static const ink = Color(0xFF122E28);
  static const green = Color(0xFF10715E);
  static const greenDeep = Color(0xFF0A4638);
  static const inkDeep = Color(0xFF071A16);
  static const greenDark = Color(0xFF0F3A31);

  /// التذكير والحالة النشطة **بس**.
  static const gold = Color(0xFFE9A93B);
  static const goldSoft = Color(0xFFF1C476);

  /// نص ذهبي على أرضية غامقة.
  static const goldText = Color(0xFFF0D3A0);

  /// أرضية الصفحة، والنص على الغامق.
  static const ivory = Color(0xFFF1EFE6);
  static const ivoryWarm = Color(0xFFEAE7DB);
  static const ivoryPale = Color(0xFFF7F5EC);
  static const ivoryDim = Color(0xFFEFEDE3);

  static const line = Color(0xFFDFDACB);
  static const lineSoft = Color(0xFFE9E5D8);

  static const muted = Color(0xFF6E7F76);
  static const mutedDark = Color(0xFF43544C);
  static const mutedLight = Color(0xFF8B9C93);
  static const placeholder = Color(0xFFA5AFA5);

  /// درجات السلّم ٣ و٤ — للتنبيه المتصاعد (D2)، مش لأي حاجة تانية.
  static const amber = Color(0xFFD3A21C);
  static const orange = Color(0xFFD9691F);

  /// **الطوارئ بس.** معرّف عشان الجدول يكون كامل — مش مستعمل.
  static const red = Color(0xFFC0202F);
  static const redDeep = Color(0xFFA81E26);

  /// اتأكدت / اتاخدت.
  static const greenOk = Color(0xFF175E39);
  static const greenOkSoft = Color(0xFFEAF5EE);

  /// الحجاب ورا الشيت السفلي.
  static const scrim = Color(0x8C0B2A33); // rgba(11,42,51,.55)

  /// الأرضية القديمة — اتشالت لصالح [ivory]. باقية عشان أي مرجع قديم
  /// يتلقط في المراجعة بدل ما يقع في التشغيل.
  @Deprecated('الأرضية بقت F.ivory')
  static const ground = ivory;

  // ------------------------------------------------- الحدود الدنيا (قواعد)
  /// كبار السن أول مستخدم — الأحجام دي حد أدنى مش اقتراح.
  static const minBodySize = 20.0;
  static const minTapTarget = 56.0;
  static const primaryButtonHeight = 64.0;

  /// أصغر نص مسموح بيه في أي مكان في التطبيق — **أعلى** من كابشن التصميم
  /// (١١–١٣) والـkicker (١٠). سلّم التصميم تحت مسجّل بالكامل للمرجعية،
  /// لكن ولا ودجت هنا بترسم أقل من ده.
  static const minTextSize = 17.0;

  /// أسماء الأدوية.
  static const medicationNameSize = 24.0;

  // ----------------------------------------------------- سلّم الخط (README)
  static const display1 = 46.0;
  static const display2 = 38.0;
  static const display3 = 34.0;
  static const screenTitleSize = 25.0;
  static const subtitleSize = 23.0;
  static const sectionHeadSize = 19.0;
  static const body1 = 16.5, body2 = 16.0, body3 = 15.5, body4 = 15.0;
  static const rowLabel1 = 14.5, rowLabel2 = 14.0;
  static const secondary1 = 13.0, secondary2 = 12.5;
  static const caption1 = 11.5, caption2 = 11.0;
  static const kicker1 = 10.0, kicker2 = 9.5;

  /// تباعد حروف الـkicker — ‎.14em.
  static const kickerTracking = 0.14;

  /// مقاسات موروثة من المرحلة الأولى — لسه مستعملة.
  static const questionSize = 27.0;
  static const bigTimeSize = 40.0;
  static const labelSize = 17.0;
  static const chipHeight = 64.0;

  // ------------------------------------------------------------ الأنصاف
  static const radiusChip = 8.0;
  static const radiusTile = 12.0; // 11–13
  static const radiusCard = 14.0; // 14–16
  static const radiusSection = 18.0;
  static const radiusLarge = 20.0; // 20–22
  static const radiusSheet = 26.0;

  /// الاسم القديم — نفس قيمة [radiusCard].
  static const radius = radiusCard;

  // ------------------------------------------------------------ المسافات
  static const s4 = 4.0, s6 = 6.0, s8 = 8.0, s10 = 10.0, s12 = 12.0;
  static const s14 = 14.0, s16 = 16.0, s18 = 18.0, s20 = 20.0;
  static const s22 = 22.0, s26 = 26.0, s30 = 30.0;
  static const gap = s16;

  // -------------------------------------------------------------- الظلال
  static const shadowCard = [
    BoxShadow(color: Color(0x1A0E2A33), offset: Offset(0, 8), blurRadius: 26),
  ];
  static const shadowMenu = [
    BoxShadow(color: Color(0x2E0E2A33), offset: Offset(0, 12), blurRadius: 30),
  ];
  static const shadowSheet = [
    BoxShadow(color: Color(0x3D000000), offset: Offset(0, -14), blurRadius: 40),
  ];
  static const shadowModalDark = [
    BoxShadow(color: Color(0x47000000), offset: Offset(0, 18), blurRadius: 46),
  ];

  // -------------------------------------------------------------- الحركة
  static const sheetDuration = Duration(milliseconds: 280);
  static const fadeDuration = Duration(milliseconds: 150);

  // -------------------------------------------------------------- الخطوط
  /// العناوين والعلامة.
  static const displayFamily = 'Alexandria';

  /// كل نصوص الواجهة.
  static const bodyFamily = 'IBM Plex Sans Arabic';

  /// أسماء الأدوية والأرقام — لاتيني في mono.
  ///
  /// IBM Plex Mono مفيهوش حروف عربي، ومن غير البديل العربي الحروف بتتفصل
  /// عن بعضها. عشان كده أي استخدام لـmono لازم يشيل الاحتياطي ده معاه.
  static const monoFamily = 'IBM Plex Mono';
  static const monoFallback = <String>[bodyFamily, 'Noto Sans Arabic', 'Arial'];

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: bodyFamily,
        scaffoldBackgroundColor: ivory,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          primary: green,
          secondary: gold,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: ivory,
          foregroundColor: ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: displayFamily,
            fontSize: subtitleSize,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: displayFamily, fontSize: display1, fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(fontFamily: displayFamily, fontSize: screenTitleSize, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontFamily: displayFamily, fontSize: subtitleSize, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: sectionHeadSize, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: minBodySize, height: 1.7),
          bodyMedium: TextStyle(fontSize: 18, height: 1.7),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(primaryButtonHeight),
            textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(minTapTarget),
            textStyle: const TextStyle(fontSize: minTextSize),
            side: const BorderSide(color: line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
          ),
        ),
      );
}
