import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/features/emergency/emergency_widgets.dart' show dialNumber;
import 'package:fakkarni/features/nearby/nearby_screen.dart';

import '../../data/places/overpass_places_test.dart' show MemoryCache, sample;
import '../scan/scan_test_support.dart';

/// بلاطة شفافة — مفيش شبكة في الاختبار.
class BlankTiles extends TileProvider {
  static final _png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_png);
}

class FakeLocation implements LocationSource {
  FakeLocation(this.fix);
  LocationFix fix;
  int settingsOpened = 0;
  @override
  Future<LocationFix> current() async => fix;
  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  // الثلاثاء ١٥ سبتمبر ٢٠٢٦ الساعة ١٠ ص — «فضل» Mo-Su 09:30-21:30 فاتحة
  final tueMorning = DateTime(2026, 9, 15, 10);
  const cairo = LocationFix(LocationStatus.granted, 30.0444, 31.2357);

  late int requests;
  late List<String> dialed;
  late List<String> routed;

  // الشاشة بتاخد الواجهة المكيّشة؛ المصدر تحتها هنا Overpass على MockClient
  // (على أندرويد ده هو المصدر فعلاً، وعلى iOS الشاشة نفسها ما بتفرقش).
  NearbyPlaces overpass({Map<String, dynamic>? response, bool offline = false, MemoryCache? cache}) =>
      NearbyPlaces(
        source: OverpassPlaces(
          client: MockClient((_) async {
            requests++;
            if (offline) throw http.ClientException('no network');
            return http.Response.bytes(utf8.encode(jsonEncode(response ?? sample)), 200);
          }),
        ),
        cache: cache ?? MemoryCache(),
      );

  setUp(() {
    requests = 0;
    dialed = [];
    routed = [];
    dialNumber = (n) async => dialed.add(n);
    openDirections = (p) async => routed.add(p.id);
  });

  /// مصدر «أبل» زي ما iOS هيشوفه — من غير قناة: الشاشة ما تفرقش، والجملة بس.
  NearbyPlaces apple() => NearbyPlaces(source: _AppleLike(), cache: MemoryCache());

  Future<void> pumpNearby(WidgetTester tester, {LocationSource? location, NearbyPlaces? places}) async {
    await h.pump(
      tester,
      NearbyScreen(
        location: location ?? FakeLocation(cairo),
        places: places ?? overpass(),
        tileProvider: BlankTiles(),
        now: () => tueMorning,
      ),
    );
    await settle(tester);
  }

  screenTest('الكروت من OSM زي ما هي: الاسم، المسافة، «فاتحة» بس لو فيه تاج، «اتصل» بس لو فيه رقم — ومفيش نجوم', (tester) async {
    await pumpNearby(tester);

    expect(requests, 1);
    expect(find.text('© مساهمو OpenStreetMap'), findsOneWidget, reason: 'شرط الرخصة');
    expect(find.byKey(const ValueKey('nearby-privacy')), findsOneWidget);
  });

