import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/features/care/caregiver_snapshot_holder.dart' show refreshEvery;

import '../../app/root_test.dart' show SilentSink;
import '../scan/scan_test_support.dart' show screenTest;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, event, now;

/// شاشة الابن كانت بتتجمّد: موبايل الأب دفع، والابن فاضل باصص على الصورة
/// القديمة لحد ما يقفل التطبيق ويفتحه. السؤال كل [refreshEvery] هو العلاج —
/// بس **وتبويب بيانات ظاهر («متابعة» أو «الأدوية» أو «الملف الصحي») والتطبيق في
/// المقدمة**. `CaregiverShell` بيحتفظ بالتبويبات حية، فمن غير الشرط ده كان
/// هيفضل يسأل السحابة وهو على الإعدادات أو والموبايل في جيبه.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<FakeCaregiverRemote> pumpShell(WidgetTester tester) async {
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    final patientId = await routines.ensurePatient();
    final remote = FakeCaregiverRemote()
      ..next = CaregiverSnapshot(
        patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
        medications: const [],
        events: [event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending')],
        lastUpdated: DateTime(2026, 8, 31, 13),
      );
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
          caregiver: remote,
        ),
        child: MaterialApp(
          theme: F.light,
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: CaregiverShell(onNotLinked: () {}, now: now),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return remote;
  }

  /// بيعدّي [n] دورات سؤال كاملة ويرجّع كام نداء حصل فيها.
  Future<int> callsOver(WidgetTester tester, FakeCaregiverRemote remote, int n) async {
    final before = remote.calls;
    for (var i = 0; i < n; i++) {
      await tester.pump(refreshEvery);
      await tester.pump(const Duration(milliseconds: 50));
    }
    return remote.calls - before;
  }

  screenTest('على تبويب المتابعة: بيسأل كل ١٠ ثواني', (tester) async {
    final remote = await pumpShell(tester);
    expect(remote.calls, 1, reason: 'سؤال الفتح');

    expect(await callsOver(tester, remote, 3), 3);
  });

  screenTest('على «الإعدادات»: ولا نداء — والرجوع للمتابعة بيسأل على طول ويرجّع السؤال الدوري',
      (tester) async {
    final remote = await pumpShell(tester);

    await tester.tap(find.text('الإعدادات'));
    await tester.pump();
    expect(await callsOver(tester, remote, 4), 0, reason: 'التبويب مش ظاهر');

    final before = remote.calls;
    await tester.tap(find.text('متابعة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(remote.calls, before + 1, reason: 'رجع يبص → صورة طازة، مش بعد ١٠ ثواني');

    expect(await callsOver(tester, remote, 2), 2);
  });

  screenTest('«الملف الصحي» تبويب بيانات برضه: الدخول بيسأل على طول، والسؤال الدوري شغّال',
      (tester) async {
    final remote = await pumpShell(tester);

    final before = remote.calls;
    await tester.tap(find.text('السجل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(remote.calls, before + 1, reason: 'دخل تبويب بيانات → صورة طازة');

    expect(await callsOver(tester, remote, 2), 2, reason: 'سحبة واحدة لكل دورة — التبويبين بيقروا نفس الصورة');
  });

  screenTest('«الأدوية» تبويب بيانات برضه — الدخول بيسأل، والدورة شغّالة', (tester) async {
    // تبويب جديد (جولة ٢٩) — لو اتنسي من `dataTabs`، الابن بيبص على
    // قايمة واقفة والسؤال الدوري ساكت، من غير ما حاجة تقول له.
    final remote = await pumpShell(tester);

    final before = remote.calls;
    await tester.tap(find.text('الأدوية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(remote.calls, before + 1, reason: 'دخل تبويب بيانات → صورة طازة');

    expect(await callsOver(tester, remote, 2), 2);
  });

  screenTest('التطبيق في الخلفية: ولا نداء — والرجوع للمقدمة بيرجّعه', (tester) async {
    final remote = await pumpShell(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(await callsOver(tester, remote, 4), 0, reason: 'الموبايل في جيبه');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(await callsOver(tester, remote, 2), 2);
  });
}
