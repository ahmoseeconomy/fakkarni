import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/data/places/places.dart';

class MemoryCache implements PlacesCache {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

const sample = {
  'elements': [
    {
      'type': 'node',
      'id': 1,
      'lat': 30.0472,
      'lon': 31.2386,
      'tags': {'amenity': 'pharmacy', 'name': 'Al Azaby', 'phone': '+20 2 1234567'},
    },
    {
      'type': 'node',
      'id': 2,
      'lat': 30.0448,
      'lon': 31.2470,
      'tags': {'amenity': 'pharmacy', 'name': 'Fadl', 'name:ar': 'فضل', 'opening_hours': 'Mo-Su 09:30-21:30'},
    },
    {'type': 'node', 'id': 3, 'lat': 30.045, 'lon': 31.2465, 'tags': {'amenity': 'pharmacy'}},
    {
      'type': 'way',
      'id': 4,
      'center': {'lat': 30.046, 'lon': 31.240},
      'tags': {'healthcare': 'doctor', 'name': 'عيادة د. سامي'},
    },
    {'type': 'node', 'id': 5, 'lat': 30.0, 'lon': 31.0, 'tags': {'amenity': 'cafe', 'name': 'مش صيدلية'}},
  ],
};

void main() {
  test('التحليل: الصيدليات والدكاترة زي ما هم، الاسم العربي لو موجود، والمجهول من غير اسم', () {
    final places = Place.fromOverpass(sample);
    expect(places, hasLength(4));
    expect(places[0].phone, '+20 2 1234567');
    expect(places[1].name, 'فضل');
    expect(places[1].openingHours, 'Mo-Su 09:30-21:30');
    expect(places[2].name, isNull, reason: 'مش هنخترع اسم');
    expect(places[2].openingHours, isNull);
    expect(places[3].kind, PlaceKind.doctor);
    expect(places[3].lat, 30.046);
  });

  test('استعلام واحد لكل بحث، والنقطة مقرّبة قبل ما تخرج، وهوية التطبيق في الطلب — والبحث التاني من الكاش', () async {
    final requests = <http.Request>[];
    final client = MockClient((req) async {
      requests.add(req);
      return http.Response.bytes(utf8.encode(jsonEncode(sample)), 200);
    });
    final places = OverpassPlaces(client: client, cache: MemoryCache());
    final now = DateTime(2026, 9, 15, 10);

    final first = await places.search(30.044412345, 31.235712345, now: now);
    final second = await places.search(30.04438, 31.23572, now: now.add(const Duration(hours: 2)));

    expect(requests, hasLength(1));
    expect(requests.single.headers['User-Agent'], OverpassPlaces.userAgent);
    final body = Uri.decodeQueryComponent(requests.single.body);
    expect(body, contains('around:2000,30.044,31.236'));
    expect(body, isNot(contains('30.0444')), reason: 'المكان الدقيق ما بيطلعش');
    expect(body, contains('"amenity"="pharmacy"'));
    expect(body, contains('"healthcare"="doctor"'));
    expect(first.fromCache, isFalse);
    expect(second.fromCache, isTrue);
    expect(second.places, hasLength(4));
  });

  test('بعد ٢٤ ساعة بيدوّر تاني', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes(utf8.encode(jsonEncode(sample)), 200);
    });
    final places = OverpassPlaces(client: client, cache: MemoryCache());
    final now = DateTime(2026, 9, 15, 10);
    await places.search(30.044, 31.236, now: now);
    await places.search(30.044, 31.236, now: now.add(const Duration(hours: 25)));
    expect(calls, 2);
  });

  test('من غير نت ومفيش كاش → PlacesOffline؛ ومع كاش قديم → النتايج القديمة معلّمة offline', () async {
    final offline = MockClient((_) async => throw http.ClientException('no network'));
    expect(() => OverpassPlaces(client: offline, cache: MemoryCache()).search(30.044, 31.236), throwsA(isA<PlacesOffline>()));

    final cache = MemoryCache();
    final online = MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode(sample)), 200));
    await OverpassPlaces(client: online, cache: cache).search(30.044, 31.236, now: DateTime(2026, 9, 10));
    final stale = await OverpassPlaces(client: offline, cache: cache).search(30.044, 31.236, now: DateTime(2026, 9, 15));
    expect(stale.offline, isTrue);
    expect(stale.fetchedAt, DateTime(2026, 9, 10));
    expect(stale.places, hasLength(4));
  });
}
