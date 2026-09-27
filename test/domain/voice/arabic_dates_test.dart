// بورت `dates.ar.js` — حالات `backend/test/nlu.test.js` بالحرف (الماضي، زي
// الأصل)، وحالات المواعيد الجاية بتاعتنا.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/arabic_dates.dart';

void main() {
  // السبت ٨ أغسطس ٢٠٢٦ الساعة ١٠ — زي NOW في الأصل
  final now = DateTime(2026, 8, 8, 10);
  List<String> iso(String s, {DateTime? at, bool future = false}) =>
      [for (final d in extractDates(s, now: at ?? now, future: future)) isoDate(d.date)];

  group('زي الأصل (ماضي)', () {
    test('الكلمات النسبية', () {
      expect(iso('امبارح'), ['2026-08-07']);
      expect(iso('النهاردة'), ['2026-08-08']);
      expect(iso('بكرة'), ['2026-08-09']);
      expect(iso('بعد بكرة'), ['2026-08-10']);
    });
    test('«أول امبارح» قبل «امبارح» — الأطول بيكسب', () {
      expect(iso('أول امبارح'), ['2026-08-06']);
    });
    test('بالليل متأخر اليوم لسه صح', () {
      final late = DateTime(2026, 8, 9, 1, 30);
      expect(iso('امبارح', at: late), ['2026-08-08']);
      expect(iso('النهاردة', at: late), ['2026-08-09']);
    });
    test('«من ٣ أيام» و«من أسبوعين»', () {
      expect(iso('من 3 أيام'), ['2026-08-05']);
      expect(iso('من أسبوعين'), ['2026-07-25']);
    });
    test('التواريخ الصريحة زي ما هي', () {
      expect(iso('يوم 2026-03-15'), ['2026-03-15']);
      expect(iso('يوم 15/3/2026'), contains('2026-03-15'));
    });
    test('يوم الأسبوع = أقرب واحد فات', () {
      expect(iso('يوم الجمعة'), ['2026-08-07']);
      expect(iso('يوم الجمعة اللي فات'), ['2026-08-07']);
      expect(iso('يوم السبت اللي فات'), ['2026-08-01']);
    });
    test('الفترات للأسئلة', () {
      final m = extractRange('الشهر ده', now: now)!;
      expect(isoDate(m.from), '2026-08-01');
      expect(isoDate(m.to), '2026-08-31');
      final prev = extractRange('الشهر اللي فات', now: now)!;
      expect(isoDate(prev.from), '2026-07-01');
      expect(isoDate(prev.to), '2026-07-31');
      expect(isoDate(extractRange('آخر 30 يوم', now: now)!.from), '2026-07-09');
      expect(extractRange('حاجة تانية خالص', now: now), isNull);
    });
  });

  group('مواعيد جاية (future)', () {
    test('«يوم الحد» = الحد الجاي (السبت ٨ → الحد ٩)', () {
      expect(iso('احجزلي ميعاد دكتور يوم الحد', future: true), ['2026-08-09']);
      expect(iso('يوم الجمعة', future: true), ['2026-08-14']);
      expect(iso('يوم السبت', future: true), ['2026-08-08'], reason: 'النهارده لسه ينفع');
      expect(iso('السبت الجاي', future: true), ['2026-08-15']);
    });
    test('«بكرة» و«بعد بكرة» زي ما هم', () {
      expect(iso('بكرة الساعة ٥', future: true), ['2026-08-09']);
      expect(iso('بعد بكره', future: true), ['2026-08-10']);
    });
    test('«الأسبوع الجاي» / «بعد أسبوع» / «بعد ٣ أيام» / «بعد شهر»', () {
      expect(iso('الأسبوع الجاي', future: true), ['2026-08-15']);
      expect(iso('بعد أسبوع', future: true), ['2026-08-15']);
      expect(iso('بعد اسبوعين', future: true), ['2026-08-22']);
      expect(iso('بعد ٣ أيام', future: true), ['2026-08-11']);
      expect(iso('بعد شهر', future: true), ['2026-09-08']);
    });
    test('«التلات الأسبوع الجاي» = التلات اللي بعد الجاي، مش +٧ بس', () {
      expect(iso('التلات الأسبوع الجاي', future: true), ['2026-08-11']);
    });
    test('«أول الشهر» و«آخر الشهر»', () {
      expect(iso('أول الشهر', future: true), ['2026-09-01']);
      expect(iso('أول الشهر', at: DateTime(2026, 9, 1), future: true), ['2026-09-01']);
      expect(iso('آخر الشهر', future: true), ['2026-08-31']);
    });
    test('من غير تاريخ = ولا حاجة (مفيش تخمين)', () {
      expect(iso('احجزلي ميعاد دكتور', future: true), isEmpty);
    });
  });
}
