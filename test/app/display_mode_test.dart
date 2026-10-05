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
      expect(
        await DayNight.refreshLocation(
          position: () async => (lat: 59.91, lon: 10.75),
          tzOffset: const Duration(hours: 1), // منطقة أوسلو — المكان مطابق
        ),
        isTrue,
      );
      final oslo = DayNight.windowFor(DateTime(2026, 10, 5, 12));
      expect(oslo.sunsetMinutes - oslo.sunriseMinutes, lessThan(cairo.sunsetMinutes - cairo.sunriseMinutes));
      // null (مفيش إذن) = ولا حاجة بتتغيّر
      expect(await DayNight.refreshLocation(position: () async => null), isFalse);
      expect(DayNight.windowFor(DateTime(2026, 10, 5, 12)), oslo);
    });
  });

  group('عطل المحاكي (٥ أكتوبر ٢٠٢٦): «مساء الخير» الساعة ٢:٣٠ الضهر', () {
    test('حالة اليوم الحقيقية: ٥ أكتوبر بالقاهرة — ٢ الضهر نهار و٨ بالليل مساء', () {
      // الشروق ٣:٥١ والغروب ١٥:٣٧ UTC (متقاسين بالـprobe) — المقارنة
      // باللحظة فبتصح مهما كانت منطقة ماكينة التشغيل
      expect(DayNight.isDaytime(DateTime(2026, 10, 5, 14)), isTrue, reason: 'بعد الضهر صباح لحد الغروب');
      expect(DayNight.isDaytime(DateTime(2026, 10, 5, 20)), isFalse);
    });

    test('**السبب المتقاس**: مكان المحاكي الافتراضي (سان فرانسيسكو) بساعة قاهرة — النافذة بالدقايق بتتلف وبتطلّع «ليل على طول»', () {
      // توثيق شكل العطل: غروبها بالدقايق قبل شروقها
      final sf = sun.sunWindowFor(DateTime(2026, 10, 5, 14, 30), lat: 37.7749, lon: -122.4194);
      expect(sf.sunsetMinutes, lessThan(sf.sunriseMinutes), reason: 'النافذة ملفوفة');
      expect(
        sun.isDaytime(DateTime(2026, 10, 5, 14, 30), sunriseMinutes: sf.sunriseMinutes, sunsetMinutes: sf.sunsetMinutes),
        isFalse,
        reason: 'المقارنة بالدقايق على نافذة ملفوفة = ليل دايماً — ده اللي المحاكي ورّاه',
      );
      // والإصلاح الأول: المكان اللي مش مطابق منطقة الجهاز بيترفض والقاهرة بتفضل
      expect(sun.plausibleForTimezone(-122.4194, const Duration(hours: 3)), isFalse);
      expect(sun.plausibleForTimezone(31.2357, const Duration(hours: 3)), isTrue);
    });

    test('رفض المكان المش مطابق: سان فرانسيسكو بإزاحة قاهرة بتترفض والتحية بتفضل صح', () async {
      expect(
        await DayNight.refreshLocation(
          position: () async => (lat: 37.7749, lon: -122.4194),
          tzOffset: const Duration(hours: 3),
        ),
        isFalse,
        reason: 'مكان متخزّن قديم/افتراضي محاكي — القاهرة أصدق',
      );
      expect(DayNight.isDaytime(DateTime(2026, 10, 5, 14)), isTrue, reason: '٢ الضهر فضلت صباح');
    });

    test('والإصلاح التاني: المقارنة باللحظة بتستحمل اللفّ — نص ليل UTC جوّه نافذة اليوم اللي فات', () {
      // غروب سان فرانسيسكو ٥ أكتوبر ≈ ٠١:٤٨ UTC يوم ٦ — لحظة ٠١:٠٠ UTC
      // يوم ٦ نهار عندهم، وجوّه نافذة **امبارح** UTC: اللوب [-1, 0, +1]
      // هو اللي بيمسكها
      expect(
        sun.isDaytimeAtInstant(DateTime.utc(2026, 10, 6, 1), lat: 37.7749, lon: -122.4194),
        isTrue,
      );
      expect(
        sun.isDaytimeAtInstant(DateTime.utc(2026, 10, 6, 10), lat: 37.7749, lon: -122.4194),
        isFalse,
        reason: '٢ بالليل عندهم',
      );
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
    testWidgets('صف بالاختيار الحالي وسهم → صفحة التلات اختيارات، والاختيار بيتطبّق وبيتخزّن وبيرجع مكتوب على الصف', (tester) async {
      SharedPreferences.setMockInitialValues({});
      ThemeModeStore.isNight = (_) => false;
      await ThemeModeStore.load(clock: () => DateTime(2026, 10, 5, 10));
      await tester.pumpWidget(MaterialApp(
        theme: F.light,
        home: const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: DisplayModeRow())),
      ));
      // صف واحد بالحالي — مش تلات شرايح (المالك، ٥ أكتوبر مساءً)
      expect(find.text('وضع الشاشة'), findsOneWidget);
      expect(find.byKey(const ValueKey('display-mode-current')), findsOneWidget);
      expect(find.text('تلقائي'), findsOneWidget, reason: 'الاختيار الحالي مكتوب على الصف');
      expect(find.text('ليلي على طول'), findsNothing, reason: 'الاختيارات جوّه الصفحة مش هنا');

      await tester.tap(find.byKey(const ValueKey('display-mode-row')));
      await tester.pumpAndSettle();
      expect(find.byType(DisplayModeScreen), findsOneWidget);
      for (final label in ['تلقائي', 'نهاري على طول', 'ليلي على طول']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('display-mode-dark')));
      await tester.pump();
      expect(F.isDark, isTrue);
      expect(ThemeModeStore.mode, DisplayMode.dark);
      expect((await SharedPreferences.getInstance()).getString(ThemeModeStore.modeKey), 'dark');

      // رجوع — الصف بيقول الاختيار الجديد
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('ليلي على طول'), findsOneWidget);
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
