import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/f_sheet.dart';
import 'package:fakkarni/data/auth/auth_service.dart';
import 'package:fakkarni/data/push/push_tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/elder/elder_home_screen.dart';
import 'package:fakkarni/features/settings/notifications_screen.dart';
import 'package:fakkarni/domain/scheduling/ramadan.dart';
import 'package:fakkarni/features/link/sign_in_screen.dart';
import 'package:fakkarni/features/medication/add_sheet.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../features/scan/scan_test_support.dart' show expectNoRedAndMinSize;
import '../features/today/today_screen_test.dart' show expectNoRed;
import '../support/seeded_clock.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

class _Sink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled[n.id] = n;
  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();
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

/// «الإعدادات» تبويب في الدوك (مكان «العائلة»)، و«العائلة» سابت الشريط —
/// الربط بقى من الإعدادات ومن صف «مين بيتابعك» في الرئيسية.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('الإعدادات').last);
  // ضخّ محدود: نقطة المية بتلمع على طول، فـpumpAndSettle عمرها ما هتهدا
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  late AppDatabase db;
  late AppServices services;
  late _Sink sink;

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
        sink: sink = _Sink(),
        preferences: PreferencesRepository(db),
      ),
      patientId: patientId,
    );
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(seconds: 4)); // نبضة العلامة بتلف
  }

  Future<void> pumpShell(WidgetTester tester, {DateTime? now}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AppShell(routine: normalDay, now: now ?? DateTime(2026, 8, 31, 6)),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('أربع تبويبات بكلمة، «ضيف» بكلمة، والشريط العلوي علامة ف بس — ومفيش أحمر', (tester) async {
    await pumpShell(tester);

    for (final tab in AppShell.tabs) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('ضيف'), findsOneWidget, reason: 'الـ+ مش لوحده');
    // المخطط ٤ + طلب المالك: «الملف» و«الإعدادات» في الدوك، ومفتاح الوضع فوق
    expect(find.text('الملف الطبي'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('العائلة'), findsNothing, reason: 'الربط من الإعدادات وصف الدايرة');
    expect(find.byKey(const ValueKey('dark-mode-toggle')), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(TextButton)), findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing, reason: 'الهوية مش بوابة');
    expectNoRedAndMinSize(tester);
  });

  screenTest('التبويبات بتوصّل: الأدوية → الملف → الإعدادات', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('الأدوية').last);
    await settle(tester);
    expect(find.text('لسه مفيش أدوية.'), findsOneWidget);

    await tester.tap(find.text('الملف الطبي').last);
    await settle(tester);
    expect(find.text('الملف الطبي'), findsWidgets, reason: 'التبويب التالت بقى السجل');

    await openSettings(tester);
    expect(find.text('وضع رمضان'), findsOneWidget);
    expect(find.text('مواعيد يومك'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
    // التبويبات بتفضل حيّة في IndexedStack — بس برّه الشاشة
    expect(find.byType(MedicationsScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(MedicationsScreen), findsNothing);
  });

  screenTest('«ضيف» بيفتح شيت الصورة فيه أول اختيار', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(F.sheetDuration);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FSheet), findsOneWidget);
    // **الصورة الأول** — الزرار الأساسي الوحيد في الشيت.
    expect(find.widgetWithText(FilledButton, 'صوّر العلبة أو الشريط'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'صوّر روشتة'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'أكتبها بإيدي'), findsOneWidget);
    // نفس القايمة اللي كارت «ضيف دوا» بيفتحها — الشيت معرّف مرة واحدة
    for (final label in addSheetLabels) {
      expect(find.descendant(of: find.byType(FSheet), matching: find.text(label)), findsOneWidget, reason: label);
    }
    expectNoRedAndMinSize(tester);
  });

  screenTest('كارت رمضان في الإعدادات: حده ذهبي وهو شغّال والسطر بيقرا الحالة', (tester) async {
    await services.routines.enterRamadan(services.patientId, RamadanTimes.cairoDefaults);
    await pumpShell(tester);
    await openSettings(tester);
    await settle(tester);

    expect(find.text('شغّال'), findsOneWidget);
    final card = tester.widget<Material>(
      find.ancestor(of: find.text('وضع رمضان'), matching: find.byType(Material)).first,
    );
    final shape = card.shape as RoundedRectangleBorder;
    expect(shape.side.color, F.gold);
    expect(tester.widget<Text>(find.text('شغّال')).style?.color, F.ink, reason: 'الحافة ذهبي، الكلمة تتقري');
  });

  group('الإعدادات (المخطط 33)', () {
    screenTest('من غير جلسة: كارت الحساب «مش مربوط»، الصفوف، اللغة معطّلة، ومفيش خروج', (tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      await settle(tester);

      expect(find.text('مش مربوط'), findsWidgets);
      expect(find.text('حساب تجريبي'), findsNothing);
      for (final row in ['مواعيد يومك', 'وضع رمضان', 'التنبيهات', 'نمط كبار السن', 'دائرة الرعاية', 'اللغة']) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      // «الملف الصحي» تبويب في الدوك — بابين لأوضة واحدة اتشال منهم واحد.
      // «قريب منك» مكانه هنا زي ما هو (مالوش تبويب).
      expect(find.widgetWithText(InkWell, 'الملف الصحي'), findsNothing,
          reason: 'مفيش صف تاني لنفس الشاشة');
      expect(find.text('قريب منك'), findsOneWidget);
      expect(find.text('عربي'), findsOneWidget);
      // D5.2: الأب بيعرف بالظبط الابن بيشوف إيه — ومفيش حاجة من سحابة 0012 ناقصة من السطر
      final sees = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('caregiver-sees')),
        matching: find.byType(Text),
      ));
      for (final part in ['أدويتك', 'جرعاتك', 'قياسات السكر', 'الملف الصحي والتحاليل', 'أسئلة الدكتور', 'فصيلة الدم', 'الحساسية', 'الأمراض المزمنة', 'مش هيشوفوا أرقام الطوارئ ولا الصور']) {
        expect(sees.data, contains(part), reason: part);
      }
      expect(find.text('تسجيل الخروج'), findsNothing, reason: 'مفيش جلسة تخرج منها');
      // المؤجَّل مش موجود — ولا صف بيفتح على فراغ
      for (final gone in ['الاسم والسن', 'بطاقة الطوارئ', 'تصدير']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      expectNoRedAndMinSize(tester);
    });

    screenTest('جلسة مجهولة: «حساب تجريبي» بالحقيقة، والخروج بيمسح التوكن قبل الجلسة', (tester) async {
      final auth = _FakeAuth()..user = const FakkarniUser(id: 'u1', isAnonymous: true);
      final push = _FakePush(auth);
      services = AppServices(
        db: services.db,
        routines: services.routines,
        medications: services.medications,
        events: services.events,
        scheduler: services.scheduler,
        patientId: services.patientId,
        auth: auth,
        push: push,
      );
      await pumpShell(tester);
      await openSettings(tester);
      await settle(tester);

      expect(find.text('حساب تجريبي'), findsOneWidget);
      expect(find.text('حساب شخصي'), findsNothing, reason: 'قول الحقيقة');

      await tester.tap(find.text('تسجيل الخروج'));
      await settle(tester);
      expect(push.clearedBeforeSignOut, isTrue, reason: 'التوكن قبل الجلسة — مش بعدها');
      expect(auth.user, isNull);
      expect(find.text('مش مربوط'), findsWidgets);
    });
  });

  group('نمط كبار السن (D3.3، المخطط 18)', () {
    Future<void> addDose(String name, DayAnchor anchor, {int offset = 0}) =>
        services.medications.addMedication(
          patientId: services.patientId,
          name: name,
          timing: AnchorTiming(anchor, offset),
          startDate: DateTime(2026, 8, 31),
          amountLabel: 'قرص واحد',
        );

    screenTest('المفتاح في الإعدادات → تبويبتين بس ومن غير «ضيف»، وتاني دوسة بترجّع العادي', (tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('elder-mode')));
      await settle(tester);

      expect((await services.preferences.get()).elderMode, isTrue);
      for (final tab in AppShell.elderTabs) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
      expect(find.text('الأدوية'), findsNothing);
      expect(find.text('العائلة'), findsNothing);
      expect(find.text('ضيف'), findsNothing);
      expect(find.byType(ElderHomeScreen), findsOneWidget);

      // الخروج من نفس التبويب التاني
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('elder-mode')));
      await settle(tester);
      for (final tab in AppShell.tabs) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
    });

    screenTest('باقي اليوم بيبان تحت الكارت — بحالته، ومن غير أزرار', (tester) async {
      await services.preferences.setElderMode(true);
      // واحدة فاتت (٧:٠٠)، واحدة جاية (٢:٣٠)، وواحدة بالليل (٨:٠٠ م)
      await addDose('Concor', DayAnchor.breakfast, offset: -30);
      await addDose('Amaryl', DayAnchor.lunch);
      await addDose('Telfast', DayAnchor.dinner);
      await pumpShell(tester, now: DateTime(2026, 8, 31, 8));

      // التلاتة كلهم ظاهرين — إخفاء باقي اليوم بيتقري «أدويتي اتمسحت»
      for (final name in ['Concor', 'Amaryl', 'Telfast']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('باقي اليوم'), findsOneWidget);
      expect(find.text('جاي'), findsNWidgets(2), reason: 'الاتنين الجايين');
      expect(find.text('مفيش أدوية النهارده'), findsNothing);

      // صفوف باقي اليوم للقراية: ولا زرار فيها
      final home = find.byType(ElderHomeScreen);
      expect(find.descendant(of: home, matching: find.byType(FilledButton)), findsOneWidget);
      expect(find.descendant(of: home, matching: find.byType(OutlinedButton)), findsOneWidget,
          reason: '«بعد شوية» بتاع الكارت وبس');
    });

    screenTest('يوم من غير جرعات خالص → الجملة زي ما هي', (tester) async {
      await services.preferences.setElderMode(true);
      await pumpShell(tester, now: DateTime(2026, 8, 31, 8));

      expect(find.text('مفيش أدوية النهارده'), findsOneWidget);
      expect(find.text('باقي اليوم'), findsNothing);
    });

    screenTest('كارت فعل واحد بس وباقي اليوم للقراية، نص ٢٤+، «تم ✅» ٨٠، ومفيش «اتصل» ولا سطر صوت ولا أحمر', (tester) async {
      await services.routines.saveProfile(services.patientId, name: 'فاطمة', sex: Sex.f);
      await services.preferences.setElderMode(true);
      await addDose('Concor', DayAnchor.breakfast, offset: -30); // ٧:٠٠
      await addDose('Telfast', DayAnchor.dinner); // ٨:٠٠ م
      await pumpShell(tester, now: DateTime(2026, 8, 31, 8));

      expect(find.text('صباح الخير'), findsOneWidget);
      expect(find.text('يا فاطمة'), findsOneWidget);
      expect(find.text('Concor'), findsOneWidget);
      // باقي اليوم بيبان — بس للقراية. إخفاؤه كان بيتقري «أدويتي اتمسحت».
      expect(find.text('Telfast'), findsOneWidget, reason: 'باقي اليوم ظاهر');
      expect(find.text('باقي اليوم'), findsOneWidget);
      // **كارت الفعل واحد**: زرار واحد أساسي في الشاشة كلها، وهو بتاع الكارت
      // اللي فوق — صفوف باقي اليوم من غير أي زرار.
      expect(
        find.descendant(of: find.byType(ElderHomeScreen), matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(tester.getSize(find.widgetWithText(FilledButton, 'تم ✅')).height, F.elderPrimaryButtonHeight);

      final home = find.byType(ElderHomeScreen);
      for (final text in tester.widgetList<Text>(find.descendant(of: home, matching: find.byType(Text)))) {
        final size = text.style?.fontSize;
        if (size != null) expect(size, greaterThanOrEqualTo(F.elderTextSize), reason: text.data);
      }
      for (final gone in ['اتصل', 'قول']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      expectNoRed(tester);
    });

    screenTest('«تم ✅» بيسجّل الجرعة وبيجيب اللي بعدها، و«بعد شوية ⏰» تأجيل حقيقي', (tester) async {
      await services.preferences.setElderMode(true);
      await addDose('Concor', DayAnchor.breakfast, offset: -30); // ٧:٠٠
      await addDose('Telfast', DayAnchor.dinner); // ٨:٠٠ م
      await pumpShell(tester, now: DateTime(2026, 8, 31, 8));

      await tester.tap(find.text('بعد شوية ⏰'));
      await settle(tester);
      expect(sink.scheduled.keys, contains(snoozeIdFor(DateTime(2026, 8, 31, 7))));
      expect(find.text('هنفكّرك تاني بعد ربع ساعة'), findsOneWidget);

      await tester.tap(find.text('تم ✅'));
      await settle(tester);
      // الكارت بقى بتاع الجرعة اللي بعدها…
      expect(find.text('Telfast'), findsOneWidget);
      // …واللي اتاخدت **ما بتختفيش**: بتنزل «باقي اليوم» بعلامة «اتاخد».
      // اختفاؤها كان بيخلّي المريض يشك إنه نسيها (نفس قاعدة السكة العادية).
      expect(find.text('Concor'), findsOneWidget);
      expect(find.text('اتاخد'), findsOneWidget);
      expect(sink.scheduled.keys, isNot(contains(snoozeIdFor(DateTime(2026, 8, 31, 7)))),
          reason: 'التأكيد بيسكّت الخانة كلها — التأجيل معاها');
    });
  });

  group('التنبيهات (D3.3، المخطط 26)', () {
    Future<void> openNotifications(WidgetTester tester) async {
      await pumpShell(tester);
      await openSettings(tester);
      await settle(tester);
      await tester.tap(find.text('التنبيهات'));
      await settle(tester);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    }

    screenTest('الإلزامي 🔒 «دائمًا» ومالوش مفتاح، +١٥ و+٣٠ بس بمفتاح، والمؤجَّل مش موجود', (tester) async {
      await openNotifications(tester);

      expect(find.text('دائمًا'), findsNWidgets(3));
      expect(find.text('تفويت جرعة'), findsOneWidget);
      expect(find.text('في الموعد'), findsOneWidget);
      expect(find.text('+٦٠ د — إشعار لعيلتك أو ممرضك'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.text('+١٥ د'), findsOneWidget);
      expect(find.text('+٣٠ د'), findsOneWidget);
      expect(find.text('الإعدادات دي على الموبايل ده بس.'), findsOneWidget);
      for (final gone in ['ساعات الهدوء', 'نداء الطوارئ', 'سكر', 'انضمام', 'رفع تقرير', '+٤٥', 'مالك الرعاية']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      expectNoRedAndMinSize(tester);
    });

    screenTest('قفل الدرجتين من الشاشة → بيتحفظ، والجدولة فيها تذكيرات بس ومفيش ولا درجة', (tester) async {
      final today = DateTime.now();
      await services.medications.addMedication(
        patientId: services.patientId,
        name: 'Concor',
        timing: const AnchorTiming(DayAnchor.dinner, 0),
        startDate: DateTime(today.year, today.month, today.day),
      );
      await openNotifications(tester);

      await tester.tap(find.byKey(const ValueKey('rung-first')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('rung-second')));
      await settle(tester);

      final saved = await services.preferences.get();
      expect(saved.enabledRungs, isEmpty);
      expect(sink.scheduled.keys.where(isDoseId), isNotEmpty);
      expect(sink.scheduled.keys.where(isEscalationId), isEmpty);
      expect(tester.widgetList<Switch>(find.byType(Switch)).every((s) => !s.value), isTrue);

      // وفتح واحدة بيرجّعها هي بس
      await tester.tap(find.byKey(const ValueKey('rung-second')));
      await settle(tester);
      expect(sink.scheduled.keys.where((id) => escalationRungOf(id) == EscalationRung.second), isNotEmpty);
      expect(sink.scheduled.keys.where((id) => escalationRungOf(id) == EscalationRung.first), isEmpty);
    });
  });
}

class _FakeAuth implements AuthService {
  FakkarniUser? user;
  final _c = StreamController<FakkarniUser?>.broadcast();
  bool signedOut = false;
  @override
  Stream<FakkarniUser?> get authState async* {
    yield user;
    yield* _c.stream;
  }

  @override
  FakkarniUser? get currentUser => user;
  @override
  Future<void> signInToLink() async {}
  @override
  Future<void> signOut() async {
    signedOut = true;
    user = null;
    _c.add(null);
  }
}

class _FakePush implements PushTokens {
  _FakePush(this.auth);
  final _FakeAuth auth;
  bool? clearedBeforeSignOut;
  @override
  void start() {}
  @override
  Future<void> registerNow() async {}
  @override
  Future<void> clear() async => clearedBeforeSignOut ??= !auth.signedOut;
  @override
  Future<void> dispose() async {}
}
