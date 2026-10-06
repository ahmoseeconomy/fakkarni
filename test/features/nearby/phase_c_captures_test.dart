// لقطات المرحلة ج — «قريب منك» بتصميم المالك: نهاري وليلي، موبايل صغير
// (SE ٣٧٥×٦٦٧) وكبير (٤٣٠×٩٣٢)، والقايمة مفتوحة، والحالات (مفيش إذن، مفيش
// نت، مفيش نتايج). بلاطات الخريطة **مرسومة في الاختبار** (مفيش شبكة) —
// على الجهاز هي بلاطات OpenStreetMap الحقيقية.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/features/nearby/nearby_screen.dart';

import '../../data/places/overpass_places_test.dart' show MemoryCache;
import '../scan/scan_test_support.dart';
import 'nearby_screen_test.dart' show FakeLocation;

class _Source implements PlacesSource {
  _Source(this.places, {this.offline = false});
  final List<Place> places;
  final bool offline;
  @override
  String get id => 'fake';
  @override
  String get displayName => 'OpenStreetMap';
  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async {
    if (offline) throw const PlacesOffline('offline');
    return places;
  }
}

/// بلاطة شبه خريطة — أرضية فاتحة وشوارع بيضا — عشان اللقطة ما تبقاش فاضية.
class _PaintedTiles extends TileProvider {
  _PaintedTiles(this.png);
  final Uint8List png;
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(png);
}

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(() async {
    F.setDark(on: false);
    await h.tearDown();
  });

  late Uint8List tile;

  setUpAll(() async {
    final cairo = FontLoader('Cairo');
    for (final f in ['Cairo-Regular.ttf', 'Cairo-Medium.ttf', 'Cairo-SemiBold.ttf', 'Cairo-Bold.ttf', 'Cairo-ExtraBold.ttf']) {
      cairo.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await cairo.load();
    // الأيقونات — من غيرها بتطلع مربعات في اللقطة
    final home = Platform.environment['HOME'];
    final icons = File('$home/develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
    }
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 256, 256), Paint()..color = const Color(0xFFECE9E2));
    final block = Paint()..color = const Color(0xFFE2DED4);
    for (final r in [const Rect.fromLTWH(14, 14, 90, 70), const Rect.fromLTWH(140, 20, 100, 60), const Rect.fromLTWH(20, 150, 80, 90), const Rect.fromLTWH(150, 140, 90, 100)]) {
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), block);
    }
    final park = Paint()..color = const Color(0xFFD5E6CF);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(150, 150, 50, 40), const Radius.circular(4)), park);
    final road = Paint()..color = const Color(0xFFFFFFFF);
    c.drawRect(const Rect.fromLTWH(0, 112, 256, 22), road);
    c.drawRect(const Rect.fromLTWH(116, 0, 18, 256), road);
    c.drawRect(const Rect.fromLTWH(0, 0, 256, 6), road);
    final img = await rec.endRecording().toImage(256, 256);
    tile = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });

  const here = LocationFix(LocationStatus.granted, 30.0444, 31.2357);
  final now = DateTime(2026, 9, 15, 10);

  const places = [
    Place(
      id: 'ph',
      kind: PlaceKind.pharmacy,
      lat: 30.0472,
      lon: 31.2372,
      name: 'صيدلية النور',
      phone: '01012345678',
      openingHours: 'Mo-Su 09:00-23:00',
      address: '٢٥ شارع عباس العقاد، مدينة نصر',
    ),
    Place(id: 'doc', kind: PlaceKind.doctor, lat: 30.0425, lon: 31.2390, name: 'عيادة د. هشام للعيون', phone: '+20 2 1234567'),
    Place(id: 'hos', kind: PlaceKind.hospital, lat: 30.0480, lon: 31.2320, name: 'مستشفى القصر العيني'),
    Place(id: 'lab', kind: PlaceKind.lab, lat: 30.0410, lon: 31.2330, name: 'معمل البرج'),
    Place(id: 'ph2', kind: PlaceKind.pharmacy, lat: 30.0500, lon: 31.2400, name: 'صيدلية العزبي', phone: '+20 2 22223333'),
  ];

  Future<void> shot(
    WidgetTester tester,
    String name, {
    required bool dark,
    required Size size,
    List<Place> data = places,
    LocationFix fix = here,
    bool offline = false,
    Future<void> Function()? before,
  }) async {
    F.setDark(on: dark);
    await h.pump(
      tester,
      RepaintBoundary(
        key: const ValueKey('capture-root'),
        child: NearbyScreen(
          location: FakeLocation(fix),
          places: NearbyPlaces(source: _Source(data, offline: offline), cache: MemoryCache()),
          tileProvider: _PaintedTiles(tile),
          now: () => now,
        ),
      ),
    );
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    await settle(tester);
    if (before != null) await before();
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture-root')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/capture/phase-c/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  const small = Size(375, 667);
  const large = Size(430, 932);

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';
    screenTest('لقطة $mode — صغير', (tester) => shot(tester, 'map-small-$mode', dark: dark, size: small));
    screenTest('لقطة $mode — كبير', (tester) => shot(tester, 'map-large-$mode', dark: dark, size: large));
    screenTest('لقطة $mode — مفيش إذن', (tester) => shot(tester, 'no-permission-$mode', dark: dark, size: small, fix: const LocationFix(LocationStatus.deniedForever)));
    screenTest('لقطة $mode — مفيش نت', (tester) => shot(tester, 'offline-$mode', dark: dark, size: small, offline: true));
    screenTest('لقطة $mode — مفيش نتايج', (tester) => shot(tester, 'empty-$mode', dark: dark, size: small, data: const []));
  }

  screenTest('لقطة — القايمة مفتوحة (كبير، نهاري)', (tester) => shot(
        tester,
        'list-open-large-day',
        dark: false,
        size: large,
        before: () async {
          await tester.tap(find.byKey(const ValueKey('nearby-view-toggle')));
          await settle(tester);
        },
      ));

  screenTest('لقطة — «دكاترة» بالتخصصات (صغير، نهاري)', (tester) => shot(
        tester,
        'doctors-small-day',
        dark: false,
        size: small,
        before: () async {
          await tester.tap(find.byKey(const ValueKey('nearby-filter-doctor')));
          await settle(tester);
        },
      ));
}
