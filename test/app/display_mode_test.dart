// الشروق والغروب الحقيقيين ووضع الشاشة (مراجعة المالك، ٥ أكتوبر ٢٠٢٦):
// التحية بالشمس، «تلقائي» الافتراضي وبيتبعها، «على طول» بيفرض، الهجرة من
// زرار القمر القديم — **وعمرنا ما نطلب إذن مكان جديد عشان التحية**.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/day_night.dart';
import 'package:fakkarni/core/theme/theme_mode_store.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/display_mode_row.dart';
import 'package:fakkarni/domain/time/sun_times.dart' as sun;

void main() {
  tearDown(() {
    DayNight.resetForTest();
    ThemeModeStore.resetForTest();
    ThemeModeStore.isNight = (_) => false;
    F.setDark(on: false);
  });

  group('حساب الشمس — نقي، UTC', () {
    test('اعتدال مارس في القاهرة: الشروق ≈ ١٢:٠٠ − خط الطول/١٥ بالـUTC', () {
      final t = sun.sunTimesUtc(year: 2026, month: 3, day: 20)!;
      // زوال شمسي ≈ 12:00 − (31.24/15)h ≈ 9:55 UTC؛ نهار الاعتدال ≈ ١٢ ساعة
      final sunriseMinutes = t.sunriseUtc.hour * 60 + t.sunriseUtc.minute;
      expect((sunriseMinutes - (3 * 60 + 55)).abs(), lessThan(20),
          reason: 'الشروق ${t.sunriseUtc} — المفروض حوالين ٣:٥٥ UTC');
      final daylight = t.sunsetUtc.difference(t.sunriseUtc).inMinutes;
      expect((daylight - 12 * 60).abs(), lessThan(20), reason: 'نهار الاعتدال ≈ ١٢ ساعة');
    });

    test('نهار يونيو أطول من ديسمبر — وبالمقادير المعروفة لخط عرض ٣٠', () {
      final june = sun.sunTimesUtc(year: 2026, month: 6, day: 21)!;
      final dec = sun.sunTimesUtc(year: 2026, month: 12, day: 21)!;
      final juneLen = june.sunsetUtc.difference(june.sunriseUtc).inMinutes;
      final decLen = dec.sunsetUtc.difference(dec.sunriseUtc).inMinutes;
      expect(juneLen, greaterThan(decLen));
      expect((juneLen - 14 * 60).abs(), lessThan(35), reason: 'يونيو ≈ ١٤ ساعة (كان $juneLen د)');
      expect((decLen - (10 * 60 + 15)).abs(), lessThan(35), reason: 'ديسمبر ≈ ١٠ ساعات وشوية (كان $decLen د)');
    });

    test('«نهار» من الشروق **لحد** الغروب — دقيقة الغروب نفسها مساء', () {
      const w = (sunriseMinutes: 6 * 60, sunsetMinutes: 18 * 60);
      expect(sun.isDaytime(DateTime(2026, 10, 5, 6, 0), sunriseMinutes: w.sunriseMinutes, sunsetMinutes: w.sunsetMinutes), isTrue);
      expect(sun.isDaytime(DateTime(2026, 10, 5, 17, 59), sunriseMinutes: w.sunriseMinutes, sunsetMinutes: w.sunsetMinutes), isTrue);
      expect(sun.isDaytime(DateTime(2026, 10, 5, 18, 0), sunriseMinutes: w.sunriseMinutes, sunsetMinutes: w.sunsetMinutes), isFalse);
      expect(sun.isDaytime(DateTime(2026, 10, 5, 5, 59), sunriseMinutes: w.sunriseMinutes, sunsetMinutes: w.sunsetMinutes), isFalse);
    });

    test('DayNight: القاهرة افتراضياً، والمكان الهادي بيحرّك النافذة — وفشله بيسيبها', () async {
      final cairo = DayNight.windowFor(DateTime(2026, 10, 5, 12));
      // أوسلو (٥٩٫٩ شمالاً) — نهار أكتوبر أقصر بوضوح من القاهرة
      expect(await DayNight.refreshLocation(position: () async => (lat: 59.91, lon: 10.75)), isTrue);
      final oslo = DayNight.windowFor(DateTime(2026, 10, 5, 12));
      expect(oslo.sunsetMinutes - oslo.sunriseMinutes, lessThan(cairo.sunsetMinutes - cairo.sunriseMinutes));
      // null (مفيش إذن) = ولا حاجة بتتغيّر
      expect(await DayNight.refreshLocation(position: () async => null), isFalse);
      expect(DayNight.windowFor(DateTime(2026, 10, 5, 12)), oslo);
    });
  });

  group('وضع الشاشة — التخزين والتطبيق', () {
    test('تنزيلة جديدة = «تلقائي»، وبيتبع الشمس عند الإقلاع', () async {
      SharedPreferences.setMockInitialValues({});
      ThemeModeStore.isNight = (now) => now.hour >= 18;
      await ThemeModeStore.load(clock: () => DateTime(2026, 10, 5, 21));
      expect(ThemeModeStore.mode, DisplayMode.auto);
      expect(F.isDark, isTrue, reason: '٩ بالليل = ليلي تحت «تلقائي»');
      await ThemeModeStore.load(clock: () => DateTime(2026, 10, 5, 10));
      expect(F.isDark, isFalse);
    });

    test('زرار القمر القديم متخزّن = «على طول» المطابق — اختياره بيتحترم', () async {
      SharedPreferences.setMockInitialValues({'ui.dark': true});
      ThemeModeStore.isNight = (_) => false;
      await ThemeModeStore.load(clock: () => DateTime(2026, 10, 5, 10));
      expect(ThemeModeStore.mode, DisplayMode.dark);
      expect(F.isDark, isTrue, reason: 'ليلي على طول حتى الصبح');
      expect((await SharedPreferences.getInstance()).getString(ThemeModeStore.modeKey), 'dark');
    });

    test('«نهاري على طول» بيفرض حتى بالليل — والتحية برّه الموضوع (بتقرا الشمس مباشرة)', () async {
      SharedPreferences.setMockInitialValues({});
      ThemeModeStore.isNight = (_) => true;
      await ThemeModeStore.load(clock: () => DateTime(2026, 10, 5, 21));
      expect(F.isDark, isTrue);
      await ThemeModeStore.setMode(DisplayMode.light, clock: () => DateTime(2026, 10, 5, 21));
      expect(F.isDark, isFalse, reason: 'الوضع بيفرض');
      expect((await SharedPreferences.getInstance()).getString(ThemeModeStore.modeKey), 'light');
    });

    test('الرجوع للمقدمة بيعيد التطبيق — تطبيق مفتوح عبر الغروب بيقلب', () async {
      SharedPreferences.setMockInitialValues({});
      ThemeModeStore.isNight = (now) => now.hour >= 18;
      await ThemeModeStore.load(clock: () => DateTime(2026, 10, 5, 17));
      expect(F.isDark, isFalse);
      ThemeModeStore.apply(DateTime(2026, 10, 5, 19)); // اللي الرجوع بينده
      expect(F.isDark, isTrue);
    });
  });

  group('الصف في الإعدادات', () {
    testWidgets('تلات شرايح، «تلقائي» الافتراضي، والاختيار بيتطبّق فوراً وبيتخزّن', (tester) async {
      SharedPreferences.setMockInitialValues({});
      ThemeModeStore.isNight = (_) => false;
      await ThemeModeStore.load(clock: () => DateTime(2026, 10, 5, 10));
      await tester.pumpWidget(MaterialApp(
        theme: F.light,
        home: const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: DisplayModeRow())),
      ));
      for (final label in ['تلقائي', 'نهاري على طول', 'ليلي على طول']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('display-mode-dark')));
      await tester.pump();
      expect(F.isDark, isTrue);
      expect(ThemeModeStore.mode, DisplayMode.dark);
      expect((await SharedPreferences.getInstance()).getString(ThemeModeStore.modeKey), 'dark');
    });
  });

  test('**عمرنا ما نطلب إذن مكان عشان التحية** — قراية الحالة بس، وgeolocator في ملفينه', () {
    final quiet = File('lib/data/location/quiet_position.dart').readAsStringSync();
    expect(quiet, contains('checkPermission'));
    expect(quiet.contains('requestPermission'), isFalse,
        reason: 'طلب إذن جديد للتحية ممنوع (قرار المالك، ٥ أكتوبر ٢٠٢٦)');
    expect(quiet, contains('getLastKnownPosition'), reason: 'من الكاش — مفيش GPS ولا حوار');
    // geolocator بيتستورد في مكانين بس: «القريب مني» (اللي بيطلب الإذن
    // عن قصد) والقراية الهادية دي
    final importers = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.readAsStringSync().contains("package:geolocator")) importers.add(f.path);
    }
    expect(importers.toSet(), {'lib/data/places/places.dart', 'lib/data/location/quiet_position.dart'});
  });
}
