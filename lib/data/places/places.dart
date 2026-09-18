import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// نوع المكان — اللي OSM بيقوله، مش تخمين.
enum PlaceKind { pharmacy, doctor }

/// مكان زي ما المصدر قاله. **مفيش تقييم** — لا OSM ولا MapKit عندهم تقييمات
/// بنقدر نعرضها، ونجمة مخترعة على صيدلية حقيقية كذبة على ناس.
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

  /// للكاش — الشكل بتاعنا، مش شكل المصدر، عشان المصدرين يتخزّنوا بنفس الطريقة.
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'lat': lat,
        'lon': lon,
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (openingHours != null) 'openingHours': openingHours,
      };

  static Place fromJson(Map<String, dynamic> json) => Place(
        id: json['id'] as String,
        kind: PlaceKind.values.byName(json['kind'] as String),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        name: json['name'] as String?,
        phone: json['phone'] as String?,
        openingHours: json['openingHours'] as String?,
      );

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

/// مصدر الأماكن — **دالة واحدة**: الصيدليات والدكاترة حوالين نقطة.
///
/// مفيش كاش هنا ولا تقريب — ده شغل [NearbyPlaces]. المصدر بيجيب وبس، وبيرمي
/// لو ما قدرش (شبكة، قناة، أي حاجة) — والواجهة هي اللي بتحوّل الرمية لـ
/// «من غير نت» أو للنتايج القديمة.
abstract interface class PlacesSource {
  /// اسم قصير بيدخل في مفتاح الكاش — نتايج مصدر ما تتقراش كنتايج التاني.
  String get id;

  /// الاسم اللي المستخدم بيشوفه في جملة الخصوصية: «مكانك بيتبعت لـ …».
  /// لازم يبقى اسم اللي **الموقع بيروح له فعلاً**، مش اسم الخريطة.
  String get displayName;

  Future<List<Place>> nearby(double lat, double lon, int radiusMeters);
}

/// **المكان الوحيد** اللي بيختار المصدر: iOS → خرايط أبل، وغيره → Overpass.
///
/// `test/data/places/places_source_switch_test.dart` بيقرا `lib/` وبيقع لو
/// الاختيار ده اتكرر في مكان تاني.
PlacesSource placesSourceForPlatform({http.Client? client}) =>
    Platform.isIOS ? AppleMapKitPlaces() : OverpassPlaces(client: client);

/// البحث زي ما الشاشة بتشوفه: كاش ٢٤ ساعة، نقطة مقرّبة لـ٣ أرقام عشرية
/// (~١١٠ متر) **قبل** ما تخرج من الموبايل، ونتايج قديمة لما النت يقع.
///
/// الكاش بيخزّن [Place] بشكلنا إحنا مش بشكل المصدر — فالمصدرين متساويين
/// قدامه، ومفتاحه فيه اسم المصدر.
class NearbyPlaces {
  NearbyPlaces({required this.source, this.cache = const PrefsPlacesCache()});

  /// المصدر بيتختار بالمنصة — مرة واحدة، في [placesSourceForPlatform].
  NearbyPlaces.forPlatform() : this(source: placesSourceForPlatform());

  final PlacesSource source;
  final PlacesCache cache;

  /// الشاشة بتسأل هنا ومش بتسمّي مصدر بنفسها.
  String get sourceName => source.displayName;

  static const radiusMeters = 2000;
  static const cacheFor = Duration(hours: 24);

  static double round3(double v) => (v * 1000).roundToDouble() / 1000;

  Future<PlacesResult> search(double latitude, double longitude, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final lat = round3(latitude), lon = round3(longitude);
    final key = 'places:v2:${source.id}:$lat:$lon:$radiusMeters';

    ({DateTime at, List<Place> places})? cached;
    final raw = await cache.read(key);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        cached = (
          at: DateTime.fromMillisecondsSinceEpoch(json['fetchedAtMs'] as int),
          places: [for (final p in json['places'] as List) Place.fromJson(p as Map<String, dynamic>)],
        );
      } catch (_) {
        cached = null;
      }
    }
    if (cached != null && at.difference(cached.at) < cacheFor) {
      return PlacesResult(places: cached.places, fetchedAt: cached.at, fromCache: true);
    }

    try {
      final places = await source.nearby(lat, lon, radiusMeters).timeout(const Duration(seconds: 30));
      await cache.write(
        key,
        jsonEncode({'fetchedAtMs': at.millisecondsSinceEpoch, 'places': [for (final p in places) p.toJson()]}),
      );
      return PlacesResult(places: places, fetchedAt: at, fromCache: false);
    } catch (error) {
      debugPrint('Places(${source.id}): $error');
      if (cached != null) {
        return PlacesResult(places: cached.places, fetchedAt: cached.at, fromCache: true, offline: true);
      }
      throw PlacesOffline(error);
    }
  }
}

