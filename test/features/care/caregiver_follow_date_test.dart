// **نفس العطل، في الملف اللي `0e7991c` نساه.**
//
// من جهاز حقيقي، حساب الابن: زيارة محجوزة **بكرة** كانت بتتعرض بتاريخ
// **الروشتة** اللي المتابعة اتبدت منها. الجولة اللي فاتت صلّحت «متابعة»
// (`caregiver_screen.dart`) وسابت «الملف الصحي»
// (`caregiver_health_screen.dart:408`).
//
// **وده بيقول حاجة عن الاختبارات مش عن الكود**: مكانش فيه ولا لقطة فيها
// متابعة مفتوحة على تبويب الملف الصحي، فالسطر الغلط كان أخضر. الحارس
// الأخير في الملف ده بيمشي على **كل** سطح عند الابن بتاريخ ورقة مميّز
// ويقع لو ظهر في أي مكان — فملف جديد بيتنسي بيقع كمان.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/format/arabic_time.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/health/follow_display.dart';
import 'package:fakkarni/features/care/caregiver_health_screen.dart';
import 'package:fakkarni/features/care/caregiver_snapshot_holder.dart';
import 'package:drift/native.dart';

import '../../app/root_test.dart' show SilentSink;
import '../scan/scan_test_support.dart' show screenTest, settle;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, now;

const _patient = CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد');

/// تاريخ الورقة — بعيد خالص عن أي ميعاد، عشان ظهوره ما يبقاش صدفة.
final paperDate = DateTime(2023, 9, 13);
const paperText = '١٣ سبتمبر ٢٠٢٣';

/// ميعاد الزيارة: بكرة بالنسبة لـ[now] (٣١ أغسطس ٢٠٢٦).
final tomorrow = DateTime(2026, 9, 1, 10);

CaregiverRecord _openVisit() => CaregiverRecord(
      uuid: 'v1',
      kind: 'visit',
      title: 'د. حسام',
      happenedAt: paperDate,
      updatedAt: DateTime(2026, 8, 30),
      doctor: 'د. حسام',
      followKind: 'visit',
      checkupStage: 1, // الزيارة اتحجزت
      checkupStageSince: DateTime(2026, 8, 30),
      doctorVisitAt: tomorrow,
    );

/// متابعة تحليل مفتوحة من غير ميعاد.
CaregiverRecord _openLab({String uuid = 'f1', String title = 'تقرير تحليل — ٦ نتايج'}) =>
    CaregiverRecord(
      uuid: uuid,
      kind: 'lab',
      title: title,
      happenedAt: paperDate,
      updatedAt: DateTime(2026, 8, 29),
      checkupStage: 2, // حجز المعمل
      checkupStageSince: DateTime(2026, 8, 29),
    );

/// تقرير خلص — ده اللي **بيفضل** بتاريخه.
CaregiverRecord _finishedLab() => CaregiverRecord(
      uuid: 'r1',
      kind: 'lab',
      title: 'صورة دم كاملة',
      happenedAt: DateTime(2026, 8, 20),
      updatedAt: DateTime(2026, 8, 20),
      labLines: const [CaregiverLabLine(testName: 'HbA1c', value: 7.1, unit: '%')],
    );

CaregiverSnapshot _snapshot(List<CaregiverRecord> records) => CaregiverSnapshot(
      patient: _patient,
      medications: const [],
      events: const [],
      records: records,
    );

