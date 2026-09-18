import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/places/places.dart';

/// الأربع أنواع في **استعلام واحد** — والوسوم اللي مصر بتستخدمها فعلاً.
void main() {
  test('استعلام واحد: صيدلية، دكاترة/عيادة/healthcare=doctor، مستشفى، معمل — كلهم حوالين نفس النقطة', () {
    final q = OverpassPlaces.query(30.044, 31.236);

    expect('[out:json]'.allMatches(q), hasLength(1), reason: 'استعلام واحد مش أربعة');
    for (final tag in [
      'nwr["amenity"="pharmacy"]',
      'nwr["amenity"="doctors"]',
      'nwr["amenity"="clinic"]',
      'nwr["healthcare"="doctor"]',
      'nwr["amenity"="hospital"]',
      'nwr["healthcare"="laboratory"]',
    ]) {
      expect(q, contains('$tag(around:2000,30.044,31.236)'), reason: tag);
    }
    expect(q, endsWith(');out center tags;'));
  });

  test('التحليل: clinic دكتور، hospital مستشفى، laboratory معمل — وcafe لأ', () {
    final places = Place.fromOverpass({
      'elements': [
        {'type': 'node', 'id': 1, 'lat': 30.0, 'lon': 31.0, 'tags': {'amenity': 'clinic', 'name': 'عيادة'}},
        {'type': 'node', 'id': 2, 'lat': 30.0, 'lon': 31.0, 'tags': {'amenity': 'hospital', 'healthcare': 'hospital'}},
        {'type': 'node', 'id': 3, 'lat': 30.0, 'lon': 31.0, 'tags': {'healthcare': 'laboratory'}},
        {'type': 'node', 'id': 4, 'lat': 30.0, 'lon': 31.0, 'tags': {'amenity': 'doctors'}},
        {'type': 'node', 'id': 5, 'lat': 30.0, 'lon': 31.0, 'tags': {'amenity': 'cafe'}},
      ],
    });
    expect([for (final p in places) (p.id, p.kind)], [
      ('node/1', PlaceKind.doctor),
      ('node/2', PlaceKind.hospital),
      ('node/3', PlaceKind.lab),
      ('node/4', PlaceKind.doctor),
    ]);
  });
}
