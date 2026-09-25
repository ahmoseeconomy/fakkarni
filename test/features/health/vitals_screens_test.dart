import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/vitals_repository.dart';
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/health/vitals.dart';
import 'package:fakkarni/features/health/glucose_screen.dart';
import 'package:fakkarni/features/health/vitals/vital_entry_sheet.dart';
import 'package:fakkarni/features/health/vitals/vital_history.dart';
import 'package:fakkarni/features/health/vitals/vital_history_screen.dart';
import 'package:fakkarni/features/export/export_document.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';

import '../../data/sync/sync_service_test.dart' show FakeSyncRemote;
import '../scan/scan_test_support.dart' show Harness, screenTest, settle, expectNoRedAndMinSize;

final now = DateTime(2026, 9, 25, 12);

class _Opener extends StatelessWidget {
  const _Opener({this.initial});
  final VitalKind? initial;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showVitalEntrySheet(context, initial: initial, now: now),
            child: const Text('افتح'),
          ),
        ),
      );
}

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  Future<List<VitalRow>> rows() => h.db.select(h.db.vitals).get();

  Future<void> open(WidgetTester tester, {VitalKind? initial}) async {
    await h.pump(tester, _Opener(initial: initial));
    await tester.tap(find.text('افتح'));
    await settle(tester);
  }

  group('«سجّل قياس»', () {
    screenTest('الضغط: الرقمين والنبض الاختياري بيتحفظوا بوقت دلوقتي', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('vital-value')), '130');
      await tester.enterText(find.byKey(const ValueKey('vital-value2')), '٨٥');
      await tester.enterText(find.byKey(const ValueKey('vital-pulse')), '72');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('vital-save')));
      await settle(tester);
      final r = (await rows()).single;
      expect((r.kind, r.value, r.value2, r.pulse), ('bloodPressure', 130.0, 85.0, 72));
      expect(r.measuredAt, DateTime(2026, 9, 25, 12));
    });

    screenTest('الوزن بكسر عربي', (tester) async {
      await open(tester, initial: VitalKind.weight);
      await tester.enterText(find.byKey(const ValueKey('vital-value')), '٧٢٫٥');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('vital-save')));
      await settle(tester);
      expect((await rows()).single.value, 72.5);
    });

    screenTest('رقم برّه اللي الأجهزة بتقراه: «الرقم ده غريب — راجعه» ومفيش حفظ، ومفيش أحمر', (tester) async {
      await open(tester, initial: VitalKind.spo2);
      await tester.enterText(find.byKey(const ValueKey('vital-value')), '140');
      await settle(tester);
      expect(find.text('الرقم ده غريب — راجعه'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vital-save')));
      await settle(tester);
      expect(await rows(), isEmpty);
      expectNoRedAndMinSize(tester);
    });

    screenTest('الوقت بيتغيّر: امبارح بتتحفظ على امبارح', (tester) async {
      await open(tester, initial: VitalKind.pulse);
      await tester.enterText(find.byKey(const ValueKey('vital-value')), '72');
      await tester.tap(find.byKey(const ValueKey('vital-edit-time')));
      await settle(tester);
      await tester.tap(find.text('امبارح'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('vital-save')));
      await settle(tester);
      expect((await rows()).single.measuredAt.day, 24);
    });

    screenTest('شريحة «السكر» بتفتح شاشة السكر زي ما هي', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('vital-kind-glucose')));
      await settle(tester);
      expect(find.byType(GlucoseScreen), findsOneWidget);
      expect(await rows(), isEmpty);
    });
  });

  group('التاريخ', () {
    Future<void> seed(List<(double, double?, int)> values, {VitalKind kind = VitalKind.bloodPressure}) async {
      for (final (v, d, ago) in values) {
        await VitalsRepository(h.db).add(
          h.services.patientId,
          VitalEntry(kind: kind, value: v, value2: d),
          measuredAt: now.subtract(Duration(days: ago)),
        );
      }
    }

    screenTest('آخر رقم، والمعتاد لسه مش كفاية، والرسم — من غير أحمر', (tester) async {
      await seed([(130, 85, 0), (125, 80, 3)]);
      await h.pump(tester, const VitalHistoryScreen(kind: VitalKind.bloodPressure));
      expect(find.text('١٣٠/٨٥ مم زئبق'), findsOneWidget);
      expect(find.byKey(const ValueKey('vital-usual')), findsOneWidget);
      expect(find.textContaining('لسه ما عندناش قياسات كفاية'), findsOneWidget);
      expect(find.byKey(const ValueKey('vital-diff')), findsNothing);
      expect(find.byKey(const ValueKey('vital-chart')), findsOneWidget);
      expect(find.text('الرقم الكبير'), findsOneWidget, reason: 'الخطين مكتوب مين مين — اللون مش لوحده');
      expect(find.byKey(const ValueKey('vital-ask-doctor')), findsOneWidget);
      expectNoRedAndMinSize(tester);
    });

    screenTest('٣ قياسات → المتوسط والفرق بالأرقام، والفترة بتقصّ القايمة في الرسم', (tester) async {
      await seed([(135, 88, 0), (125, 80, 5), (130, 84, 20)]);
      await h.pump(tester, VitalHistoryScreen(kind: VitalKind.bloodPressure, now: now));
      expect(find.textContaining('متوسط آخر ٣٠ يوم'), findsOneWidget);
      expect(find.byKey(const ValueKey('vital-diff')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vital-period-7')));
      await settle(tester);
      expect(find.byKey(const ValueKey('vital-chart')), findsOneWidget);
    });

    testWidgets('عند العيلة والممرض: قراية بس — مفيش «سجّل قياس»', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VitalHistoryView(
              kind: VitalKind.weight,
              vitals: [Vital(kind: VitalKind.weight, value: 72, measuredAt: now)],
              now: now,
            ),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('vital-add')), findsNothing);
      expect(find.text('٧٢ كيلو'), findsOneWidget);
    });
  });

  screenTest('«السجل»: «قياساتك» بآخر رقم لكل نوع و«سجّل قياس»', (tester) async {
    await VitalsRepository(h.db).add(h.services.patientId, const VitalEntry(kind: VitalKind.weight, value: 72.5),
        measuredAt: now.subtract(const Duration(hours: 2)));
    await h.pump(tester, HealthFileScreen(today: now));
    expect(find.text('قياساتك'), findsOneWidget);
    expect(find.byKey(const ValueKey('vital-summary-weight')), findsOneWidget);
    expect(find.text('٧٢٫٥ كيلو'), findsOneWidget);
    expect(find.byKey(const ValueKey('records-add-vital')), findsOneWidget);
  });

  test('المزامنة: القياس بيطلع، ولو جدول السحابة لسه مش موجود الصف بيستنى من غير ما يوقّف حاجة', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final h2 = Harness()..db = db;
    await h2.db.into(h2.db.patients).insert(PatientsCompanion.insert(name: 'أحمد'));
    final patientId = (await h2.db.select(h2.db.patients).getSingle()).id;
    await VitalsRepository(db).add(patientId, const VitalEntry(kind: VitalKind.pulse, value: 72), measuredAt: now);

    final missing = _NoVitalsTable();
    final sync = SyncService(db: db, remote: missing, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync.confirmLinked();
    await sync.push();
    expect(missing.rowCount('vitals'), 0);
    expect((await db.select(db.vitals).getSingle()).syncedAtMs, isNull, reason: 'الصف مستني الهجرة');
    await sync.dispose();

    final cloud = FakeSyncRemote();
    final sync2 = SyncService(db: db, remote: cloud, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync2.confirmLinked();
    await sync2.push();
    final row = cloud.tables['vitals']!.values.single;
    expect((row['kind'], row['value'], row['pulse']), ('pulse', 72.0, null));
    await sync2.dispose();
  });

  test('الملف: قسم «القياسات» بآخر رقم لكل نوع', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final patientId = await db.into(db.patients).insert(PatientsCompanion.insert(name: 'أحمد'));
    final repo = VitalsRepository(db);
    await repo.add(patientId, const VitalEntry(kind: VitalKind.weight, value: 70), measuredAt: now.subtract(const Duration(days: 5)));
    await repo.add(patientId, const VitalEntry(kind: VitalKind.weight, value: 71), measuredAt: now.subtract(const Duration(days: 1)));
    await repo.add(patientId, const VitalEntry(kind: VitalKind.bloodPressure, value: 130, value2: 85), measuredAt: now);
    final doc = await collectExport(db, patientId: patientId, options: ExportOptions.defaults(), now: now);
    final block = doc.blocks.singleWhere((b) => b.section == ExportSection.vitals);
    expect(block.lines, hasLength(2));
    expect(block.lines.first, startsWith('الضغط: ١٣٠/٨٥ مم زئبق'));
    expect(block.lines.last, startsWith('الوزن: ٧١ كيلو'), reason: 'الأحدث بس');
  });
}

class _NoVitalsTable extends FakeSyncRemote {
  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (table == 'vitals') throw const SyncRejected('PGRST205', "Could not find the table 'public.vitals'");
    await super.upsert(table, rows);
  }
}
