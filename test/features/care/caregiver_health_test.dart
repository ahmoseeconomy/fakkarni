import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/supabase_caregiver_remote.dart'
    show emergencyFromRow, questionFromRow, readingFromRow, recordFromRow;
import 'package:fakkarni/features/care/caregiver_health_screen.dart';
import 'package:fakkarni/features/care/caregiver_screen.dart';
import 'package:fakkarni/features/care/caregiver_snapshot_holder.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize, screenTest, settle;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, now;

const _patient = CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد');

CaregiverRecord record(String title, {required DateTime arrived, DateTime? happened, String kind = 'visit'}) =>
    CaregiverRecord(
      uuid: title,
      kind: kind,
      title: title,
      happenedAt: happened ?? arrived,
      updatedAt: arrived,
    );

void main() {
  group('الصفوف → الموديلات (من غير Supabase)', () {
    test('سجل بسطور تحاليله، والوقت محلي', () {
      final r = recordFromRow({
        'uuid': 'r1',
        'kind': 'lab',
        'title': 'تحليل سكر تراكمي',
        'happened_at': '2026-08-20T07:00:00.000Z',
        'doctor': 'د. سامي',
        'place': null,
        'notes': 'صايم ١٢ ساعة',
        'deleted_at': null,
        'updated_at': '2026-08-31T09:00:00.000Z',
        'lab_results': [
          {'test_name': 'HbA1c', 'value': 7.1, 'unit': '%'},
          {'test_name': 'Glucose', 'value': 128, 'unit': 'mg/dL'},
        ],
      })!;
      expect(r.kind, 'lab');
      expect(r.happenedAt, DateTime.utc(2026, 8, 20, 7).toLocal());
      expect(r.updatedAt, DateTime.utc(2026, 8, 31, 9).toLocal());
      expect(r.doctor, 'د. سامي');
      expect(r.place, isNull);
      expect([for (final l in r.labLines) (l.testName, l.value, l.unit)], [
        ('HbA1c', 7.1, '%'),
        ('Glucose', 128.0, 'mg/dL'),
      ]);
    });

    test('سجل ممسوح ناعم → null (عمره ما يتعرض، حتى لو الاستعلام فوّته)', () {
      expect(
        recordFromRow({
          'uuid': 'r1',
          'kind': 'visit',
          'title': 'x',
          'happened_at': '2026-08-20T07:00:00.000Z',
          'deleted_at': '2026-08-30T07:00:00.000Z',
          'updated_at': '2026-08-30T07:00:00.000Z',
        }),
        isNull,
      );
    });

    test('قياس، طوارئ، سؤال', () {
      final g = readingFromRow({
        'uuid': 'g1',
        'value_mg_dl': 128,
        'measured_at': '2026-08-31T05:00:00.000Z',
        'context': 'afterMeal',
        'updated_at': '2026-08-31T05:01:00.000Z',
      });
      expect((g.valueMgDl, g.context), (128, 'afterMeal'));

      final e = emergencyFromRow({'blood_type': 'O+', 'allergies': ' ', 'chronic_conditions': 'ضغط'})!;
      expect((e.bloodType, e.allergies, e.chronicConditions), ('O+', null, 'ضغط'));
      expect(emergencyFromRow({'blood_type': null, 'allergies': '', 'chronic_conditions': null}), isNull,
          reason: 'صف فاضي كله = مفيش حاجة');
      expect(emergencyFromRow(null), isNull);

      final q = questionFromRow({
        'uuid': 'q1',
        'body': 'ينفع أوقف الملح؟',
        'written_at': '2026-08-30T08:00:00.000Z',
        'asked': true,
        'updated_at': '2026-08-30T08:00:00.000Z',
      });
      expect((q.body, q.asked), ('ينفع أوقف الملح؟', true));
    });
  });

  group('«الجديد»', () {
    test('بالوصول مش بتاريخ الحدث: تحليل من ٢٠١٩ اتسجّل النهارده فوق قياس امبارح', () {
      final snapshot = CaregiverSnapshot(
        patient: _patient,
        medications: const [],
        events: const [],
        records: [
          record('تحليل ٢٠١٩', arrived: DateTime(2026, 8, 31, 10), happened: DateTime(2019, 3, 1), kind: 'lab'),
        ],
        readings: [
          CaregiverReading(
            uuid: 'g1',
            valueMgDl: 128,
            measuredAt: DateTime(2026, 8, 30, 8),
            context: 'fasting',
            updatedAt: DateTime(2026, 8, 30, 8),
          ),
        ],
        questions: [
          CaregiverQuestion(
            uuid: 'q1',
            body: 'سؤال',
            writtenAt: DateTime(2026, 8, 31, 9),
            asked: false,
            updatedAt: DateTime(2026, 8, 31, 9),
          ),
        ],
      );

      final items = newestArrivals(snapshot);
      expect([for (final i in items) i.type], [NewItemType.record, NewItemType.question, NewItemType.reading]);
      expect(items.first.happenedAt, DateTime(2019, 3, 1), reason: 'بيتعرض بتاريخه هو');
    });

    test('آخر ١٠ بس، من أي نوع', () {
      final snapshot = CaregiverSnapshot(
        patient: _patient,
        medications: const [],
        events: const [],
        records: [for (var i = 0; i < 8; i++) record('سجل $i', arrived: DateTime(2026, 8, 1 + i))],
        readings: [
          for (var i = 0; i < 8; i++)
            CaregiverReading(
              uuid: 'g$i',
              valueMgDl: 100 + i,
              measuredAt: DateTime(2026, 8, 10 + i),
              context: 'fasting',
              updatedAt: DateTime(2026, 8, 10 + i),
            ),
        ],
      );

      final items = newestArrivals(snapshot);
      expect(items, hasLength(10));
      expect(items.first.reading!.valueMgDl, 107, reason: 'الأحدث وصولاً الأول');
      final arrivals = [for (final i in items) i.arrivedAt];
      expect(arrivals, [...arrivals]..sort((a, b) => b.compareTo(a)));
      expect(items.where((i) => i.type == NewItemType.record), hasLength(2), reason: 'السجلات الأقدم اتقصّت');
    });

    screenTest('على «متابعة»: تحت التنبيهات المفتوحة، وكل سطر بتاريخ حدثه', (tester) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          alerts: [
            CaregiverAlert(
              uuid: 'a1',
              medicationName: 'Glucophage',
              scheduledAt: DateTime(2026, 8, 31, 9),
              doseState: 'missed',
              deliveryStatus: 'no_token',
              createdAt: DateTime(2026, 8, 31, 10),
            ),
          ],
          records: [
            record('صورة صدر', arrived: DateTime(2026, 8, 31, 11), happened: DateTime(2019, 3, 1), kind: 'imaging'),
          ],
        );
      await tester.pumpWidget(MaterialApp(
        theme: F.light,
        home: Directionality(textDirection: TextDirection.rtl, child: CaregiverScreen(remote: remote, now: now)),
      ));
      await settle(tester);

      expect(find.text('أشعة: صورة صدر'), findsOneWidget);
      expect(find.text('١ مارس ٢٠١٩'), findsOneWidget);
      final alertTop = tester.getTopLeft(find.textContaining('والدك ما أكّدش')).dy;
      final newestTop = tester.getTopLeft(find.byKey(const ValueKey('newest'))).dy;
      expect(alertTop, lessThan(newestTop), reason: 'جرعة فاتت أهم من سجل اتضاف');
      expectNoRedAndMinSize(tester);
    });
  });

  screenTest('«الملف الصحي» بكل قسم فاضي: ما بيقعش، وكل قسم بيقول «لسه مفيش حاجة هنا»', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()..next = const CaregiverSnapshot(patient: _patient, medications: [], events: []),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);

    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('لسه مفيش حاجة هنا.'), findsNWidgets(3));
    expect(find.text('لسه ما اتملاش'), findsNWidgets(3), reason: 'الطوارئ فاضية = مفيش حاجة اتخمّنت');
    holder.setActive(false);
  });

  screenTest('سجل ممسوح ما بيوصلش الشاشة: الصورة من الصفوف بتفلتره', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = [
      {
        'uuid': 'r1',
        'kind': 'visit',
        'title': 'زيارة شغّالة',
        'happened_at': '2026-08-20T07:00:00.000Z',
        'deleted_at': null,
        'updated_at': '2026-08-30T07:00:00.000Z',
      },
      {
        'uuid': 'r2',
        'kind': 'visit',
        'title': 'زيارة اتمسحت',
        'happened_at': '2026-08-21T07:00:00.000Z',
        'deleted_at': '2026-08-31T07:00:00.000Z',
        'updated_at': '2026-08-31T07:00:00.000Z',
      },
    ];
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          records: [for (final r in rows) ?recordFromRow(r)],
        ),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);

    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);

    expect(find.text('زيارة شغّالة'), findsOneWidget);
    expect(find.textContaining('اتمسحت'), findsNothing);
    holder.setActive(false);
  });
}
