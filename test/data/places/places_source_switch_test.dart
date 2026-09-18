import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// المصدر بيتختار **في مكان واحد** بالمنصة: `placesSourceForPlatform` في
/// `lib/data/places/places.dart`. لو الاختيار اتكرر في شاشة أو خدمة تانية،
/// iOS وأندرويد يبقوا على مصدرين في نفس الوقت من غير ما حد يقصد.
void main() {
  final files = [
    for (final e in Directory('lib').listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart') && !e.path.startsWith('lib/macos')) e,
  ];
  String read(File f) => f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('AppleMapKitPlaces وOverpassPlaces بيتبنوا في placesSourceForPlatform وبس', () {
    final constructions = <String>[];
    for (final f in files) {
      for (final line in read(f).split('\n')) {
        // تعريف المُنشئ نفسه (`  OverpassPlaces({` / `  const AppleMapKitPlaces();`) مش بناء
        if (RegExp(r'^\s*(const\s+)?(AppleMapKitPlaces|OverpassPlaces)\(').hasMatch(line)) continue;
        for (final m in RegExp(r'\b(AppleMapKitPlaces|OverpassPlaces)\(').allMatches(line)) {
          constructions.add('${f.path}: ${m.group(1)}');
        }
      }
    }
    expect(constructions, unorderedEquals([
      'lib/data/places/places.dart: AppleMapKitPlaces',
      'lib/data/places/places.dart: OverpassPlaces',
    ]));

    final places = read(File('lib/data/places/places.dart'));
    final chooser = places.substring(places.indexOf('PlacesSource placesSourceForPlatform'));
    final chooserBody = chooser.substring(0, chooser.indexOf(';') + 1);
    expect(chooserBody, contains('Platform.isIOS'));
    expect(chooserBody, contains('AppleMapKitPlaces()'));
    expect(chooserBody, contains('OverpassPlaces('));
  });

  test('Platform.isIOS مش بيختار مصدر أماكن في أي مكان تاني', () {
    for (final f in files) {
      final text = read(f);
      if (f.path == 'lib/data/places/places.dart') {
        expect('Platform.isIOS'.allMatches(text), hasLength(1), reason: 'مرة واحدة في places.dart');
        continue;
      }
      for (final line in text.split('\n')) {
        if (line.contains('Platform.isIOS')) {
          expect(line.contains('Places') || line.contains('places'), isFalse, reason: '${f.path}: $line');
        }
      }
    }
  });

  test('الشاشة بتاخد الواجهة المكيّشة ومش بتعرف المصدر', () {
    final screen = read(File('lib/features/nearby/nearby_screen.dart'));
    expect(screen, contains('NearbyPlaces.forPlatform()'));
    expect(screen.contains('Overpass'), isFalse, reason: 'الشاشة ما تسمّيش مصدر');
    expect(screen.contains('MapKit'), isFalse);
  });
}
