import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/places/places.dart';

import 'overpass_places_test.dart' show MemoryCache;

/// عقد [PlacesSource] — نفس الاختبارات على مصدر مزيّف وعلى مصدر خرايط أبل
/// بقناة مزيّفة. الجزء السويفت نفسه برّه `flutter test`؛ اللي بيتثبت هنا
/// إن أي مصدر بيرجّع [Place] الشاشة تعرف تعرضه، وإن الواجهة المكيّشة
/// ([NearbyPlaces]) بتعامل المصدرين بنفس الطريقة.
class FakeSource implements PlacesSource {
  FakeSource(this.places, {this.fail = false, this.id = 'fake', this.displayName = 'Fake'});
  final List<Place> places;
  bool fail;
  @override
  final String id;
  @override
  final String displayName;
  final calls = <(double lat, double lon, int radius)>[];

  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async {
    calls.add((lat, lon, radiusMeters));
    if (fail) throw StateError('down');
    return places;
  }
}

const cairo = (lat: 30.0444, lon: 31.2357);

final samplePlaces = [
  const Place(id: 'x/1', kind: PlaceKind.pharmacy, lat: 30.0472, lon: 31.2386, name: 'Al Azaby', phone: '+20 2 1234567'),
  const Place(id: 'x/2', kind: PlaceKind.doctor, lat: 30.046, lon: 31.240, name: 'عيادة د. سامي'),
  const Place(id: 'x/3', kind: PlaceKind.pharmacy, lat: 30.045, lon: 31.2465),
  const Place(id: 'x/4', kind: PlaceKind.hospital, lat: 30.0450, lon: 31.2420, name: 'مستشفى القصر العيني'),
  const Place(id: 'x/5', kind: PlaceKind.lab, lat: 30.0440, lon: 31.2440, name: 'معمل البرج'),
];

/// صفوف زي ما `PlacesChannel.swift` بيبعتها.
const channelRows = <Object?>[
  {'id': 'mapkit/I1', 'kind': 'pharmacy', 'name': 'Al Azaby', 'lat': 30.0472, 'lon': 31.2386, 'phone': '+20 2 1234567'},
  {'id': 'mapkit/I2', 'kind': 'doctor', 'name': 'عيادة د. سامي', 'lat': 30.046, 'lon': 31.240},
  {'id': 'mapkit/I3', 'kind': 'pharmacy', 'lat': 30.045, 'lon': 31.2465},
  {'id': 'mapkit/I4', 'kind': 'hospital', 'name': 'مستشفى القصر العيني', 'lat': 30.0450, 'lon': 31.2420},
  {'id': 'mapkit/I5', 'kind': 'lab', 'name': 'معمل البرج', 'lat': 30.0440, 'lon': 31.2440},
];