/// Overpass API — **استعلام واحد لكل بحث** (صيدليات ودكاترة مع بعض).
/// سياسة الاستخدام: https://dev.overpass-api.de/overpass-doc/en/preface/commons.html
///
/// الـinstance العام للتجربة والاستخدام الصغير؛ تطبيق لناس كتير محتاج
/// instance بتاعه (مكتوب في «دين تقني»). أندرويد على المصدر ده زي ما هو.
class OverpassPlaces implements PlacesSource {
  OverpassPlaces({http.Client? client, this.cache = const PrefsPlacesCache()}) : _client = client ?? http.Client();

  final http.Client _client;

  /// عشان [search] — الكاش نفسه بيعيش في [NearbyPlaces].
  final PlacesCache cache;

  static final endpoint = Uri.parse('https://overpass-api.de/api/interpreter');
  static const radiusMeters = NearbyPlaces.radiusMeters;
  static const cacheFor = NearbyPlaces.cacheFor;

  /// هوية التطبيق — مطلوبة بسياسة OSM (مش هوية المكتبة الافتراضية).
  static const userAgent = 'Fakkarni/1.0 (com.fakkarni.fakkarni)';

  static double round3(double v) => NearbyPlaces.round3(v);

  static String query(double lat, double lon, [int radius = radiusMeters]) {
    final around = '(around:$radius,$lat,$lon)';
    return '[out:json][timeout:25];('
        'nwr["amenity"="pharmacy"]$around;'
        'nwr["amenity"="doctors"]$around;'
        'nwr["healthcare"="doctor"]$around;'
        ');out center tags;';
  }

  @override
  String get id => 'overpass';

  @override
  String get displayName => 'OpenStreetMap';

  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async {
    final response = await _client.post(
      endpoint,
      headers: {'User-Agent': userAgent},
      body: {'data': query(lat, lon, radiusMeters)},
    );
    if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}');
    return Place.fromOverpass(jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }

  /// نفس البحث المكيّش بتاع الشاشة، على المصدر ده — بيفضل موجود عشان اختبارات
  /// Overpass تفضل زي ما هي.
  Future<PlacesResult> search(double latitude, double longitude, {DateTime? now}) =>
      NearbyPlaces(source: this, cache: cache).search(latitude, longitude, now: now);
}

/// خرايط أبل (iOS بس): `MKLocalSearch` من الجهاز نفسه، عن طريق قناة صغيرة في
/// `ios/Runner/PlacesChannel.swift`. **مفيش مفتاح، مفيش MapKit JS، ومفيش
/// شبكة في Dart** — النظام هو اللي بيكلّم أبل، بنفس القواعد بتاعة تطبيق
/// الخرايط نفسه.
///
/// اللي بيرجع: الاسم، الإحداثيات، التليفون، ومعرّف MapKit.
/// [Place.openingHours] **null دايماً** — MapKit ما بيدّيهاش، والشاشة بتعرف
/// تسكت (مفيش «فاتحة/قافلة» من غير وسم).
///
/// الجزء السويفت **ما يتختبرش من `flutter test`**؛ اللي بيتختبر هنا هو
/// ترجمة اللي القناة بترجّعه لـ[Place]، على قناة مزيّفة.
class AppleMapKitPlaces implements PlacesSource {
  const AppleMapKitPlaces();

  static const channel = MethodChannel('fakkarni/places');

  @override
  String get id => 'mapkit';

  @override
  String get displayName => 'Apple';

  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async {
    final raw = await channel.invokeMethod<List<Object?>>('nearby', {
      'lat': lat,
      'lon': lon,
      'radiusMeters': radiusMeters,
    });
    return fromChannel(raw ?? const []);
  }

  /// صف من سويفت → [Place]. صف ناقص (من غير إحداثيات أو نوع) بيتعدّى، مش بيرمي.
  static List<Place> fromChannel(List<Object?> rows) {
    final places = <Place>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final lat = row['lat'], lon = row['lon'];
      if (lat is! num || lon is! num) continue;
      final kind = switch (row['kind']) {
        'pharmacy' => PlaceKind.pharmacy,
        'doctor' => PlaceKind.doctor,
        _ => null,
      };
      if (kind == null) continue;
      String? text(String k) {
        final v = row[k];
        return v is String && v.trim().isNotEmpty ? v.trim() : null;
      }

      places.add(Place(
        id: text('id') ?? 'mapkit/${lat.toDouble()},${lon.toDouble()}',
        kind: kind,
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        name: text('name'),
        phone: text('phone'),
        // MapKit ما بيدّيش مواعيد — ولا هنخمّنها
        openingHours: null,
      ));
    }
    return places;
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
