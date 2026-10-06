// كارت «القريب مني» الجديد (المالك، ٢٨ سبتمبر ٢٠٢٦): بلاطة النوع، الاسم،
// المسافة رقم كبير، «مفتوح الآن» بس لو فيه مواعيد، «اتصال» / «اتجاهات» /
// واتساب — واللي مش عندنا ما بيترسمش.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/features/nearby/nearby_screen.dart';

import '../../data/places/overpass_places_test.dart' show MemoryCache;
import '../../support/contrast_audit.dart';
import '../scan/scan_test_support.dart';
import 'nearby_screen_test.dart' show BlankTiles, FakeLocation, pickPlace;

class _Source implements PlacesSource {
  _Source(this.places);
  final List<Place> places;
  @override
  String get id => 'fake';
  @override
  String get displayName => 'Apple';
  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async => places;
}

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(() async {
    F.setDark(on: false);
    await h.tearDown();
  });

  const here = LocationFix(LocationStatus.granted, 30.0444, 31.2357);
  // الثلاثاء ١٠ الصبح
  final now = DateTime(2026, 9, 15, 10);

  const full = Place(
    id: 'full',
    kind: PlaceKind.pharmacy,
    lat: 30.0510,
    lon: 31.2357, // ~٧٣٠ متر
    name: 'صيدلية النور',
    phone: '01012345678',
    openingHours: 'Mo-Su 09:00-22:00',
    address: '٢٥ شارع التحرير، الدقي',
    rating: 4.6,
  );
  const noPhone = Place(id: 'nophone', kind: PlaceKind.hospital, lat: 30.0460, lon: 31.2370, name: 'مستشفى القصر العيني');
  const doctor = Place(id: 'doc', kind: PlaceKind.doctor, lat: 30.0470, lon: 31.2380, name: 'د. هشام', phone: '+20 2 1234567');
  const lab = Place(id: 'lab', kind: PlaceKind.lab, lat: 30.0480, lon: 31.2390, name: 'معمل البرج');

  Future<void> pump(WidgetTester tester, List<Place> places) async {
    tester.view.physicalSize = const Size(390, 4000);
    await h.pump(
      tester,
      NearbyScreen(
        location: FakeLocation(here),
        places: NearbyPlaces(source: _Source(places), cache: MemoryCache()),
        tileProvider: BlankTiles(),
        now: () => now,
      ),
    );
    await settle(tester);
  }

  screenTest('كارت كامل: بلاطة، اسم، عنوان، «مفتوح الآن»، «٠٫٧» كم، «★ ٤٫٦»، و«اتصال / اتجاهات / واتساب»', (tester) async {
    await pump(tester, [full]);
    expect(find.byKey(const ValueKey('kind-tile-pharmacy')), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const ValueKey('place-name-full'))).data, 'صيدلية النور');
    expect(tester.widget<Text>(find.byKey(const ValueKey('place-address-full'))).data, '٢٥ شارع التحرير، الدقي');
    expect(find.text('مفتوح الآن'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('place-distance-full')), matching: find.text('كم')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('place-distance-full')), matching: find.text('٠٫٧')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('place-rating-full'))).data, '★ ٤٫٦');
    expect(find.descendant(of: find.byKey(const ValueKey('call-full')), matching: find.byType(FilledButton)), findsOneWidget,
        reason: '«اتصال» مليان');
    expect(find.descendant(of: find.byKey(const ValueKey('route-full')), matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('route-full')), matching: find.text('اتجاهات')), findsOneWidget);
    // واتساب صغير، بكلمته، في نفس الصف
    final wa = tester.getRect(find.byKey(const ValueKey('whatsapp-full')));
    final call = tester.getRect(find.byKey(const ValueKey('call-full')));
    expect(wa.center.dy, closeTo(call.center.dy, 1));
    expect(wa.width, lessThan(call.width));
    expect(find.descendant(of: find.byKey(const ValueKey('whatsapp-full')), matching: find.text('واتساب')), findsOneWidget);
    // الترتيب RTL: البلاطة يمين، والمسافة شمال
    expect(tester.getCenter(find.byKey(const ValueKey('kind-tile-pharmacy')).last).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey('place-distance-full'))).dx));
  });

  screenTest('من غير رقم: مفيش «اتصال» ولا واتساب، و«اتجاهات» بعرض الكارت', (tester) async {
    await pump(tester, [noPhone]);
    expect(find.byKey(const ValueKey('call-nophone')), findsNothing);
    expect(find.byKey(const ValueKey('whatsapp-nophone')), findsNothing);
    final card = tester.getRect(find.byKey(const ValueKey('place-nophone')));
    final route = tester.getRect(find.byKey(const ValueKey('route-nophone')));
    // الكارت المختار جوّه الورقة: حشو من الجنبين ومن غير حد
    expect(route.width, closeTo(card.width - 2 * F.gap, 1), reason: 'العرض كله جوّه الحشو');
  });

  screenTest('من غير مواعيد ولا تقييم ولا عنوان: مفيش شريحة ولا نجمة ولا سطر — ولا حاجة مخترعة', (tester) async {
    await pump(tester, [noPhone, doctor]);
    expect(find.text('مفتوح الآن'), findsNothing);
    expect(find.text('مغلق'), findsNothing);
    expect(find.byKey(const ValueKey('place-rating-nophone')), findsNothing);
    expect(find.byKey(const ValueKey('place-address-nophone')), findsNothing);
    for (final fake in ['★', 'متوفر', 'تأمين', 'توصيل', 'دقيقة']) {
      expect(find.textContaining(fake), findsNothing, reason: fake);
    }
    // أرضي: «اتصال» آه، واتساب لأ — على الدكتور لما يبقى مختار
    await pickPlace(tester, 'doc');
    expect(find.byKey(const ValueKey('call-doc')), findsOneWidget);
    expect(find.byKey(const ValueKey('whatsapp-doc')), findsNothing);
  });

  screenTest('«مغلق» بس لما مواعيد الخريطة بتقول كده', (tester) async {
    const closed = Place(id: 'closed', kind: PlaceKind.pharmacy, lat: 30.045, lon: 31.236, name: 'صيدلية الليل', openingHours: 'Mo-Su 20:00-23:00');
    await pump(tester, [closed]);
    expect(find.text('مغلق'), findsOneWidget);
    expect(find.text('مفتوح الآن'), findsNothing);
  });

  screenTest('كل نوع بأيقونته ولونه — على الكارت والدبوس والفلتر نفس الشكل', (tester) async {
    await pump(tester, [full, noPhone, doctor, lab]);
    for (final (kind, icon) in [
      (PlaceKind.pharmacy, Icons.medication),
      (PlaceKind.hospital, Icons.local_hospital),
      (PlaceKind.doctor, Icons.medical_services),
      (PlaceKind.lab, Icons.science),
    ]) {
      expect(kindStyle(kind).icon, icon);
      final tiles = find.byKey(ValueKey('kind-tile-${kind.name}'));
      // الكارت دايماً؛ الدبوس لو جوّه حدود الخريطة (البعيد بيتقصّ برّه الإطار)
      expect(tiles, findsWidgets, reason: kind.name);
      expect(find.descendant(of: tiles.first, matching: find.byIcon(icon)), findsOneWidget);
      final chip = find.byKey(ValueKey('nearby-filter-${kind == PlaceKind.lab ? 'lab' : kind.name}'));
      expect(find.descendant(of: chip, matching: find.byIcon(icon)), findsOneWidget, reason: 'نفس الأيقونة على الفلتر');
    }
    // الأنواع بتختلف في اللون كمان — مش أيقونة بس
    final grounds = {for (final k in PlaceKind.values) kindStyle(k).bg};
    expect(grounds.length, PlaceKind.values.length);
    // مفيش أحمر ولا دهبي في البلاطات
    for (final k in PlaceKind.values) {
      for (final c in [kindStyle(k).bg, kindStyle(k).fg]) {
        expect(c, isNot(F.red));
        expect(c, isNot(F.gold));
      }
    }
  });

  screenTest('مرتّبين بالمسافة — الأقرب الأول', (tester) async {
    await pump(tester, [lab, full, noPhone]);
    final ys = [for (final id in ['nophone', 'lab', 'full']) tester.getTopLeft(find.byKey(ValueKey('place-$id'))).dy];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
  });

  screenTest('مفيش حاجة خالص → «مفيش أماكن قريبة دلوقتي — جرّب تكبّر المسافة»', (tester) async {
    await pump(tester, const []);
    expect(find.text('مفيش أماكن قريبة دلوقتي — جرّب تكبّر المسافة'), findsOneWidget);
  });

  double contrast(Color a, Color b) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    double l(Color c) => 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    final x = l(a), y = l(b);
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  for (final dark in [false, true]) {
    screenTest('${dark ? 'ليلي' : 'نهاري'} — كل نص بيتقري، وأيقونة كل نوع ٣:١ على بلاطتها', (tester) async {
      F.setDark(on: dark);
      await pump(tester, [full, noPhone, doctor, lab]);
      expectReadableText(tester, where: 'كروت القريب مني');
      for (final k in PlaceKind.values) {
        expect(contrast(kindStyle(k).fg, kindStyle(k).bg), greaterThanOrEqualTo(3.0), reason: '${k.name} ${dark ? 'ليلي' : 'نهاري'}');
      }
    });
  }
}
