import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/ai/package_reader.dart';
import 'package:fakkarni/ai/package_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/edit_medication_screen.dart';
import 'package:fakkarni/features/medication/scan_package_screen.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';

import '../../features/scan/scan_test_support.dart';
import '../../support/seeded_clock.dart';

/// **كل باب بيحفظ دوا لازم يسيب تذكيراته متجدولة** — بالأرقام والساعات
/// بالظبط، من غير تكرار. الأبواب الخمسة: بالإيد، الروشتة، صورة العلبة،
/// تعديل الساعة، و«كلّمني» ← الفورم.

class _Reader implements MedicinePackageReader {
  @override
  Future<PackageReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async => PackageReading(
        brand: const ReadField(value: 'Concor', confidence: 0.95),
        activeIngredient: const ReadField(value: 'Bisoprolol', confidence: 0.95),
        strength: const ReadField(value: '5 mg', confidence: 0.95),
        form: const ReadField(value: 'tablets', confidence: 0.95),
        packSize: const ReadField(value: '30', confidence: 0.95),
      );
}

/// تخزين الصور بيقع — عشان نثبت إن الصورة ما تقدرش تسيب الدوا من غير تذكير.
class _BrokenStore implements AttachmentStore {
  int saves = 0;
  @override
  Future<String> save(Uint8List bytes, {String extension = 'jpg'}) async {
    saves++;
    throw StateError('disk full');
  }

  @override
  Future<void> delete(String relativePath) async {}
  @override
  Future<File?> fileFor(String relativePath) async => null;
}

void main() {
  late AppDatabase db;
  late RecordingSink sink;
  late MedicationRepository meds;
  late AppServices services;
  late _BrokenStore photos;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    final patients = PatientRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    sink = RecordingSink();
    photos = _BrokenStore();
    final pid = await patients.ensurePatient();
    services = AppServices(
      db: db,
      patients: patients,
      medications: meds,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(medications: meds, events: DoseEventRepository(db), patientId: pid, sink: sink),
      patientId: pid,
      medPhotoStore: photos,
    );
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        theme: F.light,
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    ));
    await settle(tester);
  }

  Map<int, PlannedNotification> doses() => {
        for (final e in sink.scheduled.entries)
          if (isDoseId(e.key)) e.key: e.value,
      };

  /// المتوقَّع: الخطة من الجداول الحقيقية، دلوقتي. الأرقام نفسها، والساعة
  /// ٩ بالليل بس، ومفيش تكرار (الخريطة بالرقم).
  Future<void> expectExactly(WidgetTester tester, {required int minute}) async {
    final schedules = await tester.runAsync(() => meds.activeSchedules(services.patientId));
    final expected = planWindow(schedules: schedules!, from: DateTime.now());
    expect(expected, isNotEmpty);
    expect(doses().keys.toSet(), {for (final p in expected) p.id});
    for (final p in doses().values) {
      expect(p.at.hour * 60 + p.at.minute, minute, reason: 'تذكير في ساعة غلط: ${p.at}');
    }
    // كل تذكير على يوم لوحده — مفيش اتنين لنفس اللحظة
    expect(doses().values.map((p) => p.at).toSet().length, doses().length);
  }

  final nine = 21 * 60;

  screenTest('بالإيد: «ضيف دوا» ← احفظ ← التذكيرات بالظبط', (tester) async {
    await pump(tester, const AddMedicationScreen());
    await tester.enterText(find.byType(TextField).first, 'Concor');
    await pickTime(tester, const MinuteOfDay(21 * 60));
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
    await expectExactly(tester, minute: nine);
  });

  screenTest('الروشتة: «تمام» ← التذكيرات بالظبط', (tester) async {
    final line = ReadLine(
      name: ok('Concor'),
      amount: ok('قرص'),
      timings: ok([FixedTiming(MinuteOfDay(nine))]),
      duration: const ReadField(value: null, confidence: 1),
    );
    await pump(
      tester,
      ReviewPrescriptionScreen(
        reading: PrescriptionReading(doctor: const ReadField(value: null, confidence: 1), lines: [line]),
      ),
    );
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)));
    await settle(tester);
    await expectExactly(tester, minute: nine);
  });

  screenTest('صورة العلبة: الصورة بتقع وقت الحفظ — والتذكيرات برضه متجدولة', (tester) async {
    // صورة حقيقية عشان التصغير يعدّي ويوصل للتخزين اللي بيقع
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    await pump(tester, ScanPackageScreen(reader: _Reader(), pickImage: (ImageSource s) async => jpeg));
    await tester.tap(find.byKey(const ValueKey('package-capture')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('med-photo-use-box')));
    await tester.tap(find.byKey(const ValueKey('med-photo-use-box')));
    await settle(tester);
    await pickTime(tester, const MinuteOfDay(21 * 60));
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    for (var i = 0; i < 20 && photos.saves == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await settle(tester);
    expect(photos.saves, 1, reason: 'الصورة ما وصلتش للتخزين — الاختبار ما بيقيسش حاجة');
    await expectExactly(tester, minute: nine);
  });

  screenTest('تعديل الساعة: القديم راح، الجديد موجود، ومفيش تكرار', (tester) async {
    final id = await tester.runAsync(() async {
      final id = await meds.addMedication(
        patientId: services.patientId,
        name: 'Concor',
        timing: FixedTiming(MinuteOfDay.hm(9)),
        startDate: DateTime.now(),
      );
      await services.scheduler.rescheduleAll();
      return id;
    });
    final before = doses().keys.toSet();
    expect(before, isNotEmpty);

    await pump(tester, EditMedicationScreen(medicationId: id!));
    await tester.tap(find.text('عدّل').first);
    await settle(tester);
    await pickTime(tester, const MinuteOfDay(21 * 60)); // بكرة المحرّر
    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);

    expect(doses().keys.toSet().intersection(before), isEmpty, reason: 'تذكير الساعة القديمة لسه موجود');
    await expectExactly(tester, minute: nine);
  });

  screenTest('«كلّمني» ← الفورم متعبّي ← احفظ ← التذكيرات بالظبط', (tester) async {
    // نفس المدخلات اللي `TalkButton._openAdd` بيبعتها
    await pump(
      tester,
      AddMedicationScreen(
        initialName: 'Concor',
        initialTimings: [FixedTiming(MinuteOfDay(nine))],
        initialAmount: 'قرص',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
    await expectExactly(tester, minute: nine);
  });
}
