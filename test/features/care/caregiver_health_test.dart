import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/supabase_caregiver_remote.dart'
    show emergencyFromRow, questionFromRow, readingFromRow, recordFromRow;
import 'package:fakkarni/domain/health/lab_range.dart';
import 'package:fakkarni/features/care/caregiver_health_screen.dart';
import 'package:fakkarni/features/health/lab_flag.dart';
import 'package:fakkarni/features/health/usual_words.dart'
    show adviceWords, labAboveWord, labBelowWord, labNearWord, labNoRangeText;
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
          {'test_name': 'HbA1c', 'value': 7.1, 'unit': '%', 'ref_low': 4, 'ref_high': 5.6},
          // صف اتكتب قبل نسخة ١٨ — الأعمدة مش موجودة أصلاً
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
      // نطاق الورقة جاي زي ما جهاز الأب رفعه…
      expect((r.labLines[0].range!.low, r.labLines[0].range!.high), (4.0, 5.6));
      // …والصف اللي مالوش نطاق بيفضل من غير نطاق. **مش** بنملاه من عندنا.
      expect(r.labLines[1].range, isNull);
    });

    test('نطاق مطبوع بالحروف بيعدّي زي ما هو، والتلاتة null = مفيش نطاق', () {
      Map<String, dynamic> withLines(List<Map<String, dynamic>> lines) => {
            'uuid': 'r1',
            'kind': 'lab',
            'title': 'تحليل',
            'happened_at': '2026-08-20T07:00:00.000Z',
            'deleted_at': null,
            'updated_at': '2026-08-31T09:00:00.000Z',
            'lab_results': lines,
          };
      final textRange = recordFromRow(withLines([
        {'test_name': 'CRP', 'value': 3, 'unit': null, 'ref_text': 'Negative'},
      ]))!;
      expect(textRange.labLines.single.range!.text, 'Negative');

      final none = recordFromRow(withLines([
        {'test_name': 'Uric acid', 'value': 5.1, 'unit': 'mg/dL', 'ref_low': null, 'ref_high': null, 'ref_text': null},
      ]))!;
      expect(none.labLines.single.range, isNull);
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

  screenTest('«الملف الصحي» فاضي خالص: ما بيقعش، وجملة واحدة — مش لوحات فاضية', (tester) async {
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
    // **جملة واحدة بدل تلات لوحات فاضية** — المدخل الفاضي مش بيظهر أصلاً،
    // وغيابه هو «مفيش حاجة هنا».
    expect(find.text('لسه مفيش حاجة هنا.'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('care-entry-visit')));
    await settle(tester);

    expect(find.text('زيارة شغّالة'), findsOneWidget);
    expect(find.textContaining('اتمسحت'), findsNothing);
    holder.setActive(false);
  });

  screenTest('مداخل بعددها، والفاضي مش بيظهر — والدوسة بتفتح قايمته', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          records: [
            CaregiverRecord(
              uuid: 'r1',
              kind: 'lab',
              title: 'صورة دم',
              happenedAt: DateTime(2026, 9, 12),
              updatedAt: DateTime(2026, 9, 12, 10),
            ),
            CaregiverRecord(
              uuid: 'r2',
              kind: 'lab',
              title: 'وظايف كلى',
              happenedAt: DateTime(2026, 9, 10),
              updatedAt: DateTime(2026, 9, 10, 10),
            ),
          ],
          readings: [
            CaregiverReading(
              uuid: 'g1',
              valueMgDl: 128,
              measuredAt: DateTime(2026, 9, 12, 8),
              context: 'fasting',
              updatedAt: DateTime(2026, 9, 12, 8, 5),
            ),
          ],
        ),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);

    // مدخل لكل حاجة فيها محتوى، بعدده
    expect(find.byKey(const ValueKey('care-entry-lab')), findsOneWidget);
    expect(find.byKey(const ValueKey('care-entry-readings')), findsOneWidget);
    expect(find.text('٢'), findsOneWidget, reason: 'تحليلين');
    // واللي مفيهوش حاجة مش بيظهر — غيابه هو «مفيش حاجة هنا»
    expect(find.byKey(const ValueKey('care-entry-visit')), findsNothing);
    expect(find.byKey(const ValueKey('care-entry-questions')), findsNothing);
    expect(find.text('لسه مفيش حاجة هنا.'), findsNothing);
    // والسجلات نفسها مش على الشاشة الأولى — دي مداخل
    expect(find.text('صورة دم'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('care-entry-lab')));
    await settle(tester);
    expect(find.text('صورة دم'), findsOneWidget);
    expect(find.text('وظايف كلى'), findsOneWidget);
    expectNoRedAndMinSize(tester);
    holder.setActive(false);
  });

  screenTest('الروشتة: ترويسة بحقول مسمّاة، والأدوية سطر لكل واحد', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          records: [
            CaregiverRecord(
              uuid: 'r1',
              kind: 'prescription',
              title: 'روشتة — ٣ أدوية',
              happenedAt: DateTime(2026, 9, 10),
              updatedAt: DateTime(2026, 9, 10, 10),
              doctor: 'د. حسام',
              place: 'عيادة النزهة',
              notes: 'Concor 5mg — Telfast 180mg — Augmentin 1g',
            ),
          ],
        ),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('care-entry-prescription')));
    await settle(tester);

    // الترويسة بأسامي حقولها — والاسم بنوع الورقة: «العيادة» مش «المكان»
    expect(find.text('تاريخ الورقة'), findsOneWidget);
    expect(find.text('الدكتور'), findsOneWidget);
    expect(find.text('العيادة'), findsOneWidget);
    expect(find.text('د. حسام'), findsOneWidget);
    expect(find.text('عيادة النزهة'), findsOneWidget);

    // والأدوية سطر لكل واحد — مش فقرة مربوطة بشَرطات
    expect(find.text('الأدوية (٣)'), findsOneWidget);
    expect(find.text('Concor 5mg'), findsOneWidget);
    expect(find.text('Telfast 180mg'), findsOneWidget);
    expect(find.text('Augmentin 1g'), findsOneWidget);
    expect(find.text('Concor 5mg — Telfast 180mg — Augmentin 1g'), findsNothing);
    expectNoRedAndMinSize(tester);
    holder.setActive(false);
  });

  screenTest('التحليل: «المعمل» مش «العيادة»، وعنوان النتايج بعددها', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          records: [
            CaregiverRecord(
              uuid: 'r1',
              kind: 'lab',
              title: 'صورة دم كاملة',
              happenedAt: DateTime(2026, 9, 12),
              updatedAt: DateTime(2026, 9, 12, 10),
              place: 'معمل البرج',
              labLines: const [
                CaregiverLabLine(testName: 'WBC', value: 7, unit: '10^3/uL', range: LabRange(low: 4, high: 11)),
                CaregiverLabLine(testName: 'Hb', value: 13, unit: 'g/dL', range: LabRange(low: 11, high: 15)),
              ],
            ),
          ],
        ),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('care-entry-lab')));
    await settle(tester);

    expect(find.text('المعمل'), findsOneWidget);
    expect(find.text('تاريخ التقرير'), findsOneWidget);
    expect(find.text('معمل البرج'), findsOneWidget);
    expect(find.text('النتايج (٢)'), findsOneWidget);
    expectNoRedAndMinSize(tester);
    holder.setActive(false);
  });

  screenTest('تقرير طويل: المتعلّم بيبان، والسليم بينطوي ورا «كل النتايج»',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          records: [
            CaregiverRecord(
              uuid: 'r1',
              kind: 'lab',
              title: 'صورة دم كاملة',
              happenedAt: DateTime(2026, 9, 12),
              updatedAt: DateTime(2026, 9, 12, 10),
              // الملاحظة هي **نفس** النتايج كفقرة — دي اللي اتشالت
              notes: 'WBC 12.4 10^3/uL — Hb 11.6 g/dL — PLT 250 10^3/uL',
              labLines: const [
                CaregiverLabLine(
                    testName: 'WBC', value: 12.4, unit: '10^3/uL', range: LabRange(low: 4, high: 11)),
                CaregiverLabLine(testName: 'Hb', value: 11.6, unit: 'g/dL', range: LabRange(low: 11, high: 15)),
                CaregiverLabLine(testName: 'PLT', value: 250, unit: '10^3/uL', range: LabRange(low: 150, high: 400)),
                CaregiverLabLine(testName: 'MCV', value: 88, unit: 'fL', range: LabRange(low: 80, high: 100)),
                // متعلّم **متأخر** في القايمة — الطي لازم يعدّيه
                CaregiverLabLine(testName: 'MCH', value: 27.2, unit: 'pg', range: LabRange(low: 27, high: 33)),
                CaregiverLabLine(testName: 'RDW', value: 13, unit: '%', range: LabRange(low: 11.5, high: 14.5)),
              ],
            ),
          ],
        ),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);

    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);
    // الملف بقى مداخل — التقرير جوّه مدخل التحاليل
    await tester.tap(find.byKey(const ValueKey('care-entry-lab')));
    await settle(tester);

    // **تمثيل واحد**: الفقرة راحت، والنتايج سطور
    expect(find.textContaining('WBC 12.4 10^3/uL —'), findsNothing,
        reason: 'الفقرة كانت نفس الكلام مرتين');
    // المتعلّم بيبان من غير ما حد يفتح حاجة
    expect(find.text(labAboveWord), findsOneWidget, reason: 'WBC ١٢.٤ فوق ٤–١١');
    expect(find.textContaining('WBC'), findsOneWidget);
    // وواحد قريب من الحد كمان متعلّم ومش منطوي
    expect(find.text(labNearWord), findsWidgets);
    // والسليم اللي بعد أول تلاتة منطوي
    expect(find.textContaining('RDW'), findsNothing);
    expect(find.text('كل النتايج (٦)'), findsOneWidget);

    await tester.tap(find.text('كل النتايج (٦)'));
    await settle(tester);
    expect(find.textContaining('RDW'), findsOneWidget);
    expect(find.text('كل النتايج (٦)'), findsNothing);
    holder.setActive(false);
  });

  screenTest('سجل من غير سطور تحاليل لسه بيعرض ملاحظته', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          records: [
            CaregiverRecord(
              uuid: 'r2',
              kind: 'visit',
              title: 'باطنة',
              happenedAt: DateTime(2026, 9, 12),
              updatedAt: DateTime(2026, 9, 12, 10),
              notes: 'الضغط كويس',
            ),
          ],
        ),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('care-entry-visit')));
    await settle(tester);
    expect(find.text('الضغط كويس'), findsOneWidget,
        reason: 'مفيش سطور — الملاحظة هي المحتوى الوحيد');
    holder.setActive(false);
  });

  screenTest('الابن بيشوف نطاق الورقة وعلامته — نفس كلام شاشة أبوه', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final holder = CaregiverSnapshotHolder(
      FakeCaregiverRemote()
        ..next = CaregiverSnapshot(
          patient: _patient,
          medications: const [],
          events: const [],
          records: [
            CaregiverRecord(
              uuid: 'r1',
              kind: 'lab',
              title: 'صورة دم كاملة',
              happenedAt: DateTime(2026, 9, 12),
              updatedAt: DateTime(2026, 9, 12, 10),
              labLines: const [
                CaregiverLabLine(
                    testName: 'WBC', value: 12.4, unit: '10^3/uL', range: LabRange(low: 4, high: 11)),
                CaregiverLabLine(
                    testName: 'Ferritin', value: 8, unit: 'ng/mL', range: LabRange(low: 30, high: 400)),
                CaregiverLabLine(
                    testName: 'Platelets', value: 10.5, unit: '10^3/uL', range: LabRange(low: 4, high: 11)),
                CaregiverLabLine(
                    testName: 'Sodium', value: 140, unit: 'mmol/L', range: LabRange(low: 135, high: 145)),
                CaregiverLabLine(testName: 'Uric acid', value: 5.1, unit: 'mg/dL'),
              ],
            ),
          ],
        ),
    );
    addTearDown(holder.dispose);
    holder.setActive(true);

    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(textDirection: TextDirection.rtl, child: CaregiverHealthScreen(holder: holder)),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('care-entry-lab')));
    await settle(tester);

    // نفس التلات كلمات بالحرف — مش نسخة تانية من الكلام
    expect(find.text(labAboveWord), findsOneWidget);
    expect(find.text(labBelowWord), findsOneWidget);
    expect(find.text(labNearWord), findsOneWidget);
    expect(find.byType(LabFlagBadge), findsNWidgets(3), reason: 'Sodium جوّه النطاق — من غير علامة');

    // ونطاق الورقة نفسه، وسطر الورقة اللي من غير نطاق
    expect(find.text('نطاق الورقة: من ٤ إلى ١١'), findsNWidgets(2));
    expect(find.text('نطاق الورقة: من ٣٠ إلى ٤٠٠'), findsOneWidget);
    expect(find.text(labNoRangeText), findsOneWidget);

    // الابن لسه ما بيحكمش: ولا كلمة نصيحة، والأحمر محبوس في العلامة
    for (final word in adviceWords) {
      expect(find.textContaining(word), findsNothing, reason: '«$word» عند الابن');
    }
    expectNoRedAndMinSize(tester);
    holder.setActive(false);
  });
}
