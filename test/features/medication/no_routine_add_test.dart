import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/widgets/f_wheels.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';

import '../scan/scan_test_support.dart';

/// **«ضيف دوا» من غير روتين: مفيش ميعاد بيتخمّن.**
///
/// كل المراسي مش متحددة. الجرعة بتبدأ على ساعة ثابتة المستخدم هو اللي
/// بيأكّدها؛ ولو اختار «قبل الفطار» بيتسأل «بتفطر الساعة كام؟» مرة واحدة،
/// والإجابة بتتحفظ في روتينه متحددة، وبعدها المرساة عادية.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<RoutineRepository> noRoutine() async {
    final routines = RoutineRepository(h.db);
    await routines.saveRoutine(h.services.patientId, DayRoutine.none);
    return routines;
  }

  Future<void> pumpAdd(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, AddMedicationScreen(routine: DayRoutine.none, today: aug31, initialName: 'Concor'));
  }

  screenTest('الفورم بيقول إن المواعيد مش متحددة، والمحرّر بيفتح على ساعة ثابتة — مفيش رقم من روتين افتراضي', (tester) async {
    await noRoutine();
    await pumpAdd(tester);
    expect(find.textContaining('ما حدّدتش مواعيد يومك'), findsOneWidget);
    // الصف بيقول إن الفطار مش متحدد، و«احفظ» مقفولة لحد ما يختار
    expect(find.text('الفطار — مش متحدد'), findsOneWidget);
    expect(find.textContaining('— ٧:٠٠ ص'), findsNothing, reason: 'ولا ساعة من الافتراضي');
    expect(tester.widget<FilledButton>(find.descendant(
        of: find.byKey(const ValueKey('save-medication')), matching: find.byType(FilledButton))).onPressed,
        isNull);

    await tester.tap(find.byKey(const ValueKey('dose-row-0')));
    await settle(tester);
    // المحرّر على ساعة محددة: البكرة موجودة، والتنبيه مكتوب، ومفيش معاينة من الافتراضي
    expect(find.byType(FTimeWheel), findsOneWidget);
    expect(find.text('ساعة ثابتة — مش هتتحرك مع روتين يومك'), findsOneWidget);
    expect(find.text('يعني حوالي ٧:٠٠ ص'), findsNothing, reason: 'ولا معاينة من الافتراضي');

    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);
    expect(find.text('الساعة ٨:٠٠ ص'), findsOneWidget, reason: 'الصف بيقول اللي اختاره');
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.single.timing, FixedTiming(MinuteOfDay.hm(8)), reason: 'اللي على البكرة وأكّده');
  });

  screenTest('«قبل الفطار؟» بتسأل عن الفطار مرة، بتحفظه متحدد، وبعدها الجرعة على المرساة', (tester) async {
    final routines = await noRoutine();
    await pumpAdd(tester);
    await tester.tap(find.byKey(const ValueKey('dose-row-0')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('mode-anchor')));
    await settle(tester);
    expect(find.text('قبل الفطار؟'), findsOneWidget, reason: 'مرساة مش متحددة بعلامة استفهام');

    await tester.tap(find.text('قبل الفطار؟'));
    await settle(tester);
    expect(find.text('بتفطر الساعة كام؟'), findsOneWidget);
    // «تمام» مقفولة لحد ما يختار
    final confirm = tester.widget<FilledButton>(
      find.descendant(of: find.byKey(const ValueKey('anchor-confirm')), matching: find.byType(FilledButton)),
    );
    expect(confirm.onPressed, isNull);
    // البكرة واقفة على ٧:٣٠ — دقيقة واحدة لفوق = ٧:٣١ (وبعدها «تمام» بتتفتح)
    await tester.drag(find.byKey(FTimeWheel.minutesKey), const Offset(0, -FTimeWheel.itemExtent));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('anchor-confirm')));
    await settle(tester);

    // اتحفظ متحدد — والشريحة بقت عادية والمعاينة بتحسب منه
    final routine = (await routines.getRoutine(h.services.patientId))!;
    expect(routine.isSet(DayAnchor.breakfast), isTrue);
    expect(routine.breakfast, MinuteOfDay.hm(7, 31), reason: 'بالدقيقة الواحدة');
    expect(routine.isSet(DayAnchor.lunch), isFalse, reason: 'سؤال واحد بس');
    expect(find.text('قبل الفطار'), findsOneWidget);
    expect(find.text('قبل الفطار؟'), findsNothing);
    expect(find.text('يعني حوالي ٧:٠١ ص'), findsOneWidget);

    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);
    expect(find.text('قبل الفطار بنص ساعة — ٧:٠١ ص'), findsOneWidget, reason: 'الصف بيقول المرساة وساعتها');
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await settle(tester);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.single.timing, const AnchorTiming(DayAnchor.breakfast, -30));
  });

  screenTest('قفل السؤال من غير إجابة: ولا حاجة اتكتبت، والمحرّر لسه على الساعة الثابتة', (tester) async {
    final routines = await noRoutine();
    await pumpAdd(tester);
    await tester.tap(find.byKey(const ValueKey('dose-row-0')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('mode-anchor')));
    await settle(tester);
    await tester.tap(find.text('قبل الفطار؟'));
    await settle(tester);
    // اقفل الشيت بالسحب لتحت
    await tester.drag(find.text('بتفطر الساعة كام؟'), const Offset(0, 600));
    await settle(tester);
    expect(find.text('بتفطر الساعة كام؟'), findsNothing);
    expect((await routines.getRoutine(h.services.patientId))!.isSet(DayAnchor.breakfast), isFalse);
    expect(find.text('قبل الفطار؟'), findsOneWidget);
  });

  screenTest('روتين كامل: نفس السلوك القديم بالحرف — المراسي أول حاجة والمعاينة منها', (tester) async {
    await RoutineRepository(h.db).saveRoutine(h.services.patientId, normalDay);
    await h.pump(tester, AddMedicationScreen(routine: normalDay, today: aug31, initialName: 'Concor'));
    // الصف محسوب من المرساة على طول، والدوسة عليه تفتح المحرّر على المراسي
    expect(find.text('قبل الفطار بنص ساعة — ٧:٠٠ ص'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dose-row-0')));
    await settle(tester);
    expect(find.byType(FTimeWheel), findsNothing);
    expect(find.text('قبل الفطار'), findsOneWidget);
    expect(find.text('يعني حوالي ٧:٠٠ ص'), findsOneWidget);
  });
}
