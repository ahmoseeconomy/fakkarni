// «قريب منك» بتصميم المالك (المرحلة ج، ٦ أكتوبر ٢٠٢٦): الخريطة هي الشاشة،
// ورقة بتتسحب فيها المكان المختار بأفعاله وباقي الأماكن صفوف خفيفة، وزرار
// «القايمة»/«الخريطة»، و«موقعك الحالي» لوحدها، والـ© ظاهرة دايماً.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/primitives.dart';
import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/features/emergency/emergency_widgets.dart' show dialNumber;
import 'package:fakkarni/features/nearby/nearby_screen.dart';

import '../../data/places/overpass_places_test.dart' show MemoryCache;
import '../scan/scan_test_support.dart';
import 'nearby_screen_test.dart' show BlankTiles, FakeLocation, pickPlace;

class _Source implements PlacesSource {
  _Source(this.places);
  final List<Place> places;
  @override
  String get id => 'fake';
  @override
  String get displayName => 'OpenStreetMap';
  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async => places;
}

class _SlowLocation implements LocationSource {
  final gate = Completer<LocationFix>();
  @override
  Future<LocationFix> current() => gate.future;
  @override
  Future<void> openSettings() async {}
}

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(() async {
    F.setDark(on: false);
    await h.tearDown();
  });

  const here = LocationFix(LocationStatus.granted, 30.0444, 31.2357);
  final now = DateTime(2026, 9, 15, 10);

  const pharmacy = Place(
    id: 'ph',
    kind: PlaceKind.pharmacy,
    lat: 30.0450,
    lon: 31.2360,
    name: 'صيدلية النور',
    phone: '01012345678',
    openingHours: 'Mo-Su 09:00-22:00',
    address: '٢٥ شارع التحرير، الدقي',
  );
  const hospital = Place(id: 'hos', kind: PlaceKind.hospital, lat: 30.0460, lon: 31.2370, name: 'مستشفى القصر العيني');
  const doctor = Place(id: 'doc', kind: PlaceKind.doctor, lat: 30.0470, lon: 31.2380, name: 'د. هشام', phone: '+20 2 1234567');
  const lab = Place(id: 'lab', kind: PlaceKind.lab, lat: 30.0480, lon: 31.2390, name: 'معمل البرج');
  const all = [pharmacy, hospital, doctor, lab];

  Future<void> pump(WidgetTester tester, List<Place> places, {Size size = const Size(414, 920), LocationSource? location}) async {
    await h.pump(
      tester,
      NearbyScreen(
        location: location ?? FakeLocation(here),
        places: NearbyPlaces(source: _Source(places), cache: MemoryCache()),
        tileProvider: BlankTiles(),
        now: () => now,
      ),
    );
    // **بعد** h.pump — هو بيفرض ١٠٠٠×٣٢٠٠، فمقاس قبله كان بيضيع في صمت
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    await settle(tester);
  }

  Rect screen(WidgetTester tester) => Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;

  screenTest('الهيدر: «أماكن قريبة من موقعك»، «موقعك الحالي» لوحدها من غير اسم منطقة، وسطر الخصوصية', (tester) async {
    await pump(tester, all);
    expect(find.text('قريب منك'), findsOneWidget);
    expect(find.text('أماكن قريبة من موقعك'), findsOneWidget);
    final chip = find.byKey(const ValueKey('nearby-location-chip'));
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('موقعك الحالي')), findsOneWidget);
    // اسم المنطقة هو المرحلة د — مفيش «:» ولا اسم مخترع جنبها
    expect(find.textContaining('موقعك الحالي:'), findsNothing);
    expect(find.byKey(const ValueKey('nearby-privacy')), findsOneWidget);
  });

  screenTest('الورقة: الأقرب مختار بأفعاله، والباقي صفوف خفيفة من غير أزرار — وكل مكان مرة واحدة', (tester) async {
    await pump(tester, all);
    // الصيدلية الأقرب: كارت بأفعال
    expect(find.byKey(const ValueKey('call-ph')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-ph')), findsOneWidget);
    expect(find.byKey(const ValueKey('whatsapp-ph')), findsOneWidget);
    expect(find.byKey(const ValueKey('keep-pharmacy-ph')), findsOneWidget);
    // الباقيين صفوف — مفيش أفعال عليهم لحد ما يتختاروا
    for (final id in ['hos', 'doc', 'lab']) {
      expect(find.byKey(ValueKey('place-$id')), findsOneWidget, reason: id);
      expect(find.byKey(ValueKey('route-$id')), findsNothing, reason: 'صف خفيف — مش كارت كبير');
    }
    expect(find.text('أماكن تانية قريبة — ٣'), findsOneWidget);
    for (final p in all) {
      expect(find.text(p.name!), findsOneWidget, reason: 'مفيش اسم بيتكرّر');
    }
    // الأزرار كلها الفقاعات المشتركة — «اتصال» هو الأساسي الوحيد
    expect(find.descendant(of: find.byKey(const ValueKey('call-ph')), matching: find.byType(FPrimaryButton)), findsOneWidget);
    for (final k in ['route-ph', 'whatsapp-ph', 'keep-pharmacy-ph']) {
      expect(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(FSecondaryButton)), findsOneWidget, reason: k);
    }
    expect(find.byType(FPrimaryButton), findsOneWidget, reason: 'أساسي واحد في الشاشة');
    expectNoRedAndMinSize(tester);
  });

  screenTest('دوسة على صف بتختاره — وأفعاله بتشتغل', (tester) async {
    final dialed = <String>[];
    dialNumber = (n) async => dialed.add(n);
    await pump(tester, all);
    await pickPlace(tester, 'doc');
    expect(find.byKey(const ValueKey('route-doc')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-doc')), findsOneWidget, reason: '«احجز ميعاد عنده» على الدكتور');
    expect(find.byKey(const ValueKey('call-ph')), findsNothing, reason: 'الصيدلية رجعت صف');
    await tester.tap(find.byKey(const ValueKey('call-doc')));
    await settle(tester);
    expect(dialed, ['+20 2 1234567']);
  });

  screenTest('دوسة على دبوس بتختار مكانه', (tester) async {
    await pump(tester, all);
    await tester.tap(find.byKey(const ValueKey('pin-lab')));
    await settle(tester);
    expect(find.byKey(const ValueKey('route-lab')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-ph')), findsNothing);
  });

  screenTest('«القايمة» بتفتح الورقة لآخرها (كل الأماكن) وبتبقى «الخريطة» — والـ© فاضلة ظاهرة', (tester) async {
    await pump(tester, all);
    final sheet = find.byType(DraggableScrollableSheet);
    final collapsedTop = tester.getTopLeft(sheet.first).dy;
    double sheetTop() => tester.getRect(find.byKey(const ValueKey('nearby-rest-head'))).top;
    final headBefore = sheetTop();

    await tester.tap(find.byKey(const ValueKey('nearby-view-toggle')));
    await settle(tester);
    expect(find.text('الخريطة'), findsOneWidget, reason: 'الزرار بيقول هيرجّعك فين');
    expect(sheetTop(), lessThan(headBefore - 100), reason: 'الورقة طلعت — الصفوف بقت فوق');
    // حقوق الخريطة ما بتستخبّاش ورا الورقة المفتوحة
    final credit = tester.getRect(find.byKey(const ValueKey('osm-attribution')));
    expect(screen(tester).contains(credit.center), isTrue);
    expect(credit.bottom, lessThanOrEqualTo(tester.getTopLeft(sheet.first).dy + tester.getSize(sheet.first).height), reason: 'جوّه الشاشة');
    // كل الأماكن بتوصلها جوّه الورقة المفتوحة — بالتمرير لو كتير
    for (final id in ['hos', 'doc', 'lab']) {
      final row = find.byKey(ValueKey('place-$id'));
      await tester.ensureVisible(row);
      await settle(tester);
      expect(screen(tester).contains(tester.getCenter(row)), isTrue, reason: id);
    }
    expect(find.text('الخريطة'), findsOneWidget, reason: 'التمرير جوّه القايمة ما قفلهاش');

    await tester.tap(find.byKey(const ValueKey('nearby-view-toggle')));
    await settle(tester);
    expect(find.text('القايمة'), findsOneWidget);
    expect(tester.getTopLeft(sheet.first).dy, closeTo(collapsedTop, 2), reason: 'رجعت مكانها');
  });

  screenTest('الصف من «القايمة» بيختار وبيرجّع الورقة مكانها', (tester) async {
    await pump(tester, all);
    await tester.tap(find.byKey(const ValueKey('nearby-view-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('place-hos')));
    await settle(tester);
    expect(find.byKey(const ValueKey('route-hos')), findsOneWidget);
    expect(find.text('القايمة'), findsOneWidget, reason: 'الورقة نزلت تاني — الخريطة قدّامه');
  });

  screenTest('المستشفى مش أحمر — لا على البلاطة ولا على الدبوس', (tester) async {
    await pump(tester, [hospital]);
    for (final tile in tester.widgetList<Container>(find.byKey(const ValueKey('kind-tile-hospital')))) {
      final deco = tile.decoration! as BoxDecoration;
      expect(deco.color, isNot(anyOf(F.red, F.redDeep, F.outOfRangeInk, F.careAlertInk)));
    }
    final icons = tester.widgetList<Icon>(find.descendant(of: find.byKey(const ValueKey('pin-hos')), matching: find.byType(Icon)));
    for (final i in icons) {
      expect(i.color, isNot(anyOf(F.red, F.redDeep)));
    }
    expect(kindStyle(PlaceKind.hospital).bg, isNot(F.red));
  });

  screenTest('نقطتك أخضر التطبيق — مش أزرق (الأزرق للمية)', (tester) async {
    await pump(tester, all);
    final dot = find.byKey(const ValueKey('nearby-you'));
    final colors = [
      for (final c in tester.widgetList<Container>(find.descendant(of: dot, matching: find.byType(Container))))
        (c.decoration as BoxDecoration?)?.color,
    ].nonNulls.map((c) => c.withValues(alpha: 1)).toSet();
    expect(colors, contains(F.green.withValues(alpha: 1)));
    expect(colors.any((c) => c == F.waterDrop || c == F.waterInk), isFalse);
  });

  screenTest('بيدوّر → كارت «بندوّر…» مش خريطة فاضية', (tester) async {
    final slow = _SlowLocation();
    await h.pump(
      tester,
      NearbyScreen(location: slow, places: NearbyPlaces(source: _Source(all), cache: MemoryCache()), tileProvider: BlankTiles(), now: () => now),
    );
    tester.view.physicalSize = const Size(414, 920) * 3;
    tester.view.devicePixelRatio = 3;
    await tester.pump();
    expect(find.byKey(const ValueKey('nearby-loading')), findsOneWidget);
    expect(find.textContaining('بندوّر على الأماكن'), findsOneWidget);
    expect(find.byKey(const ValueKey('osm-attribution')), findsNothing, reason: 'لسه مفيش خريطة');
    slow.gate.complete(here);
    await settle(tester);
    expect(find.byKey(const ValueKey('nearby-loading')), findsNothing);
  });

  screenTest('مفيش إذن: كارت بأيقونة وجملة و«جرّب تاني» كبير — ومفيش شريحة «موقعك الحالي»', (tester) async {
    await pump(tester, all, location: FakeLocation(const LocationFix(LocationStatus.denied)));
    expect(find.byKey(const ValueKey('nearby-no-location')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('nearby-no-location')), matching: find.byType(FPrimaryButton)), findsOneWidget);
    expect(find.byKey(const ValueKey('nearby-location-chip')), findsNothing, reason: 'من غير موقع الشريحة كانت هتبقى كدبة');
    expect(find.byKey(const ValueKey('nearby-filter-all')), findsNothing, reason: 'مفيش نتايج تتفلتر');
    expectNoRedAndMinSize(tester);
  });

  screenTest('مفيش نتايج: الخريطة بنقطتك + جملة واضحة في الورقة — عمرها ما تبقى خريطة فاضية من غير كلام', (tester) async {
    await pump(tester, const []);
    expect(find.byKey(const ValueKey('nearby-you')), findsOneWidget);
    final empty = find.byKey(const ValueKey('nearby-empty'));
    expect(empty, findsOneWidget);
    expect(screen(tester).contains(tester.getCenter(empty)), isTrue, reason: 'الجملة جوّه الشاشة');
    expect(find.byKey(const ValueKey('osm-attribution')), findsOneWidget);
  });

  group('آيفون SE (٣٧٥×٦٦٧) بالخطوط الحقيقية', () {
    setUpAll(() async {
      final loader = FontLoader('Cairo');
      for (final f in ['Cairo-Regular.ttf', 'Cairo-Medium.ttf', 'Cairo-SemiBold.ttf', 'Cairo-Bold.ttf', 'Cairo-ExtraBold.ttf']) {
        loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
      }
      await loader.load();
    });

    screenTest('الورقة المقفولة فيها اسم المختار و«اتصال» كامل — والزرارين على حافتها مش فوق الخريطة', (tester) async {
      await pump(tester, all, size: const Size(375, 667));
      final shown = screen(tester);
      final call = tester.getRect(find.byKey(const ValueKey('call-ph')));
      expect(shown.contains(call.topLeft) && shown.contains(call.bottomRight), isTrue, reason: '«اتصال» كامل: $call');
      expect(shown.contains(tester.getCenter(find.byKey(const ValueKey('place-name-ph')))), isTrue);
      for (final k in ['osm-attribution', 'nearby-research', 'nearby-view-toggle']) {
        final r = tester.getRect(find.byKey(ValueKey(k)));
        expect(shown.contains(r.topLeft) && shown.contains(r.bottomRight), isTrue, reason: '$k: $r');
      }
      final sheetTop = tester.getTopLeft(find.byType(DraggableScrollableSheet).first).dy;
      for (final k in ['nearby-research', 'nearby-view-toggle']) {
        final control = find.byKey(ValueKey(k));
        expect(find.descendant(of: find.byType(DraggableScrollableSheet), matching: control), findsOneWidget,
            reason: '$k جوّه الورقة، مش عايم فوق الخريطة');
        expect(tester.getRect(control).top, greaterThanOrEqualTo(sheetTop), reason: '$k على الورقة، مش فوق الخريطة');
      }
      expect(tester.takeException(), isNull);
    });

    screenTest('خط ×١٫٣: مفيش فيض', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, all, size: const Size(375, 667));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('nearby-filter-doctor')));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  test('مقاسات الورقة: المقفولة كفاية للكارت، والمفتوحة سايبة شريط للزرارين والـ©', () {
    for (final height in [380.0, 420.0, 560.0, 700.0]) {
      final s = nearbySheetSizes(height);
      expect(s.collapsed, lessThanOrEqualTo(s.max), reason: '$height');
      final strip = height * (1 - s.max);
      expect(strip, greaterThanOrEqualTo(F.minTapTarget + 34), reason: 'شريط الخريطة فوق الورقة المفتوحة: $height');
    }
  });

  test('الشاشة القصيرة بتحجز صف التحكم جوّه الورقة', () {
    const height = 560.0;
    final normal = nearbySheetSizes(height);
    final short = nearbySheetSizes(height, controlsOnSheet: true);
    expect(short.collapsed, greaterThan(normal.collapsed), reason: 'زرارين كبار بقوا جوّه الورقة');
    expect(short.collapsed, lessThanOrEqualTo(short.max));
  });
}
