import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// نوع المكان — اللي OSM بيقوله، مش تخمين.
enum PlaceKind { pharmacy, doctor }

/// مكان من OpenStreetMap زي ما هو. **مفيش تقييم** — OSM مفيهاش تقييمات.
class Place {
  const Place({
    required this.id,
    required this.kind,
    required this.lat,
    required this.lon,
    this.name,
    this.phone,
    this.openingHours,
  });

  final String id;
  final PlaceKind kind;
  final double lat, lon;
  final String? name;
  final String? phone;

  /// التاج بالحرف — null لو مش متسجّل.
  final String? openingHours;

  static List<Place> fromOverpass(Map<String, dynamic> json) {
    final elements = json['elements'];
    if (elements is! List) return const [];
    final places = <Place>[];
    for (final e in elements) {
      if (e is! Map) continue;
      final tags = e['tags'];
      if (tags is! Map) continue;
      final lat = (e['lat'] ?? (e['center'] is Map ? e['center']['lat'] : null));
      final lon = (e['lon'] ?? (e['center'] is Map ? e['center']['lon'] : null));
      if (lat is! num || lon is! num) continue;
      final kind = tags['amenity'] == 'pharmacy'
          ? PlaceKind.pharmacy
          : (tags['amenity'] == 'doctors' || tags['healthcare'] == 'doctor')
              ? PlaceKind.doctor
              : null;
      if (kind == null) continue;
      String? tag(String k) {
        final v = tags[k];
        return v is String && v.trim().isNotEmpty ? v.trim() : null;
      }

      places.add(Place(
        id: '${e['type']}/${e['id']}',
        kind: kind,
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        name: tag('name:ar') ?? tag('name'),
        phone: tag('phone') ?? tag('contact:phone'),
        openingHours: tag('opening_hours'),
      ));
    }
    return places;
  }
}

/// نتيجة بحث: الأماكن، وجت إمتى، ومن الكاش ولا من الشبكة.
class PlacesResult {
  const PlacesResult({required this.places, required this.fetchedAt, required this.fromCache, this.offline = false});

  final List<Place> places;
  final DateTime fetchedAt;
  final bool fromCache;

  /// الشبكة فشلت ودي نتايج قديمة — الشاشة بتقول كده.
  final bool offline;
}

class PlacesOffline implements Exception {
  const PlacesOffline(this.cause);
  final Object cause;
}

/// التخزين المؤقت — نتيجة البحث لنقطة مقرّبة ونصف قطر.
abstract interface class PlacesCache {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PrefsPlacesCache implements PlacesCache {
  const PrefsPlacesCache();

  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

/// Overpass API — **استعلام واحد لكل بحث** (صيدليات ودكاترة مع بعض)، وكاش
/// ٢٤ ساعة، ونقطة مقرّبة لـ٣ أرقام عشرية (~١١٠ متر) قبل ما تخرج من الموبايل.
/// سياسة الاستخدام: https://dev.overpass-api.de/overpass-doc/en/preface/commons.html
///
/// الـinstance العام للتجربة والاستخدام الصغير؛ تطبيق لناس كتير محتاج
/// instance بتاعه (مكتوب في «دين تقني»).
class OverpassPlaces {
  OverpassPlaces({http.Client? client, this.cache = const PrefsPlacesCache()}) : _client = client ?? http.Client();

  final http.Client _client;
  final PlacesCache cache;

  static final endpoint = Uri.parse('https://overpass-api.de/api/interpreter');
  static const radiusMeters = 2000;
  static const cacheFor = Duration(hours: 24);

  /// هوية التطبيق — مطلوبة بسياسة OSM (مش هوية المكتبة الافتراضية).
  static const userAgent = 'Fakkarni/1.0 (com.fakkarni.fakkarni)';

  static double round3(double v) => (v * 1000).roundToDouble() / 1000;

  static String query(double lat, double lon) {
    final around = '(around:$radiusMeters,$lat,$lon)';
    return '[out:json][timeout:25];('
        'nwr["amenity"="pharmacy"]$around;'
        'nwr["amenity"="doctors"]$around;'
        'nwr["healthcare"="doctor"]$around;'
        ');out center tags;';
  }

  Future<PlacesResult> search(double latitude, double longitude, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final lat = round3(latitude), lon = round3(longitude);
    final key = 'places:$lat:$lon:$radiusMeters';

    ({DateTime at, List<Place> places})? cached;
    final raw = await cache.read(key);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        cached = (
          at: DateTime.fromMillisecondsSinceEpoch(json['fetchedAtMs'] as int),
          places: Place.fromOverpass(json['response'] as Map<String, dynamic>),
        );
      } catch (_) {
        cached = null;
      }
    }
    if (cached != null && at.difference(cached.at) < cacheFor) {
      return PlacesResult(places: cached.places, fetchedAt: cached.at, fromCache: true);
    }

    try {
      final response = await _client
          .post(endpoint, headers: {'User-Agent': userAgent}, body: {'data': query(lat, lon)})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}');
      final body = utf8.decode(response.bodyBytes);
      final json = jsonDecode(body) as Map<String, dynamic>;
      await cache.write(key, jsonEncode({'fetchedAtMs': at.millisecondsSinceEpoch, 'response': json}));
      return PlacesResult(places: Place.fromOverpass(json), fetchedAt: at, fromCache: false);
    } catch (error) {
      debugPrint('Overpass: $error');
      if (cached != null) {
        return PlacesResult(places: cached.places, fetchedAt: cached.at, fromCache: true, offline: true);
      }
      throw PlacesOffline(error);
    }
  }
}

enum LocationStatus { granted, denied, deniedForever, serviceOff }

class LocationFix {
  const LocationFix(this.status, [this.lat, this.lon]);
  final LocationStatus status;
  final double? lat, lon;
}

/// إذن الموقع **وقت ما الشاشة تتفتح بس**.
abstract interface class LocationSource {
  Future<LocationFix> current();
  Future<void> openSettings();
}

class DeviceLocation implements LocationSource {
  const DeviceLocation();

  @override
  Future<LocationFix> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return const LocationFix(LocationStatus.serviceOff);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return const LocationFix(LocationStatus.denied);
    if (permission == LocationPermission.deniedForever) return const LocationFix(LocationStatus.deniedForever);
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
    );
    return LocationFix(LocationStatus.granted, p.latitude, p.longitude);
  }

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();
}
