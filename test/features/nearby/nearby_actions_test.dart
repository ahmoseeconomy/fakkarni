import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/domain/places/specialty.dart';
import 'package:fakkarni/features/emergency/emergency_widgets.dart' show dialNumber;
import 'package:fakkarni/features/medication/refill_actions.dart' show openWhatsApp;
import 'package:fakkarni/features/nearby/nearby_screen.dart';

import '../../data/places/overpass_places_test.dart' show MemoryCache;
import 'package:fakkarni/core/theme/tokens.dart';

import '../../support/contrast_audit.dart';
import '../scan/scan_test_support.dart';
import 'nearby_screen_test.dart' show BlankTiles, FakeLocation, pickPlace;

/// كارت «القريب مني»: اتصال / واتساب / الطريق، والتخصص، و«احجز».
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  const cairo = LocationFix(LocationStatus.granted, 30.0444, 31.2357);
  final now = DateTime(2026, 9, 15, 10);

  const response = {
    'elements': [
      // دكتور عيون بالوسم، موبايل
      {'type': 'node', 'id': 11, 'lat': 30.0450, 'lon': 31.2360, 'tags': {'amenity': 'doctors', 'name': 'د. هشام', 'healthcare:speciality': 'ophthalmology', 'phone': '010 1234 5678'}},
      // عيادة أسنان من الاسم، أرضي
      {'type': 'node', 'id': 12, 'lat': 30.0452, 'lon': 31.2362, 'tags': {'amenity': 'clinic', 'name': 'مركز الأسنان الحديث', 'phone': '+20 2 1234567'}},
      // دكتور من غير تخصص ولا رقم
      {'type': 'node', 'id': 13, 'lat': 30.0455, 'lon': 31.2365, 'tags': {'amenity': 'doctors', 'name': 'عيادة د. سامي'}},
      // صيدلية بموبايل
      {'type': 'node', 'id': 14, 'lat': 30.0446, 'lon': 31.2358, 'tags': {'amenity': 'pharmacy', 'name': 'صيدلية النور', 'phone': '+201112345678'}},
    ],
  };

  late List<String> dialed, routed, whats, booked;

  setUp(() {
    dialed = [];
    routed = [];
    whats = [];
    booked = [];
    dialNumber = (n) async => dialed.add(n);
    openDirections = (p) async => routed.add(p.id);
    openWhatsApp = (u) async {
      whats.add(u.toString());
      return true;
    };
    bookFromPlace = (context, p, today) async {
      booked.add(p.name ?? p.id);
      return true;
    };
  });

  Future<void> pump(WidgetTester tester, {Specialty? specialty, PlaceKind? kind}) async {
    tester.view.physicalSize = const Size(1000, 4000);
    await h.pump(
      tester,
      NearbyScreen(
        initialKind: kind,
        initialSpecialty: specialty,
        location: FakeLocation(cairo),
        places: NearbyPlaces(
          source: OverpassPlaces(client: MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode(response)), 200))),
          cache: MemoryCache(),
        ),
        tileProvider: BlankTiles(),
        now: () => now,
      ),
    );
    await settle(tester);
  }

  screenTest('الكارت: الاسم كبير، التخصص، المسافة، و«اتصال / واتساب / الطريق» في صف واحد', (tester) async {
    await pump(tester);

    final name = tester.widget<Text>(find.byKey(const ValueKey('place-name-node/11')));
    expect(name.data, 'د. هشام');
    expect(tester.widget<Text>(find.byKey(const ValueKey('place-category-node/11'))).data, 'دكتور عيون');
    expect(tester.widget<Text>(find.byKey(const ValueKey('place-category-node/12'))).data, 'دكتور أسنان');
    expect(tester.widget<Text>(find.byKey(const ValueKey('place-category-node/13'))).data, 'دكتور', reason: 'مفيش تخصص معروف — ما بنخمّنش');
    expect(find.byKey(const ValueKey('place-distance-node/11')), findsOneWidget);

    // صف واحد — الأفعال على المختار، و«صيدلية النور» أقرب فبنختار الدكتور
    await pickPlace(tester, 'node/11');
    final call = tester.getCenter(find.byKey(const ValueKey('call-node/11')));
    final wa = tester.getCenter(find.byKey(const ValueKey('whatsapp-node/11')));
    final route = tester.getCenter(find.byKey(const ValueKey('route-node/11')));
    expect(call.dy, wa.dy);
    expect(wa.dy, route.dy);

    await tester.tap(find.byKey(const ValueKey('whatsapp-node/11')));
    await tester.tap(find.byKey(const ValueKey('call-node/11')));
    await tester.tap(find.byKey(const ValueKey('route-node/11')));
    await settle(tester);
    expect(whats, ['https://wa.me/201012345678']);
    expect(dialed, ['010 1234 5678']);
    expect(routed, ['node/11']);
    expectNoRedAndMinSize(tester);
  });

  screenTest('من غير رقم: لا «اتصال» ولا «واتساب» — و«واتساب» للموبايل المصري بس', (tester) async {
    await pump(tester);
    // الأفعال على المكان المختار — بنختار كل واحد وبنبص
    await pickPlace(tester, 'node/13');
    expect(find.byKey(const ValueKey('call-node/13')), findsNothing);
    expect(find.byKey(const ValueKey('whatsapp-node/13')), findsNothing);
    expect(find.byKey(const ValueKey('route-node/13')), findsOneWidget);
    // أرضي: اتصال آه، واتساب لأ
    await pickPlace(tester, 'node/12');
    expect(find.byKey(const ValueKey('call-node/12')), findsOneWidget);
    expect(find.byKey(const ValueKey('whatsapp-node/12')), findsNothing);
    // صيدلية بموبايل: الاتنين
    await pickPlace(tester, 'node/14');
    expect(find.byKey(const ValueKey('whatsapp-node/14')), findsOneWidget);
  });

  screenTest('«احجز» على الدكاترة بس — والدوسة بتفتح الميعاد باسم الدكتور', (tester) async {
    await pump(tester);
    // الصيدلية هي الأقرب فمختارة من الأول — ومالهاش «احجز»
    expect(find.byKey(const ValueKey('book-node/14')), findsNothing, reason: 'صيدلية مش بتتحجز');
    await pickPlace(tester, 'node/11');
    expect(find.byKey(const ValueKey('book-node/11')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('book-node/11')));
    await tester.tap(find.byKey(const ValueKey('book-node/11')));
    await settle(tester);
    expect(booked, ['د. هشام']);
  });

  screenTest('شريحة التخصص تحت «دكاترة»: «أسنان» بتسيب عيادة الأسنان بس', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('nearby-specialty-dental')), findsNothing, reason: 'على «الكل» مفيش تخصصات');
    await tester.tap(find.byKey(const ValueKey('nearby-filter-doctor')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nearby-specialty-dental')));
    await settle(tester);
    expect(find.byKey(const ValueKey('place-node/12')), findsOneWidget);
    expect(find.byKey(const ValueKey('place-node/11')), findsNothing);
    expect(find.byKey(const ValueKey('place-node/13')), findsNothing);
  });

  screenTest('«أقرب دكتور عيون» من «كلّمني» بيفتح على الدكاترة والتخصص — ومفيش = جملة بتقول إزاي بنعرف التخصص', (tester) async {
    await pump(tester, specialty: Specialty.eyes);
    expect(find.byKey(const ValueKey('place-node/11')), findsOneWidget);
    expect(find.byKey(const ValueKey('place-node/12')), findsNothing);
    expect(find.byKey(const ValueKey('place-node/14')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester, specialty: Specialty.heart);
    expect(find.textContaining('مفيش دكتور قلب ظاهر'), findsOneWidget);
    expect(find.textContaining('مكتوب في اسم العيادة'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    screenTest('${dark ? 'ليلي' : 'نهاري'} — كل نص في الكروت والشرايح بيتقري', (tester) async {
      F.setDark(on: dark);
      addTearDown(() => F.setDark(on: false));
      await pump(tester, kind: PlaceKind.doctor);
      expectReadableText(tester, where: 'القريب مني');
    });
  }
}
