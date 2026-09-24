import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/health/follow_display.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/features/emergency/emergency_facts_card.dart';

import '../../app/root_test.dart' show SilentSink;
import '../scan/scan_test_support.dart' show expectCaregiverDensity, screenTest, settle;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, alert, event, now;

/// **تبويبات الابن الأربعة، في الوضعين، مليانة وفاضية.**
///
/// الشاشات دي كانت ورثت مقاسات نمط كبار السن: متن ٢٠، هدف لمس ٥٦، حشو
/// ١٦. ده صح للأب وغلط للابن — راجل شغّال بيبص تلات ثواني ومحتاج يشوف
/// اليوم كله. الاختبار ده بيمسك التلاتة اللي بتغلط في إعادة التصميم:
/// النص يختفي في الليل، الحالة تتحمّل على اللون لوحده، والشاشة الفاضية
/// تبقى فراغ من غير كلام.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// ولا سطر معروض دلوقتي تحت ٤.٥:١ على أي أرضية — بتتنده بعد **كل** تبويب.
///
/// **بطاقة الطوارئ مستثناة، وليها أرضيتها هي.** نصّها أبيض على
/// `F.redDeep` (١٠٫٧:١) — بس الأرضية دي مش من أسطح الشاشة، فمقارنتها
/// بأرضية الصفحة بتقيس حاجة مش موجودة. نفس منطق استثناء `LabFlagBadge`
/// في `expectNoRedAndMinSize`: مقصور على الودجت، وأي نص تاني على نفس
/// الشاشة لسه بيتقاس.
void _expectReadable(WidgetTester tester, String where) {
  final grounds = [F.pageGround, F.cardGround, F.railGround];
  final ownGround = {
    for (final e in find
        .descendant(of: find.byType(EmergencyFactsCard), matching: find.byType(Text))
        .evaluate())
      e.widget,
  };
  var checked = 0;
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final colour = text.style?.color;
    if (colour == null || ownGround.contains(text)) continue;
    checked++;
    final best = grounds.map((g) => _contrast(colour, g)).reduce(math.max);
    expect(best, greaterThanOrEqualTo(4.5),
        reason: '«$where»: «${text.data}» بلون $colour مالوش تباين كافي');
  }
  expect(checked, greaterThan(0), reason: '«$where»: الحارس عدّى فاضي');
}

CaregiverSnapshot _full() => CaregiverSnapshot(
      patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
      medications: const [
        CaregiverMedication(
            uuid: 'm1', name: 'Concor 5mg', amountLabel: 'قرص واحد', rules: ['الفطار − ٣٠ د']),
      ],
      events: [
        event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken', actedAt: DateTime(2026, 8, 31, 8, 5)),
        event('Glucophage', DateTime(2026, 8, 31, 9), 'missed'),
        event('Telfast', DateTime(2026, 8, 31, 20), 'pending'),
        // بكرة — موجودة في الصورة، ومش المفروض تترسم بعد ما القسم اتشال
        event('Zestril', DateTime(2026, 9, 1, 7), 'pending'),
        // امبارح كامل — عشان سطر الأسبوع يبان
        event('Concor 5mg', DateTime(2026, 8, 30, 8), 'taken', actedAt: DateTime(2026, 8, 30, 8, 3)),
      ],
      alerts: [alert(doseState: 'missed', deliveryStatus: 'no_token')],
      lastUpdated: DateTime(2026, 8, 31, 13, 30),
      records: [
        CaregiverRecord(
          uuid: 'r1',
          kind: 'lab',
          title: 'تحليل سكر تراكمي',
          happenedAt: DateTime(2026, 8, 20),
          updatedAt: DateTime(2026, 8, 31, 12),
          labLines: const [CaregiverLabLine(testName: 'HbA1c', value: 7.1, unit: '%')],
        ),
        // متابعة تحليل واقفة عند «حجز المعمل» من غير ميعاد من ١١ يوم
        CaregiverRecord(
          uuid: 'f-lab',
          kind: 'lab',
          title: 'صورة دم كاملة',
          happenedAt: DateTime(2026, 8, 18),
          updatedAt: DateTime(2026, 8, 20),
          doctor: 'د. سامي',
          checkupStage: 2,
          checkupStageSince: DateTime(2026, 8, 20),
        ),
        CaregiverRecord(
          uuid: 'r2',
          kind: 'prescription',
          title: 'روشتة د. طارق',
          happenedAt: DateTime(2026, 8, 22),
          updatedAt: DateTime(2026, 8, 31, 11),
          notes: 'Concor 5mg',
        ),
        // متابعة زيارة ليها ميعاد بعد ٣ أيام
        CaregiverRecord(
          uuid: 'f-visit',
          kind: 'visit',
          title: 'متابعة الضغط',
          happenedAt: DateTime(2026, 8, 25),
          updatedAt: DateTime(2026, 8, 25),
          doctor: 'د. حسام',
          followKind: 'visit',
          checkupStage: 1,
          checkupStageSince: DateTime(2026, 8, 25),
          doctorVisitAt: DateTime(2026, 9, 3, 10),
        ),
      ],
      readings: [
        CaregiverReading(
          uuid: 'g1',
          valueMgDl: 128,
          measuredAt: DateTime(2026, 8, 31, 8),
          context: 'fasting',
          updatedAt: DateTime(2026, 8, 31, 8, 5),
        ),
      ],
      emergency: const CaregiverEmergency(bloodType: 'O+', allergies: 'بنسلين'),
      questions: [
        CaregiverQuestion(
          uuid: 'q1',
          body: 'ينفع أوقف الملح؟',
          writtenAt: DateTime(2026, 8, 30),
          asked: true,
          updatedAt: DateTime(2026, 8, 30, 9),
        ),
      ],
    );

