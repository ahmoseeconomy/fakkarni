import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/features/health/lab_flag.dart';
import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/core/widgets/f_wheels.dart' show FTimeWheel;
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import '../../support/seeded_clock.dart';


final aug31 = DateTime(2026, 8, 31);

class RecordingSink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled[n.id] = n;
  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();
  @override
  Future<void> ensurePermissions() async {}
}

class FakeReader implements PrescriptionReader {
  FakeReader(this.result);
  final Future<PrescriptionReading> Function() result;
  int calls = 0;

  /// عدد الصفحات في كل قراية.
  final pages = <int>[];
  @override
  Future<PrescriptionReading> read(Uint8List image, {String mimeType = 'image/jpeg', List<Uint8List> morePages = const []}) {
    calls++;
    pages.add(1 + morePages.length);
    return result();
  }
}

ReadField<T> ok<T>(T value) => ReadField(value: value, confidence: 0.95);
ReadField<T> low<T>(T? value, [String? note]) =>
    ReadField(value: value, confidence: 0.4, note: note);

/// سطر واضح: Concor بعد الفطار، مفتوح المدة.
final clearLine = ReadLine(
  name: ok('Concor 5mg'),
  amount: ok('قرص واحد'),
  timings: ok([FixedTiming(MinuteOfDay.hm(7, 30))]),
  duration: const ReadField(value: null, confidence: 1),
);

/// سطر توقيته غامض.
final unclearLine = ReadLine(
  name: ok('Cataflam'),
  amount: ok('قرص'),
  timings: const ReadField.missing(unclearTimingNote),
  duration: const ReadField(value: null, confidence: 1),
);

class Harness {
  late AppDatabase db;
  late MedicationRepository meds;
  late RecordingSink sink;
  late AppServices services;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
    final patients = PatientRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    sink = RecordingSink();
    final patientId = await patients.ensurePatient();
    services = AppServices(
      db: db,
      patients: patients,
      medications: meds,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: sink,
      ),
      patientId: patientId,
    );
  }

  Future<void> tearDown() => db.close();

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(textDirection: TextDirection.rtl, child: screen),
        ),
      ),
    );
    await settle(tester);
  }
}

/// ضخّ **محدود**، مش `pumpAndSettle`.
///
/// كارت المية فيه نقطة بتلمع على طول، و`pumpAndSettle` بتفضل مستنية إطار
/// مفيهوش حركة — يعني بتعلّق لحد ما المهلة تخلص على أي شاشة الكارت ده
/// عليها. ٦٠ × ٢٥ مللي = ثانية ونص: أكتر من انتقال شاشة (٣٠٠ مللي) وأكتر
/// من أطول انتقال عندنا.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

/// بيوصّل بكرة اختيار ([FChoiceWheel]) لصف برقمه — بالسحب من مكانها
/// الحالي، زي ما الإيد بتعمل. الشرايح بقت بكر (٥ أكتوبر ٢٠٢٦)، والدوسة
/// على صف بعيد مش مضمونة (برّه نافذة الرسم) — السحبة المحسوبة مضمونة.
Future<void> pickWheel(WidgetTester tester, Key key, int targetIndex) async {
  final picker = tester.widget<CupertinoPicker>(find.byKey(key));
  final current = picker.scrollController!.selectedItem;
  if (current == targetIndex) return;
  await tester.drag(find.byKey(key), Offset(0, -44.0 * (targetIndex - current)));
  await settle(tester);
}

/// بيحرّك [FTimeWheel] لساعة بعينها — الفترة بدوستها («ص»/«م») والعمودين
/// بسحبة محسوبة زي [pickWheel]. بديل الشرايح السريعة اللي اتشالت من
/// «الساعة كام؟» (المالك، ٥ أكتوبر ٢٠٢٦ مساءً).
Future<void> pickTime(WidgetTester tester, MinuteOfDay target, {Finder? wheel}) async {
  final f = wheel ?? find.byType(FTimeWheel);
  MinuteOfDay current() => tester.widget<FTimeWheel>(f).value;
  final wantEvening = target.hour >= 12;
  if (wantEvening != (current().hour >= 12)) {
    await tester.tap(find.descendant(of: f, matching: find.text(wantEvening ? 'م' : 'ص')));
    await settle(tester);
  }
  int h12(int h) => h % 12 == 0 ? 12 : h % 12;
  final dh = h12(target.hour) - h12(current().hour);
  if (dh != 0) {
    await tester.drag(
      find.descendant(of: f, matching: find.byKey(FTimeWheel.hoursKey)),
      Offset(0, -44.0 * dh),
    );
    await settle(tester);
  }
  final dm = target.minute - current().minute;
  if (dm != 0) {
    await tester.drag(
      find.descendant(of: f, matching: find.byKey(FTimeWheel.minutesKey)),
      Offset(0, -44.0 * dm),
    );
    await settle(tester);
  }
}

void screenTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}

/// **الحد الأدنى للنص عند الابن — تدرّجه هو، مش تدرّج الأب.**
///
/// شاشات الابن ليها كثافة أعلى عن قصد (`F.care…` في `tokens.dart`): هو
/// شاب شغّال بيبص تلات ثواني، مش راجل عنده ٧٢ سنة بنضارة قراية. الحدود
/// بتاعة الأب (`F.minTextSize` ١٧) ما اتغيّرتش ولا واحد منها — الاختبار
/// ده بيتنده بحدّ الابن على شاشاته هو بس.
void expectCaregiverDensity(WidgetTester tester) =>
    expectNoRedAndMinSize(tester, min: F.careMinTextSize);

void expectNoRedAndMinSize(WidgetTester tester, {double min = F.minTextSize}) {
  // الاستثناء الوحيد المسموح (جولة ٢١): كلمة «برّه نطاق الورقة» جوّه
  // [LabFlagBadge]. مقصورة على الودجت نفسه عن قصد — أحمر في أي نص تاني
  // على نفس الشاشة لسه بيوقّع الاختبار، وحبّاية الطوارئ المليانة لسه
  // لوحدها (اختبارها في `red_only_in_emergency_test`).
  final inBadge = {
    for (final e in find
        .descendant(of: find.byType(LabFlagBadge), matching: find.byType(Text))
        .evaluate())
      e.widget,
  };
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final size = text.style?.fontSize;
    if (size != null) {
      expect(size, greaterThanOrEqualTo(min), reason: text.data);
    }
    final colour = text.style?.color;
    if (colour == null || inBadge.contains(text)) continue;
    final isRed = colour.r > 0.6 && colour.g < 0.35 && colour.b < 0.35;
    expect(isRed, isFalse, reason: 'مفيش أحمر: ${text.data}');
  }
}
