import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/emergency_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/emergency/emergency_card_screen.dart';
import 'package:fakkarni/features/emergency/emergency_edit_screen.dart';
import 'package:fakkarni/features/emergency/emergency_info_screen.dart';
import 'package:fakkarni/features/emergency/emergency_widgets.dart';
import '../../support/seeded_clock.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

class _Sink implements ReminderSink {
  @override
  Future<void> schedule(PlannedNotification n) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};
  @override
  Future<void> ensurePermissions() async {}
}

void screenTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}

void main() {
  late AppDatabase db;
  late AppServices services;
  late List<String> dialed;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
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
        sink: _Sink(),
        preferences: PreferencesRepository(db),
      ),
      patientId: patientId,
    );
    dialed = [];
    dialNumber = (n) async => dialed.add(n);
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(textDirection: TextDirection.rtl, child: home),
        ),
      ),
    );
    await settle(tester);
  }

  void expectMinSize(WidgetTester tester) {
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
    }
  }

  Future<void> fill() async {
    await services.routines.saveProfile(services.patientId, name: 'أحمد محمود', sex: Sex.m, age: 72);
    await EmergencyRepository(db).save(
      services.patientId,
      const EmergencyInfo(
        bloodType: 'O+',
        allergies: 'بنسلين — سلفا',
        chronicConditions: 'سكر نوع ٢ — ضغط',
        contacts: [EmergencyContact(name: 'محمد', phone: '01001234567', relation: 'ابني')],
      ),
    );
    final stopped = await services.medications.addMedication(
      patientId: services.patientId,
      name: 'Xatral 10mg',
      timing: const AnchorTiming(DayAnchor.dinner, 0),
      startDate: DateTime(2026, 8, 31),
    );
    await services.medications.addMedication(
      patientId: services.patientId,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.breakfast, 0),
      startDate: DateTime(2026, 8, 31),
    );
    await services.medications.stopMedication(stopped);
  }

  group('معلومات الطوارئ (المخطط ١٩)', () {
    screenTest('فاضية → كل حقل «لسه ما اتملاش» وبس — ولا حقل اتملا لوحده', (tester) async {
      await pump(tester, const EmergencyInfoScreen());

      // فصيلة الدم، الحساسية، الاسم والسن، الأمراض المزمنة — وجهات الاتصال
      // ليها فعل صريح بدل السطر الهادي (مكانها الوحيد اللي بيتضاف منه).
      expect(find.text(notFilled), findsNWidgets(4));
      expect(find.byKey(const ValueKey('add-emergency-contact')), findsOneWidget);
      expect(find.text('مفيش أدوية متسجّلة'), findsOneWidget);
      for (final invented in ['لا يوجد', 'غير معروف', 'O+', 'A+', 'مفيش حساسية']) {
        expect(find.text(invented), findsNothing, reason: invented);
      }
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, F.redDeep);
      expectMinSize(tester);
    });

    screenTest('مليانة → بالحرف، والأدوية الحالية من medications (الموقوف مش فيها)، وكل جهة اتصال بزرار', (tester) async {
      await fill();
      await pump(tester, const EmergencyInfoScreen());

      expect(find.text('O+'), findsOneWidget);
      expect(find.text('بنسلين — سلفا'), findsOneWidget);
      expect(find.text('سكر نوع ٢ — ضغط'), findsOneWidget);
      expect(find.text('أحمد محمود — ٧٢ سنة'), findsOneWidget);
      expect(find.text('Concor\u00A05mg'), findsOneWidget);
      expect(find.textContaining('Xatral'), findsNothing, reason: 'اتوقف');
      expect(find.text(notFilled), findsNothing);

      await tester.tap(find.text('اتصال'));
      await settle(tester);
      expect(dialed, ['01001234567']);
      expectMinSize(tester);
    });

    screenTest('«عدّل» → الاستمارة بتحفظ بإيد إنسان، و«مش عارف» بيسيب الفصيلة فاضية', (tester) async {
      await pump(tester, const EmergencyInfoScreen());
      await tester.tap(find.text('عدّل'));
      await settle(tester);
      expect(find.byType(EmergencyEditScreen), findsOneWidget);

      await tester.tap(find.text('B-'));
      await tester.enterText(find.byKey(const ValueKey('allergies')), 'بنسلين');
      await tester.tap(find.text('+ ضيف جهة اتصال'));
      await settle(tester);
      final contact = find.byKey(const ValueKey('contact-0'));
      final fields = find.descendant(of: contact, matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'سارة');
      await tester.enterText(fields.at(1), '01112223334');
      await tester.enterText(fields.at(2), 'بنتي');
      await tester.tap(find.text('مش عارف'));
      await tester.tap(find.text('احفظ'));
      await settle(tester);

      final saved = await EmergencyRepository(db).get(services.patientId);
      expect(saved.bloodType, isNull, reason: '«مش عارف» = مش متسجّل');
      expect(saved.allergies, 'بنسلين');
      expect(saved.chronicConditions, isNull);
      expect(saved.contacts, [const EmergencyContact(name: 'سارة', phone: '01112223334', relation: 'بنتي')]);
      expect(find.text('بنسلين'), findsOneWidget, reason: 'الشاشة اتحدّثت');
    });
  });

  group('الإسعاف — تأكيد صريح قبل الطلب', () {
    screenTest('الدوسة بتسأل «تتصل بالإسعاف ١٢٣؟» ومفيش طلب قبل التأكيد، و«لأ» ما بيطلبش', (tester) async {
      await pump(tester, const EmergencyInfoScreen());

      await tester.tap(find.byKey(const ValueKey('ambulance')));
      await settle(tester);
      expect(find.text('تتصل بالإسعاف ١٢٣؟'), findsOneWidget);
      expect(dialed, isEmpty, reason: 'لمسة بالغلط ما بتطلبش إسعاف');

      await tester.tap(find.text('لأ، رجوع'));
      await settle(tester);
      expect(find.text('تتصل بالإسعاف ١٢٣؟'), findsNothing);
      expect(dialed, isEmpty);

      await tester.tap(find.byKey(const ValueKey('ambulance')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('ambulance-confirm')));
      await settle(tester);
      expect(dialed, ['123']);
    });

    screenTest('الزرار ٦٤ وأحمر F.red — وده مسموح هنا بس', (tester) async {
      await pump(tester, const EmergencyInfoScreen());
      final button = find.byKey(const ValueKey('ambulance'));
      expect(tester.getSize(button).height, F.primaryButtonHeight);
      final style = tester.widget<ButtonStyleButton>(button).style!;
      expect(style.backgroundColor!.resolve({}), F.red);
    });
  });

  group('بطاقة الطوارئ (المخطط ٣٢)', () {
    screenTest('الساعة، الكارت الأبيض بالبيانات، جهات الاتصال، والإسعاف — ومفيش كلمة «شاشة القفل»', (tester) async {
      await fill();
      var clock = DateTime(2026, 8, 31, 9, 41, 58);
      await pump(tester, EmergencyCardScreen(now: () => clock));

      expect(tester.widget<Text>(find.byKey(const ValueKey('emergency-clock'))).data, '٩:٤١');
      clock = DateTime(2026, 8, 31, 9, 42, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(find.byKey(const ValueKey('emergency-clock'))).data, '٩:٤٢');

      expect(find.text('أحمد محمود — ٧٢ سنة'), findsOneWidget);
      expect(find.text('O+'), findsOneWidget);
      expect(find.text('بنسلين — سلفا'), findsOneWidget);
      expect(find.text('Concor\u00A05mg'), findsOneWidget);
      expect(find.text('محمد (ابني)'), findsOneWidget);
      expect(find.byKey(const ValueKey('ambulance')), findsOneWidget);
      for (final lie in ['شاشة القفل', 'فك الموبايل', 'فك الهاتف', 'مشاركة']) {
        expect(find.textContaining(lie), findsNothing, reason: lie);
      }
      expectMinSize(tester);
      // الساعة والنبضة بيتلغوا مع الشاشة — screenTest بيفكّها، ولو مؤقّت فضل الاختبار بيوقع
    });

    screenTest('فاضية → «لسه ما اتملاش» في كل حقل وفي جهات الاتصال', (tester) async {
      await pump(tester, EmergencyCardScreen(now: () => DateTime(2026, 8, 31, 9)));
      expect(find.text(notFilled), findsNWidgets(4));
      expect(find.text('جهات الاتصال: $notFilled'), findsOneWidget);
    });
  });

  group('الوصول بلمسة واحدة', () {
    Future<void> pumpShell(WidgetTester tester) =>
        pump(tester, AppShell(routine: normalDay, now: DateTime(2026, 8, 31, 8)));

    // المخطط ٤: البيل ده أحمر مصمت — وده المكان الوحيد برّه شاشتي الطوارئ.
    // الأحمر بيفضل معناه لأن مفيش حاجة تانية بتاخده: الجرعة الفايتة ذهبي.
    screenTest('«طوارئ» فوق → البطاقة بلمسة — والبيل أحمر مصمت', (tester) async {
      await pumpShell(tester);
      final shortcut = find.byKey(const ValueKey('emergency-shortcut'));
      expect(tester.getSize(shortcut).height, greaterThanOrEqualTo(F.minTapTarget));
      final style = tester.widget<ButtonStyleButton>(shortcut).style!;
      expect(style.backgroundColor!.resolve({}), F.red);
      expect(style.foregroundColor!.resolve({}), F.onRed);

      await tester.tap(shortcut);
      await settle(tester);
      expect(find.byType(EmergencyCardScreen), findsOneWidget);
    });

    screenTest('في نمط كبار السن كمان', (tester) async {
      await services.preferences.setElderMode(true);
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('emergency-shortcut')));
      await settle(tester);
      expect(find.byType(EmergencyCardScreen), findsOneWidget);
    });

    screenTest('الإعدادات → «معلومات الطوارئ»', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('الإعدادات').last);
      await settle(tester);
      await tester.tap(find.text('معلومات الطوارئ'));
      await settle(tester);
      expect(find.byType(EmergencyInfoScreen), findsOneWidget);
    });
  });

  group('جهات الاتصال: الطريق اللي محدش كان بيلاقيه', () {
    screenTest('مفيش جهات → فعل صريح بيفتح التعديل على القسم ده', (tester) async {
      await pump(tester, const EmergencyInfoScreen());

      final add = find.byKey(const ValueKey('add-emergency-contact'));
      expect(add, findsOneWidget);
      expect(find.text('ضيف جهة اتصال'), findsOneWidget);
      expect(tester.getSize(add).height, greaterThanOrEqualTo(F.minTapTarget));

      await tester.tap(add);
      await settle(tester);

      expect(find.byType(EmergencyEditScreen), findsOneWidget);
      // وصف جاهز في القسم اللي جه عشانه — مش محتاج يدوّر ولا يدوس «+» تاني
      expect(find.byKey(const ValueKey('contact-0')), findsOneWidget);
    });

    screenTest('فيه جهات → بتتعرض زي ما هي، ومفيش الفعل ده', (tester) async {
      await EmergencyRepository(db).save(
        services.patientId,
        const EmergencyInfo(
          contacts: [EmergencyContact(name: 'محمد', phone: '01001234567', relation: 'ابني')],
        ),
      );
      await pump(tester, const EmergencyInfoScreen());

      expect(find.text('محمد (ابني)'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-emergency-contact')), findsNothing);
    });

    screenTest('صف فاضي خالص ما بيتحفظش كجهة اتصال', (tester) async {
      await pump(tester, const EmergencyEditScreen(focusContacts: true));
      await settle(tester);
      expect(find.byKey(const ValueKey('contact-0')), findsOneWidget);

      await tester.tap(find.text('احفظ'));
      await settle(tester);

      final info = await EmergencyRepository(db).get(services.patientId);
      expect(info.contacts, isEmpty, reason: 'اسم فاضي وزرار «اتصال» بيدوّر على لا حاجة');
    });
  });
}
