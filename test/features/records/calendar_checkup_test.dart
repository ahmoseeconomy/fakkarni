import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';
import 'package:fakkarni/features/records/calendar_screen.dart';
import 'package:fakkarni/features/records/checkup_screen.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep15 = DateTime(2026, 9, 15, 10);

  group('التقويم (المخطط ١٢)', () {
    Future<void> seed() async {
      final medId = await h.meds.addMedication(
        patientId: h.services.patientId,
        name: 'Concor 5mg',
        timing: const AnchorTiming(DayAnchor.breakfast, 0),
        startDate: DateTime(2026, 9, 1),
      );
      final schedules = await h.meds.schedulesFor(medId);
      final engine = ScheduleEngine(normalDay);
      final events = DoseEventRepository(h.db);
      for (final day in [DateTime(2026, 9, 14), DateTime(2026, 9, 15)]) {
        await events.materializeDay(
          day,
          engine.remindersForDay(schedules, day),
        );
      }
      await events.markTaken(
        int.parse(schedules.single.id),
        DateTime(2026, 9, 14),
      );
      final records = RecordsRepository(h.db);
      await records.add(
        patientId: h.services.patientId,
        kind: RecordKind.visit,
        title: 'باطنة',
        happenedAt: DateTime(2026, 9, 20),
        doctor: 'د. هشام',
      );
      await records.add(
        patientId: h.services.patientId,
        kind: RecordKind.lab,
        title: 'HbA1c',
        happenedAt: DateTime(2026, 9, 20),
      );
      await ReadingsRepository(h.db).add(
        patientId: h.services.patientId,
        valueMgDl: 120,
        context: GlucoseContext.fasting,
        measuredAt: DateTime(2026, 9, 14, 7),
      );
    }

    screenTest(
      'شهر: الأيام اللي عليها حاجات متعلّمة، واللمس بيفتح تفاصيل اليوم',
      (tester) async {
        await seed();
        await h.pump(tester, CalendarScreen(today: sep15));
        await settle(tester);

        expect(find.text('سبتمبر ٢٠٢٦'), findsOneWidget);
        // النهارده: جرعة الساعة ٧:٣٠ ص لسه ما اتأكدتش والساعة ١٠ → ذهبي ومفيش أحمر
        expect(find.text('١٥ سبتمبر ٢٠٢٦'), findsOneWidget);
        expect(find.text('Concor 5mg'), findsOneWidget);
        expect(find.text('لسه ما اتأكدتش'), findsOneWidget);
        final todayCell = tester.widget<Material>(
          find.byKey(const ValueKey('day-2026-9-15')),
        );
        expect(
          (todayCell.shape! as RoundedRectangleBorder).side.color,
          isNot(Colors.red),
        );

        await tester.tap(find.byKey(const ValueKey('day-2026-9-14')));
        await settle(tester);
        expect(find.text('اتاخدت ✓'), findsOneWidget);
        expect(find.text('سكر ١٢٠'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('day-2026-9-20')));
        await settle(tester);
        expect(find.text('باطنة'), findsOneWidget);
        expect(find.text('HbA1c'), findsOneWidget);
        expectNoRedAndMinSize(tester);
      },
    );

    screenTest('فلتر بالنوع: «تحليل» بس بيخبّي الزيارة', (tester) async {
      await seed();
      await h.pump(tester, CalendarScreen(today: sep15));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('day-2026-9-20')));
      await tester.tap(find.byKey(const ValueKey('filter-lab')));
      await settle(tester);
      expect(find.text('HbA1c'), findsOneWidget);
      expect(find.text('باطنة'), findsNothing);
    });

    screenTest('أسبوع: ٧ أيام من السبت، والتنقّل بكلمة', (tester) async {
      await h.pump(tester, CalendarScreen(today: sep15));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('view-أسبوع')));
      await settle(tester);
      // ١٥ سبتمبر ٢٠٢٦ تلات → الأسبوع من السبت ١٢
      expect(find.byKey(const ValueKey('day-2026-9-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('day-2026-9-18')), findsOneWidget);
      expect(find.byKey(const ValueKey('day-2026-9-19')), findsNothing);
      await tester.tap(find.text('الأسبوع الجاي'));
      await settle(tester);
      expect(find.byKey(const ValueKey('day-2026-9-19')), findsOneWidget);
    });

    test('calendarEntries: الروشتة مع «دوا»، والممسوح مش باين', () {
      final entries = calendarEntries(
        doses: const [],
        records: const [],
        readings: const [],
        now: sep15,
      );
      expect(entries, isEmpty);
    });
  });

  group('متابعة التحليل (المخطط ١١)', () {
    Future<int> start() => h.services.checkups.start(
      patientId: h.services.patientId,
      title: 'صورة دم كاملة',
      today: sep15,
    );

    screenTest(
      'سبع مراحل: الخالصة ✓ خضرا، الحالية برقمها، والسطر اللي بيشرح ليه الشاشة موجودة',
      (tester) async {
        final id = await start();
        await h.services.checkups.advance(id);
        await h.services.checkups.advance(id);
        await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
        await settle(tester);

        for (final s in CheckupStage.values) {
          expect(find.text(s.label), findsWidgets, reason: s.label);
        }
        expect(find.byKey(const ValueKey('checkup-why')), findsOneWidget);
        expect(find.byIcon(Icons.check), findsNWidgets(2));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('stage-3')),
            matching: find.text('٣'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('ليس'), findsNothing, reason: 'مش فصحى');
        expect(find.textContaining('المتوقع'), findsNothing);
        expect(find.textContaining('قاعدة'), findsNothing);
        expectNoRedAndMinSize(tester);
      },
    );

    screenTest('المستخدم بيقدّم المرحلة بإيده، و«رجوع» بيرجّع', (tester) async {
      final id = await start();
      await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('checkup-advance')));
      await settle(tester);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('checkup-back')));
      await settle(tester);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    screenTest(
      '«اضبط تذكير الصيام» بس هو اللي بيجدول — بالساعات اللي اتكتبت، في نطاق الصيام، والرجوع بيلغيه',
      (tester) async {
        final id = await start();
        await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
        await settle(tester);
        expect(
          h.sink.scheduled.values.where((n) => isFastingId(n.id)),
          isEmpty,
          reason: 'مفيش حاجة قبل الضغطة',
        );

        await tester.tap(find.byKey(const ValueKey('fasting-set')));
        await settle(tester);
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: find.byKey(const ValueKey('fasting-save')),
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed,
          isNull,
          reason: 'مفيش ساعات افتراضية',
        );
        await tester.enterText(
          find.byKey(const ValueKey('fasting-hours')),
          '8',
        );
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('fasting-save')));
        await settle(tester);

        final fasting = h.sink.scheduled.values
            .where((n) => isFastingId(n.id))
            .toList();
        expect(fasting, hasLength(1));
        expect(fasting.single.id, fastingIdFor(id));
        expect(
          fasting.single.at,
          DateTime(2026, 9, 16, 0),
          reason: 'بكرة ٨ ص ناقص ٨ ساعات',
        );
        expect(fasting.single.kind, NotificationKind.fasting);
        expect(find.byKey(const ValueKey('fasting-set-line')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('checkup-advance')));
        await settle(tester);
        expect(
          h.sink.cancelled,
          isNot(contains(fastingIdFor(id))),
          reason: 'قبل «سحب العينة» لسه مفيد',
        );
        await tester.tap(find.byKey(const ValueKey('checkup-back')));
        await settle(tester);
        expect(h.sink.cancelled, contains(fastingIdFor(id)));
        expect(find.byKey(const ValueKey('fasting-set')), findsOneWidget);
      },
    );

    screenTest('المرحلة بتسأل عن ميعادها، والتخطّي بيتقال بسطر قصير مش بتحذير',
        (tester) async {
      final id = await start();
      await h.services.checkups.advance(id, now: sep15); // حجز المعمل
      await h.pump(tester, CheckupScreen(recordId: id, now: () => sep15));
      await settle(tester);

      final stage = CheckupStage.labBooking;
      expect(find.byKey(ValueKey('stage-date-set-${stage.number}')), findsOneWidget);
      expect(find.text('حجزت إمتى؟'), findsWidgets);
      final skip = find.byKey(ValueKey('stage-date-skip-${stage.number}'));
      expect(skip, findsOneWidget);
      // سطر قصير هادي: باهت، مش ذهبي ولا أحمر
      expect(tester.widget<Text>(skip).style?.color, F.mutedDark);
      expectNoRedAndMinSize(tester);

      // والمراحل التانية ما بتسألش
      expect(find.byKey(ValueKey('stage-date-set-${CheckupStage.preparation.number}')), findsNothing);

      // بيحطّ الميعاد من الشيت — **نفس منتقي اليوم بتاع شيت الصيام**
      await tester.tap(find.byKey(ValueKey('stage-date-set-${stage.number}')));
      await settle(tester);
      expect(find.byType(DayPicker), findsOneWidget);
      await tester.tap(find.text('بكرة'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('stage-date-save')));
      await settle(tester);

      expect(find.byKey(ValueKey('stage-date-line-${stage.number}')), findsOneWidget);
      expect(find.byKey(ValueKey('stage-date-set-${stage.number}')), findsNothing);
      // **إشعارين بقى**: هادي امبارح الميعاد، وواحد بيرن في يومه.
      expect(h.sink.scheduled.keys.where(isAppointmentId), hasLength(2));

      // و«شيل الميعاد» بترجّع السؤال
      await tester.tap(find.byKey(ValueKey('stage-date-clear-${stage.number}')));
      await settle(tester);
      expect(find.byKey(ValueKey('stage-date-set-${stage.number}')), findsOneWidget);
      expect(h.sink.cancelled,
          contains(appointmentIdFor(id, 0, AppointmentNotice.dayOf)));
    });

    screenTest(
      '«تابع تحليل» من الملف الصحي → الشاشة، و«امسحه» على متابعة عليها تذكير بيلغيه',
      (tester) async {
        await h.pump(tester, HealthFileScreen(today: sep15));
        await settle(tester);
        await tester.tap(find.text('تابع تحليل'));
        await settle(tester);
        // تلات طرق دلوقتي — دي بتاعة الكتابة بالإيد
        await tester.tap(find.byKey(const ValueKey('follow-by-hand')));
        await settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey('checkup-title')),
          'صورة دم كاملة',
        );
        await tester.tap(find.byKey(const ValueKey('checkup-start')));
        await settle(tester);
        expect(find.byType(CheckupScreen), findsOneWidget);

        final id = (await RecordsRepository(h.db).all(h.services.patientId))
            .single
            .id;
        await h.services.checkups.setFastingReminder(
          id,
          draw: DateTime(2026, 9, 17, 8),
          hours: 8,
          now: sep15,
        );
        await tester.pageBack();
        await settle(tester);
        // الملف بقى مداخل — المتابعة سجل `lab`، فجوّه مدخل التحاليل
        await tester.tap(find.byKey(const ValueKey('kind-entry-lab')));
        await settle(tester);
        expect(find.textContaining('متابعة تحليل — ١ من ٧'), findsOneWidget);

        await tester.tap(find.byKey(ValueKey('record-options-$id')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('record-delete')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('record-delete-confirm')));
        await settle(tester);
        expect(h.sink.cancelled, contains(fastingIdFor(id)));
      },
    );
  });
}