void runContract(String name, PlacesSource Function() make) {
  group('عقد المصدر — $name', () {
    test('بيرجّع أماكن بمعرّف وإحداثيات ونوع من الأربعة، وبيقبل المجهول من غير اسم', () async {
      final places = await make().nearby(cairo.lat, cairo.lon, 2000);

      expect(places, hasLength(5));
      for (final p in places) {
        expect(p.id, isNotEmpty);
        expect(p.lat, inInclusiveRange(-90, 90));
        expect(p.lon, inInclusiveRange(-180, 180));
      }
      expect(places.map((p) => p.kind).toSet(), PlaceKind.values.toSet(), reason: 'الأربع أنواع');
      expect(places.where((p) => p.name == null), hasLength(1), reason: 'من غير اسم ≠ متشال');
      expect(places.first.phone, '+20 2 1234567');
    });

    test('المعرّف بيمشي في الكاش وبيرجع زي ما هو — الشاشة بتفتح الطريق بيه', () async {
      final places = await make().nearby(cairo.lat, cairo.lon, 2000);
      for (final p in places) {
        expect(Place.fromJson(p.toJson()).id, p.id);
        expect(Place.fromJson(p.toJson()).kind, p.kind);
      }
    });

    test('من غير تقييم — الموديل مفيهوش حقل ليه أصلاً', () async {
      final p = (await make().nearby(cairo.lat, cairo.lon, 2000)).first;
      expect(p.toJson().keys, isNot(contains('rating')));
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runContract('مصدر مزيّف', () => FakeSource(samplePlaces));

  group('خرايط أبل على قناة مزيّفة', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? received;
    setUp(() {
      received = null;
      messenger.setMockMethodCallHandler(AppleMapKitPlaces.channel, (call) async {
        received = call;
        return channelRows;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(AppleMapKitPlaces.channel, null));

    runContract('خرايط أبل', () => const AppleMapKitPlaces());

    test('بينادي nearby بـlat/lon/radiusMeters زي ما سويفت مستنيهم — ومفيش شبكة في دارت', () async {
      await const AppleMapKitPlaces().nearby(30.044, 31.236, 2000);
      expect(received!.method, 'nearby');
      expect(received!.arguments, {'lat': 30.044, 'lon': 31.236, 'radiusMeters': 2000});
    });

    test('مواعيد الفتح null دايماً — MapKit ما بيدّيهاش، وما بنخمّنهاش', () async {
      final places = await const AppleMapKitPlaces().nearby(30.044, 31.236, 2000);
      expect(places.every((p) => p.openingHours == null), isTrue);
    });

    test('صف ناقص أو نوع غريب بيتعدّى من غير ما يرمي، والمعرّف الناقص بيتبني من الإحداثيات', () {
      final places = AppleMapKitPlaces.fromChannel([
        {'kind': 'pharmacy', 'lat': 30.0, 'lon': 31.0},
        {'id': 'mapkit/x', 'kind': 'dentist', 'lat': 30.0, 'lon': 31.0},
        {'id': 'mapkit/y', 'kind': 'doctor'},
        'not a map',
        null,
      ]);
      expect(places, hasLength(1));
      expect(places.single.id, 'mapkit/30.0,31.0');
    });

    test('القناة وقعت → المصدر بيرمي، والواجهة هي اللي بتترجم', () async {
      messenger.setMockMethodCallHandler(AppleMapKitPlaces.channel, (call) async {
        throw PlatformException(code: 'mapkit', message: 'MKErrorDomain 4');
      });
      expect(() => const AppleMapKitPlaces().nearby(30.044, 31.236, 2000), throwsA(isA<PlatformException>()));
      expect(
        () => NearbyPlaces(source: const AppleMapKitPlaces(), cache: MemoryCache()).search(30.044, 31.236),
        throwsA(isA<PlacesOffline>()),
      );
    });
  });

  group('الواجهة المكيّشة فوق أي مصدر', () {
    test('النقطة بتتقرّب قبل ما توصل المصدر، والراديوس بيتبعت، والبحث التاني من الكاش', () async {
      final source = FakeSource(samplePlaces);
      final nearby = NearbyPlaces(source: source, cache: MemoryCache());
      final now = DateTime(2026, 9, 15, 10);

      final first = await nearby.search(30.044412345, 31.235712345, now: now);
      final second = await nearby.search(30.04438, 31.23572, now: now.add(const Duration(hours: 2)));

      expect(source.calls, [(30.044, 31.236, 2000)]);
      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(second.places.map((p) => p.id), samplePlaces.map((p) => p.id));
    });

    test('مفتاح الكاش فيه اسم المصدر ومجموعة الأنواع — صفوف قديمة ناقصة نوع ما تتقراش', () async {
      final cache = MemoryCache();
      await NearbyPlaces(source: FakeSource(samplePlaces), cache: cache).search(30.044, 31.236);
      expect(cache.map.keys.single, contains(':fake:'));
      expect(cache.map.keys.single, contains('pharmacy,doctor,hospital,lab'));

      final other = FakeSource(const [], id: 'other');
      final result = await NearbyPlaces(source: other, cache: cache).search(30.044, 31.236);
      expect(other.calls, hasLength(1), reason: 'مصدر تاني = بحث جديد');
      expect(result.places, isEmpty);
    });

    test('المصدر وقع: مع كاش قديم → القديم معلّم offline، ومن غيره → PlacesOffline', () async {
      final cache = MemoryCache();
      await NearbyPlaces(source: FakeSource(samplePlaces), cache: cache).search(30.044, 31.236, now: DateTime(2026, 9, 10));

      final stale = await NearbyPlaces(source: FakeSource(const [], fail: true), cache: cache)
          .search(30.044, 31.236, now: DateTime(2026, 9, 15));
      expect(stale.offline, isTrue);
      expect(stale.fetchedAt, DateTime(2026, 9, 10));
      expect(stale.places, hasLength(5));

      expect(
        () => NearbyPlaces(source: FakeSource(const [], fail: true), cache: MemoryCache()).search(30.044, 31.236),
        throwsA(isA<PlacesOffline>()),
      );
    });
  });
}
