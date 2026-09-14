import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

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
  @override
  Future<PrescriptionReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) {
    calls++;
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
  timings: ok([const AnchorTiming(DayAnchor.breakfast, 0)]),
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
    final routines = RoutineRepository(db);
    meds = MedicationRepository(db);
    sink = RecordingSink();
    final patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);
    services = AppServices(
      db: db,
      routines: routines,
      medications: meds,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
        routines: routines,
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

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void screenTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}

void expectNoRedAndMinSize(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final size = text.style?.fontSize;
    if (size != null) {
      expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
    }
    final colour = text.style?.color;
    if (colour == null) continue;
    final isRed = colour.r > 0.6 && colour.g < 0.35 && colour.b < 0.35;
    expect(isRed, isFalse, reason: 'مفيش أحمر: ${text.data}');
  }
}