/// يوم فاضي: مفيش تنبيهات، مفيش جرعات، مفيش ملف.
CaregiverSnapshot _empty() => CaregiverSnapshot(
      patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
      medications: const [],
      events: const [],
      alerts: const [],
      lastUpdated: DateTime(2026, 8, 31, 13, 30),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async {
    await db.close();
    F.setDark(on: false);
  });

  Future<void> pump(WidgetTester tester, CaregiverSnapshot data, {required bool dark}) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    F.setDark(on: dark);

    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    final patientId = await routines.ensurePatient();
    final remote = FakeCaregiverRemote()..next = data;

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
    await settle(tester);
  }

  /// بيمشي على التبويبات الأربعة ويقرا كل واحد.
  Future<void> walkTabs(WidgetTester tester, String mode) async {
    expectCaregiverDensity(tester);
    _expectReadable(tester, 'متابعة/$mode');

    await tester.tap(find.text('الأدوية'));
    await settle(tester);
    expectCaregiverDensity(tester);
    _expectReadable(tester, 'الأدوية/$mode');

    await tester.tap(find.text('السجل'));
    await settle(tester);
    expectCaregiverDensity(tester);
    _expectReadable(tester, 'الملف الصحي/$mode');

    await tester.tap(find.text('الإعدادات'));
    await settle(tester);
    expectCaregiverDensity(tester);
    _expectReadable(tester, 'الإعدادات/$mode');
  }

  for (final (mode, dark) in [('نهاري', false), ('ليلي', true)]) {
    screenTest('التبويبات الأربعة مليانة — $mode', (tester) async {
      await pump(tester, _full(), dark: dark);

      // ١ — الإجابة الأول، وفوق كل حاجة
      expect(find.byKey(const ValueKey('care-status')), findsOneWidget);
      expect(find.text('فيه ١ محتاجة انتباهك'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('care-status'))).dy,
        lessThan(tester.getTopLeft(find.text('تنبيهات')).dy),
        reason: 'الرد على «هو كويس؟» قبل تفاصيله',
      );
      // وآخر جرعة مؤكَّدة تحتها — «تمام» من غير دليل كلمة
      expect(find.textContaining('آخر جرعة مؤكَّدة — Concor 5mg'), findsOneWidget);

      // ٢ — الأقسام بترتيبها، وكل واحد بعدّاده بين قوسين (مش «·»:
      // «٠» العربية هي نقطة، وفيه اختبار بيقرا كل نص في lib ويوقع عليها)
      double y(String head) => tester.getTopLeft(find.text(head)).dy;
      expect(find.textContaining('Zestril'), findsNothing, reason: 'جرعة بكرة اترسمت');
      // **الزيارة المحجوزة فوق، مع المواعيد** — ميعاد قدّام الأب حاجة
      // الابن عايز يشوفها أول ما يفتح، مش في آخر الشاشة. واللي فضل في
      // «زيارات»/«تحاليل» هو اللي مالوش ميعاد جاي — ومفيش تكرار.
      for (final head in ['مواعيده الجاية', 'ما اتأكدتش', 'جاية', 'اتاخدت', 'تحاليل']) {
        expect(find.text(head), findsOneWidget, reason: 'القسم «$head» ناقص');
      }
      expect(find.text('زيارات'), findsNothing,
          reason: 'الزيارة الوحيدة ليها ميعاد جاي، فطلعت فوق ومااتكرّرتش');
      expect(y('مواعيده الجاية'), lessThan(y('ما اتأكدتش')));
      expect(y('ما اتأكدتش'), lessThan(y('جاية')), reason: 'المحتاجة انتباه فوق');
      expect(y('جاية'), lessThan(y('اتاخدت')));
      expect(y('اتاخدت'), lessThan(y('تحاليل')));
      expect(find.text('(١)'), findsWidgets, reason: 'العدّاد جنب العنوان');

      // ٣ — «جاية»: النهارده وبس. **قسم بكرة اتشال** (طلب المالك)،
      // فالصف بيقول قد إيه فاضل ومفيش عنوان يوم ولا صفوف بكرة.
      expect(find.text('كمان ٦ ساعات'), findsOneWidget);
      expect(find.textContaining('بكرة — '), findsNothing, reason: 'قسم بكرة اتشال');

      // ٤ — المتابعات: المرحلة بكلمتها، والميعاد وقد إيه فاضل، والواقفة
      expect(find.text('الزيارة اتحجزت'), findsOneWidget);
      expect(find.textContaining('د. حسام'), findsOneWidget);
      // **والميعاد ميعاد المرحلة — نفس جملة الأب بالحرف.** الزيارة
      // محجوزة ٣ سبتمبر، والصف اتبدأ ٢٥ أغسطس: تاريخ البداية ده عمره ما
      // يتعرض كأنه ميعاد (ده العطل اللي جه من جهاز حقيقي).
      expect(find.textContaining('بعد ٣ أيام — ٣ سبتمبر ٢٠٢٦'), findsOneWidget);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data ?? '', isNot(contains('٢٥ أغسطس ٢٠٢٦')),
            reason: 'تاريخ بداية المتابعة رجع يتعرض');
      }
      // **والمتابعة المفتوحة مش «جديد»** — هي حاجة شغّالة وليها قسمها فوق
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => (t.data ?? '').contains('زيارة: متابعة الضغط')),
        isEmpty,
        reason: 'المتابعة المفتوحة طلعت في «الجديد» كمان',
      );
      expect(find.text('حجز المعمل'), findsOneWidget);
      expect(find.textContaining(noFollowDateText), findsOneWidget);
      expect(find.textContaining('واقفة عند «حجز المعمل»'), findsOneWidget);

      // ٥ — الأسبوع في سطر، مش شبكة سبع خانات
      expect(find.byKey(const ValueKey('care-week')), findsOneWidget);
      expect(find.text('١ من ١ أيام كل الجرعات فيها اتقفلت'), findsOneWidget);

      // ٣ — «حدّث» موجود جنب سطر آخر تحديث
      expect(find.text('حدّث'), findsOneWidget);
      expect(find.textContaining('آخر تحديث من موبايل والدك'), findsOneWidget);

      await walkTabs(tester, mode);
    });

    screenTest('اليوم الفاضي بيتكلّم — $mode', (tester) async {
      await pump(tester, _empty(), dark: dark);

      // «مفيش حاجة» بتتقال، مش بتتسكت
      expect(find.byKey(const ValueKey('care-status')), findsOneWidget);
      expect(find.text('لسه مفيش خبر النهارده'), findsOneWidget);
      expect(find.text('لسه مفيش جرعة مؤكَّدة'), findsOneWidget);
      expect(find.text('مفيش جرعات متسجّلة النهارده لسه.'), findsOneWidget);
      // **مفيش قسم فاضي** — سطر الحالة فوق قال خلاص
      for (final head in ['تنبيهات', 'ما اتأكدتش', 'جاية', 'اتاخدت', 'متخطّية', 'زيارات', 'تحاليل']) {
        expect(find.text(head), findsNothing, reason: 'قسم «$head» فاضي المفروض يختفي');
      }
      expect(find.byKey(const ValueKey('care-week')), findsNothing,
          reason: 'أسبوع من غير جرعات مالوش سطر');
      expect(find.byKey(const ValueKey('newest')), findsNothing);

      await walkTabs(tester, mode);
      expect(find.text('مفيش أدوية متسجّلة على موبايل والدك لسه.'), findsNothing,
          reason: 'إحنا على الإعدادات دلوقتي');
    });
  }

  screenTest('الحالة بأيقونة وكلمة — مش لون لوحده', (tester) async {
    await pump(tester, _full(), dark: false);

    // كل صف جرعة فيه أيقونة حالة جنب كلمتها. والصف اللي في «جاية»
    // بيقول قد إيه فاضل بدل ما يكرّر اسم القسم — ومعاه ساعته برضه.
    for (final (label, icon) in [
      ('اتأكّدت ٨:٠٥ ص', Icons.check_circle_outline),
      ('اتنست — لسه ما اتأكدتش', Icons.error_outline),
      ('كمان ٦ ساعات', Icons.schedule),
    ]) {
      final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
      expect(find.descendant(of: row, matching: find.byIcon(icon)), findsOneWidget,
          reason: '«$label» من غير أيقونة = معنى محمول على اللون لوحده');
    }
  });

  screenTest('كروت «الأدوية» و«الملف الصحي» ملوّنة — والملف بلون نوعه',
      (tester) async {
    await pump(tester, _full(), dark: false);

    // **الأدوية: تبويب واحد، لون واحد** — القايمة مرجع مش حالة.
    await tester.tap(find.text('الأدوية'));
    await settle(tester);
    final medCard = tester.widget<Container>(
      find
          .ancestor(of: find.text('Concor 5mg'), matching: find.byType(Container))
          .first,
    );
    expect(
      ((medCard.decoration! as BoxDecoration).border! as Border).top.color,
      F.careAccentTaken,
    );

    // **الملف: كل نوع بلونه** — وتحليل ≠ روشتة
    await tester.tap(find.text('السجل'));
    await settle(tester);
    Color entryEdge(String key) {
      final card = tester.widget<Container>(
        find
            .descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Container))
            .first,
      );
      return ((card.decoration! as BoxDecoration).border! as Border).top.color;
    }

    expect(entryEdge('care-entry-lab'), F.careAccentLab);
    expect(entryEdge('care-entry-prescription'), F.careAccentTaken);
    expect(entryEdge('care-entry-lab'), isNot(entryEdge('care-entry-prescription')));
    // والمداخل اللي مش سجل محايدة
    expect(entryEdge('care-entry-readings'), F.careAccentSkipped);
    expect(entryEdge('care-entry-questions'), F.careAccentSkipped);

    expectCaregiverDensity(tester);
  });

  screenTest('الخطأ بيقول وبيدّي طريق — من غير قدرة جديدة', (tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    final patientId = await routines.ensurePatient();
    final remote = FakeCaregiverRemote()
      ..next = _full()
      ..failure = const CareCircleException(CareCircleFailure.offline);

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
    await settle(tester);

    expect(find.textContaining('مفيش نت'), findsOneWidget);
    expect(find.text('حاول تاني'), findsOneWidget);
    expectCaregiverDensity(tester);
  });
}
