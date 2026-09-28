// «صيدليتي» تلات طرق: من «القريب مني»، من صورة الكارت، أو بالإيد — ومفيش
// حاجة بتتحفظ قبل «احفظ».
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/ai/pharmacy_card_reader.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/features/medication/pharmacy_sheet.dart';
import 'package:fakkarni/features/nearby/nearby_screen.dart';

import '../../data/places/overpass_places_test.dart' show MemoryCache;
import '../nearby/nearby_screen_test.dart' show BlankTiles, FakeLocation;
import '../scan/scan_test_support.dart';

class FakeCardReader implements PharmacyCardReader {
  FakeCardReader(this.reading);
  PharmacyCardReading reading;
  int calls = 0;
  @override
  Future<PharmacyCardReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    calls++;
    return reading;
  }
}

class _OnePharmacy implements PlacesSource {
  _OnePharmacy(this.phone, {this.kind = PlaceKind.pharmacy});
  final String? phone;
  final PlaceKind kind;
  @override
  String get id => 'fake';
  @override
  String get displayName => 'OpenStreetMap';
  @override
  Future<List<Place>> nearby(double lat, double lon, int radiusMeters) async => [
        Place(id: 'ph1', kind: kind, lat: 30.0445, lon: 31.2358, name: 'صيدلية العزبي', phone: phone),
      ];
}

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  late FakeCardReader reader;
  late List<ImageSource> picked;
  final originalPick = pickPharmacyCard;
  final originalNearby = pickPharmacyFromNearby;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reader = FakeCardReader(const PharmacyCardReading());
    picked = [];
    pickPharmacyCard = (source) async {
      picked.add(source);
      return Uint8List.fromList([1, 2, 3]);
    };
  });
  tearDown(() {
    pickPharmacyCard = originalPick;
    pickPharmacyFromNearby = originalNearby;
  });

  AppServices servicesWithReader() => AppServices(
        db: h.services.db,
        patients: h.services.patients,
        medications: h.services.medications,
        events: h.services.events,
        scheduler: h.services.scheduler,
        patientId: h.services.patientId,
        pharmacyCardReader: reader,
      );

  PreferencesRepository prefs() => PreferencesRepository(h.db);

  /// زرار بيفتح الورقة — زي الإعدادات و«القريب مني».
  Future<void> openSheet(WidgetTester tester, {PharmacyPrefill? prefill}) async {
    h.services = servicesWithReader();
    await h.pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            key: const ValueKey('open'),
            onPressed: () => editPharmacy(c, prefill: prefill),
            child: const Text('افتح'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await settle(tester);
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  screenTest('الترتيب: القريب مني، ثم الكارت (كاميرا / صور)، ثم الحقول التلاتة', (tester) async {
    await openSheet(tester);
    final nearby = tester.getRect(find.byKey(const ValueKey('pharmacy-from-nearby'))).top;
    final camera = tester.getRect(find.byKey(const ValueKey('pharmacy-card-camera'))).top;
    final name = tester.getRect(find.byKey(const ValueKey('pharmacy-name'))).top;
    expect(nearby, lessThan(camera));
    expect(camera, lessThan(name));
    expect(find.byKey(const ValueKey('pharmacy-card-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('pharmacy-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('pharmacy-number')), findsOneWidget);
  });

  screenTest('موبايل من «القريب مني» → اتصال وواتساب، ومفيش حاجة اتحفظت قبل «احفظ»', (tester) async {
    await openSheet(tester, prefill: const PharmacyPrefill(name: 'صيدلية العزبي', phone: '+20 101 234 5678'));
    expect(field(tester, 'pharmacy-name'), 'صيدلية العزبي');
    expect(field(tester, 'pharmacy-call'), '01012345678');
    expect(field(tester, 'pharmacy-number'), '01012345678');
    expect(find.byKey(const ValueKey('pharmacy-wa-question')), findsNothing);
    expect(find.byKey(const ValueKey('pharmacy-review-note')), findsOneWidget);
    expect(await prefs().pharmacy(), (name: null, whatsapp: null, call: null), reason: 'مفيش حفظ قبل الزرار');

    await tapKey(tester, 'pharmacy-save');
    expect(await prefs().pharmacy(), (name: 'صيدلية العزبي', whatsapp: '01012345678', call: '01012345678'));
  });

  screenTest('أرضي → اتصال بس، الواتساب فاضي والسؤال ظاهر؛ «اكتبه» بيروح لحقل الواتساب', (tester) async {
    await openSheet(tester, prefill: const PharmacyPrefill(name: 'صيدلية مصر', phone: '٠٢ ٢٣٤٥ ٦٧٨٩'));
    expect(field(tester, 'pharmacy-call'), '0223456789');
    expect(field(tester, 'pharmacy-number'), '');
    expect(find.text('عندك رقم واتساب للصيدلية دي؟'), findsOneWidget);
    expect(find.byKey(const ValueKey('pharmacy-wa-photo')), findsOneWidget);
    await tapKey(tester, 'pharmacy-wa-type');
    final wa = tester.widget<TextField>(find.byKey(const ValueKey('pharmacy-number')));
    expect(wa.focusNode!.hasFocus, isTrue);
  });

  screenTest('صورة من سؤال الواتساب: الاسم ورقم الاتصال فاضلين، والواتساب اتملى', (tester) async {
    reader.reading = const PharmacyCardReading(
      name: 'اسم تاني من الكارت',
      phones: ['0233334444', '01155554444'],
      highConfidence: true,
    );
    await openSheet(tester, prefill: const PharmacyPrefill(name: 'صيدلية مصر', phone: '0223456789'));
    await tapKey(tester, 'pharmacy-wa-photo');
    expect(reader.calls, 1);
    expect(picked, [ImageSource.camera]);
    expect(field(tester, 'pharmacy-name'), 'صيدلية مصر', reason: 'ما اتكتبش فوقه');
    expect(field(tester, 'pharmacy-call'), '0223456789', reason: 'ما اتكتبش فوقه');
    expect(field(tester, 'pharmacy-number'), '01155554444');
    expect(find.byKey(const ValueKey('pharmacy-review-note')), findsOneWidget);
  });

  screenTest('كارت فيه موبايلين → شرايح، والدوسة بتحط الرقم', (tester) async {
    reader.reading = const PharmacyCardReading(
      name: 'صيدلية النور',
      phones: ['01012345678', '01155554444'],
      highConfidence: true,
    );
    await openSheet(tester);
    await tapKey(tester, 'pharmacy-card-gallery');
    expect(picked, [ImageSource.gallery]);
    expect(field(tester, 'pharmacy-name'), 'صيدلية النور');
    expect(field(tester, 'pharmacy-number'), '');
    expect(find.byKey(const ValueKey('pharmacy-wa-choice-01155554444')), findsOneWidget);
    await tapKey(tester, 'pharmacy-wa-choice-01155554444');
    expect(field(tester, 'pharmacy-number'), '01155554444');
  });

  screenTest('رقم «واتساب» على الكارت بيكسب، والأرضي للاتصال', (tester) async {
    reader.reading = const PharmacyCardReading(
      name: 'صيدلية النور',
      phones: ['0223456789', '01012345678'],
      whatsapp: '01009998888',
      highConfidence: true,
    );
    await openSheet(tester);
    await tapKey(tester, 'pharmacy-card-camera');
    expect(field(tester, 'pharmacy-number'), '01009998888');
    expect(field(tester, 'pharmacy-call'), '0223456789');
  });

  screenTest('كارت مش مقروء → الجملة، ومفيش حقل اتملى', (tester) async {
    reader.reading = const PharmacyCardReading();
    await openSheet(tester);
    await tapKey(tester, 'pharmacy-card-camera');
    expect(find.text(pharmacyCardUnreadable), findsOneWidget);
    expect(field(tester, 'pharmacy-name'), '');
    expect(find.byKey(const ValueKey('pharmacy-review-note')), findsNothing);
  });

  screenTest('فيه صيدلية قديمة → «تغيّر صيدليتك من … لـ …؟» قبل ما تتبدّل', (tester) async {
    await prefs().setPharmacy(name: 'صيدلية الشفا', whatsapp: '01000000000', call: null);
    await openSheet(tester, prefill: const PharmacyPrefill(name: 'صيدلية العزبي', phone: '01012345678'));
    await tapKey(tester, 'pharmacy-save');
    expect(find.text('تغيّر صيدليتك من صيدلية الشفا لـ صيدلية العزبي؟'), findsOneWidget);
    expect(await prefs().pharmacy(), (name: 'صيدلية الشفا', whatsapp: '01000000000', call: null), reason: 'لسه ما اتبدلتش');

    await tapKey(tester, 'pharmacy-replace-yes');
    expect(await prefs().pharmacy(), (name: 'صيدلية العزبي', whatsapp: '01012345678', call: '01012345678'));
  });

  screenTest('«لأ، خلّي القديمة» → القديمة زي ما هي', (tester) async {
    await prefs().setPharmacy(name: 'صيدلية الشفا', whatsapp: '01000000000', call: null);
    await openSheet(tester, prefill: const PharmacyPrefill(name: 'صيدلية العزبي', phone: '01012345678'));
    await tapKey(tester, 'pharmacy-save');
    await tapKey(tester, 'pharmacy-replace-no');
    expect(await prefs().pharmacy(), (name: 'صيدلية الشفا', whatsapp: '01000000000', call: null));
  });

  screenTest('«اختار من القريب مني» جوّه الورقة بيملا الحقول من الكارت اللي اتختار', (tester) async {
    pickPharmacyFromNearby = (_) async =>
        const Place(id: 'x', kind: PlaceKind.pharmacy, lat: 0, lon: 0, name: 'صيدلية سيف', phone: '01223456789');
    await openSheet(tester);
    await tapKey(tester, 'pharmacy-from-nearby');
    expect(field(tester, 'pharmacy-name'), 'صيدلية سيف');
    expect(field(tester, 'pharmacy-number'), '01223456789');
    expect(await prefs().pharmacy(), (name: null, whatsapp: null, call: null));
  });

  screenTest('كارت صيدلية في «القريب مني»: «خليها صيدليتي» بتفتح الورقة متعبّية، ومفيش حفظ', (tester) async {
    h.services = servicesWithReader();
    await h.pump(
      tester,
      NearbyScreen(
        initialKind: PlaceKind.pharmacy,
        location: FakeLocation(const LocationFix(LocationStatus.granted, 30.0444, 31.2357)),
        places: NearbyPlaces(source: _OnePharmacy('0223456789'), cache: MemoryCache()),
        tileProvider: BlankTiles(),
        now: () => DateTime(2026, 9, 15, 10),
      ),
    );
    await settle(tester);
    expect(find.text('خليها صيدليتي'), findsOneWidget);
    await tapKey(tester, 'keep-pharmacy-ph1');
    expect(field(tester, 'pharmacy-name'), 'صيدلية العزبي');
    expect(field(tester, 'pharmacy-call'), '0223456789');
    expect(field(tester, 'pharmacy-number'), '', reason: 'أرضي — مش واتساب');
    expect(find.text('عندك رقم واتساب للصيدلية دي؟'), findsOneWidget);
    expect(await prefs().pharmacy(), (name: null, whatsapp: null, call: null));
  });

  screenTest('كارت دكتور ما عليهوش «خليها صيدليتي»', (tester) async {
    await h.pump(
      tester,
      NearbyScreen(
        initialKind: PlaceKind.doctor,
        location: FakeLocation(const LocationFix(LocationStatus.granted, 30.0444, 31.2357)),
        places: NearbyPlaces(source: _OnePharmacy('01012345678', kind: PlaceKind.doctor), cache: MemoryCache()),
        tileProvider: BlankTiles(),
        now: () => DateTime(2026, 9, 15, 10),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('place-ph1')), findsOneWidget, reason: 'الكارت نفسه موجود');
    expect(find.text('خليها صيدليتي'), findsNothing);
  });
}