void main() {
  /// **من غير `setActive`**: السؤال الدوري (١٠ ث) مؤقّت شغّال، و
  /// `testWidgets` بتقع عليه عند التفكيك بدل ما تقول نتيجة الاختبار.
  /// اللي محتاجينه هنا صورة واحدة، و`refresh` بتجيبها من غير مؤقّت.
  Future<CaregiverSnapshotHolder> holderFor(List<CaregiverRecord> records) async {
    final holder = CaregiverSnapshotHolder(FakeCaregiverRemote()..next = _snapshot(records));
    addTearDown(holder.dispose);
    await holder.refresh();
    return holder;
  }

  Future<void> openHealth(WidgetTester tester, CaregiverSnapshotHolder holder) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: CaregiverHealthScreen(holder: holder, now: now),
      ),
    ));
    await settle(tester);
  }

  /// بيفتح مدخل نوع سجل من «الملف الصحي».
  Future<void> openKind(WidgetTester tester, String kind) async {
    await tester.tap(find.byKey(ValueKey('care-entry-$kind')));
    await settle(tester);
  }

  List<String> shown(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) ?t.data,
      ];

  group('١ — الميعاد ميعاد المرحلة، مش تاريخ الورقة', () {
    screenTest('زيارة محجوزة بكرة بتقول «بكرة» — ومفيش تاريخ الروشتة', (tester) async {
      await openHealth(tester, await holderFor([_openVisit()]));
      await openKind(tester, 'visit');

      expect(find.textContaining('بكرة'), findsWidgets);
      expect(
        shown(tester).where((l) => l.contains(paperText)),
        isEmpty,
        reason: 'تاريخ الورقة رجع يتعرض كأنه ميعاد — نفس عطل ٠e7991c',
      );
      // **نفس الجملة اللي «متابعة» والأب بيقروها** — دالة واحدة.
      expect(find.text(followDateFull(tomorrow, now)), findsOneWidget);
      expect(find.text('الميعاد'), findsOneWidget, reason: 'مش «تاريخ الورقة»');
    });

    screenTest('ومتابعة من غير ميعاد بتقول كده بالحرف', (tester) async {
      await openHealth(tester, await holderFor([_openLab()]));
      await openKind(tester, 'lab');

      expect(find.text(noFollowDateText), findsOneWidget);
      expect(shown(tester).where((l) => l.contains(paperText)), isEmpty);
    });

    screenTest('والاسم باللي بنتابعه، مش بعنوان الورقة', (tester) async {
      await openHealth(tester, await holderFor([_openLab()]));
      await openKind(tester, 'lab');

      expect(find.text('متابعة تحليل'), findsOneWidget);
      expect(find.text('تقرير تحليل — ٦ نتايج'), findsNothing);
    });

    screenTest('**والتقرير اللي خلص بيفضل بتاريخه**', (tester) async {
      await openHealth(tester, await holderFor([_finishedLab()]));
      await openKind(tester, 'lab');

      expect(find.text(arabicDate(DateTime(2026, 8, 20))), findsOneWidget);
      expect(find.text('تاريخ التقرير'), findsOneWidget);
      expect(find.text('الميعاد'), findsNothing, reason: 'ورقة خلصت مالهاش ميعاد جاي');
    });
  });

  group('٢ — «منتظر» فوق و«تمت» تحت، بنفس دالة الأب', () {
    screenTest('القسمين بعدّادهم، والمنتظر فوق', (tester) async {
      await openHealth(
        tester,
        await holderFor([_finishedLab(), _openLab(), _openLab(uuid: 'f2', title: 'وظايف كبد')]),
      );
      await openKind(tester, 'lab');

      expect(find.text(waitingSectionLabel(2)), findsOneWidget);
      expect(find.text(doneSectionLabel(1)), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(waitingSectionLabel(2))).dy,
        lessThan(tester.getTopLeft(find.text(doneSectionLabel(1))).dy),
      );
      expect(
        tester.getTopLeft(find.text(doneSectionLabel(1))).dy,
        lessThan(tester.getTopLeft(find.text('صورة دم كاملة')).dy),
      );
    });

    screenTest('وقسم فاضي ما بيظهرش — غيابه هو «مفيش حاجة هنا»', (tester) async {
      await openHealth(tester, await holderFor([_finishedLab()]));
      await openKind(tester, 'lab');

      expect(find.textContaining('منتظر'), findsNothing);
      expect(find.textContaining('تمت ('), findsNothing,
          reason: 'قسم واحد معروض — عنوان فوق كل الشاشة زيادة');
      expect(find.text('صورة دم كاملة'), findsOneWidget);
    });

    screenTest('واللي ليه ميعاد قبل اللي مالوش', (tester) async {
      await openHealth(tester, await holderFor([_openLab(), _openVisit()]));
      // الزيارة ليها ميعاد بكرة، والتحليل مالوش — بس هما نوعين مختلفين،
      // فبنشوف الترتيب جوّه نوع واحد: تحليلين، واحد بميعاد وواحد من غير.
      await openKind(tester, 'visit');
      expect(find.text(followDateFull(tomorrow, now)), findsOneWidget);
    });
  });

  group('٣ — الحارس: ولا تاريخ ورقة لمتابعة مفتوحة، في أي سطح عند الابن', () {
    // **الحارس ده هو اللي المفروض يمنع التكرار.** بيمشي على التبويبات
    // الأربعة وعلى القوايم اللي بتتفتح منها، بلقطة فيها متابعتين
    // مفتوحتين بتاريخ ورقة مميّز — ولو ظهر في أي نص، بيقع.
    screenTest('كل تبويب وكل قايمة', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final routines = RoutineRepository(db);
      final meds = MedicationRepository(db);
      final events = DoseEventRepository(db);
      final patientId = await routines.ensurePatient();

      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        AppScope(
          services: AppServices(
            db: db,
            routines: routines,
            medications: meds,
            events: events,
            scheduler: ReminderScheduler(
              routines: routines,
              medications: meds,
              events: events,
              patientId: patientId,
              sink: SilentSink(),
            ),
            patientId: patientId,
            caregiver: FakeCaregiverRemote()
              ..next = _snapshot([_openVisit(), _openLab(), _finishedLab()]),
          ),
          child: MaterialApp(
            theme: F.light,
            builder: (context, child) =>
                Directionality(textDirection: TextDirection.rtl, child: child!),
            home: CaregiverShell(onNotLinked: () {}, now: now),
          ),
        ),
      );
      await settle(tester);

      void check(String where) {
        final lines = shown(tester);
        expect(lines, isNotEmpty, reason: '«$where»: الحارس عدّى على شاشة فاضية');
        expect(
          lines.where((l) => l.contains(paperText)),
          isEmpty,
          reason: '«$where»: تاريخ ورقة متابعة مفتوحة معروض — $lines',
        );
      }

      check('متابعة');
      for (final tab in ['الأدوية', 'السجل']) {
        await tester.tap(find.text(tab));
        await settle(tester);
        check(tab);
      }
      // والقوايم اللي بتتفتح من «الملف الصحي»
      for (final kind in ['visit', 'lab']) {
        await openKind(tester, kind);
        check('قايمة $kind');
        await tester.pageBack();
        await settle(tester);
      }
    });
  });
}