  screenTest('جملة الخصوصية بتسمّي اللي الموقع بيروح له فعلاً — Apple على iOS وOpenStreetMap على أندرويد — والـ© على الاتنين', (tester) async {
    await pumpNearby(tester, places: overpass());
    expect(find.text('مكانك بيتبعت لـ OpenStreetMap عشان يدوّر — التقريبي، مش مكانك بالظبط.'), findsOneWidget);
    expect(find.textContaining('Apple'), findsNothing);
    expect(find.text('© مساهمو OpenStreetMap'), findsOneWidget);

    // شجرة جديدة: الشاشة بتحتفظ بالواجهة في late final، وإعادة الضخ بنفس
    // النوع كانت هتعيد استخدام الحالة القديمة.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpNearby(tester, places: apple());
    expect(find.text('مكانك بيتبعت لـ Apple عشان يدوّر — التقريبي، مش مكانك بالظبط.'), findsOneWidget);
    expect(find.textContaining('بيتبعت لـ OpenStreetMap'), findsNothing);
    expect(find.text('© مساهمو OpenStreetMap'), findsOneWidget, reason: 'الخريطة لسه OSM على الاتنين');

    expect(find.text('Al Azaby'), findsOneWidget);
    expect(find.text('فضل'), findsOneWidget);
    expect(find.text('صيدلية من غير اسم على الخريطة'), findsOneWidget);
    expect(find.text('عيادة د. سامي'), findsOneWidget);
    expect(find.text('مش صيدلية'), findsNothing);

    expect(find.byKey(const ValueKey('open-state-node/2')), findsOneWidget);
    expect(find.text('فاتحة دلوقتي'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-state-node/1')), findsNothing, reason: 'مفيش تاج → مفيش حكم');
    expect(find.byKey(const ValueKey('open-state-node/3')), findsNothing);

    expect(find.byKey(const ValueKey('call-node/1')), findsOneWidget);
    expect(find.byKey(const ValueKey('call-node/2')), findsNothing, reason: 'مفيش رقم');

    for (final star in ['★', '⭐', 'تقييم', 'متوفر', 'توصيل', 'تأمين']) {
      expect(find.textContaining(star), findsNothing, reason: star);
    }
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expectNoRedAndMinSize(tester);

    await tester.tap(find.byKey(const ValueKey('call-node/1')));
    await tester.tap(find.byKey(const ValueKey('route-node/2')));
    await settle(tester);
    expect(dialed, ['+20 2 1234567']);
    expect(routed, ['node/2']);
  });

  screenTest('فلتر «دكاترة»، و«دوّر تاني» في نفس المكان من الكاش — مفيش طلب زيادة', (tester) async {
    await pumpNearby(tester);
    await tester.tap(find.byKey(const ValueKey('nearby-filter-doctor')));
    await settle(tester);
    expect(find.text('عيادة د. سامي'), findsOneWidget);
    expect(find.text('Al Azaby'), findsNothing);

    await tester.tap(find.text('دوّر من مكاني تاني'));
    await settle(tester);
    expect(requests, 1);
  });

  screenTest('إذن الموقع مرفوض → رسالة مفهومة و«جرّب تاني» — ومفيش طلب شبكة', (tester) async {
    await pumpNearby(tester, location: FakeLocation(const LocationFix(LocationStatus.denied)));
    expect(find.byKey(const ValueKey('nearby-no-location')), findsOneWidget);
    expect(find.text('جرّب تاني'), findsOneWidget);
    expect(requests, 0);
    expectNoRedAndMinSize(tester);
  });

  screenTest('مرفوض نهائي → «افتح الإعدادات» بيفتح الإعدادات؛ وخدمة الموقع مقفولة ليها رسالتها', (tester) async {
    final location = FakeLocation(const LocationFix(LocationStatus.deniedForever));
    await pumpNearby(tester, location: location);
    await tester.tap(find.text('افتح الإعدادات'));
    await settle(tester);
    expect(location.settingsOpened, 1);

    location.fix = const LocationFix(LocationStatus.serviceOff);
    await tester.tap(find.text('جرّب تاني'));
    await settle(tester);
    expect(find.textContaining('خدمة الموقع مقفولة'), findsOneWidget);
  });

  screenTest('من غير نت ومفيش كاش → رسالة أمينة مش شاشة فاضية', (tester) async {
    await pumpNearby(tester, places: overpass(offline: true));
    expect(find.byKey(const ValueKey('nearby-offline')), findsOneWidget);
    expect(find.text('جرّب تاني'), findsOneWidget);
  });

  screenTest('من غير نت ومعاه كاش قديم → النتايج القديمة بتاريخها', (tester) async {
    final cache = MemoryCache();
    await overpass(cache: cache).search(30.0444, 31.2357, now: DateTime(2026, 9, 10, 18));
    await pumpNearby(tester, places: overpass(offline: true, cache: cache));
    expect(find.byKey(const ValueKey('nearby-stale')), findsOneWidget);
    expect(find.textContaining('١٠ سبتمبر ٢٠٢٦'), findsOneWidget);
    expect(find.text('Al Azaby'), findsOneWidget);
  });

  screenTest('مفيش نتايج → بيقول إن التغطية ناقصة', (tester) async {
    await pumpNearby(tester, places: overpass(response: {'elements': []}));
    expect(find.byKey(const ValueKey('nearby-empty')), findsOneWidget);
    expect(find.text('© مساهمو OpenStreetMap'), findsOneWidget);
  });

  test('المسافة بالمتر تحت الكيلو، وبالكيلو فوقه', () {
    expect(distanceText(437), '٤٤٠ متر');
    expect(distanceText(1234), '١.٢ كم');
  });
}

/// مصدر بيقول «Apple» — نفس شكل نتايج MapKit، من غير قناة.
class _AppleLike implements PlacesSource {
  @override
  String get id => 'mapkit';
  @override
  String get displayName => 'Apple';
  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async => Place.fromOverpass(sample);
}
