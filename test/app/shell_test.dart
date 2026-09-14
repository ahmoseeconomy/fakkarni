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
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/ramadan.dart';
import 'package:fakkarni/features/link/sign_in_screen.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../features/scan/scan_test_support.dart' show expectNoRedAndMinSize;

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

void main() {
  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
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

  Future<void> pumpShell(WidgetTester tester) async {
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
            child: AppShell(routine: normalDay, now: DateTime(2026, 8, 31, 6)),
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
    expect(find.text('الإعدادات'), findsOneWidget, reason: 'تبويب بس — مش زرار فوق كمان');
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(TextButton)), findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing, reason: 'الهوية مش بوابة');
    expectNoRedAndMinSize(tester);
  });

  screenTest('التبويبات بتوصّل: الأدوية → العائلة → الإعدادات', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('الأدوية').last);
    await settle(tester);
    expect(find.text('لسه مفيش أدوية. دوس «ضيف» تحت.'), findsOneWidget);

    await tester.tap(find.text('العائلة').last);
    await settle(tester);
    expect(find.text('اربط ابني'), findsOneWidget);

    await tester.tap(find.text('الإعدادات').last);
    await settle(tester);
    expect(find.text('وضع رمضان'), findsOneWidget);
    expect(find.text('مواعيد يومك'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
    // التبويبات بتفضل حيّة في IndexedStack — بس برّه الشاشة
    expect(find.byType(MedicationsScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(MedicationsScreen), findsNothing);
  });

  screenTest('«ضيف» بيفتح شيت فيه «صوّر روشتة» و«أكتبها بإيدي»', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('ضيف'));
    await tester.pump();
    await tester.pump(F.sheetDuration);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FSheet), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'صوّر روشتة'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'أكتبها بإيدي'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('كارت رمضان في الإعدادات: حده ذهبي وهو شغّال والسطر بيقرا الحالة', (tester) async {
    await services.routines.enterRamadan(services.patientId, RamadanTimes.cairoDefaults);
    await pumpShell(tester);
    await tester.tap(find.text('الإعدادات').last);
    await settle(tester);

    expect(find.text('شغّال'), findsOneWidget);
    final card = tester.widget<Material>(
      find.ancestor(of: find.text('وضع رمضان'), matching: find.byType(Material)).first,
    );
    final shape = card.shape as RoundedRectangleBorder;
    expect(shape.side.color, F.gold);
    expect(tester.widget<Text>(find.text('شغّال')).style?.color, F.gold);
  });

  group('الإعدادات (المخطط 33)', () {
    screenTest('من غير جلسة: كارت الحساب «مش مربوط»، الصفوف التلاتة، اللغة معطّلة، ومفيش خروج', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('الإعدادات').last);
      await settle(tester);

      expect(find.text('مش مربوط'), findsWidgets);
      expect(find.text('حساب تجريبي'), findsNothing);
      for (final row in ['مواعيد يومك', 'وضع رمضان', 'دائرة الرعاية', 'اللغة']) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('عربي'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsNothing, reason: 'مفيش جلسة تخرج منها');
      // المؤجَّل مش موجود — ولا صف بيفتح على فراغ
      for (final gone in ['نمط كبار السن', 'التنبيهات', 'الاسم والسن', 'بطاقة الطوارئ', 'تصدير']) {
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
      await tester.tap(find.text('الإعدادات').last);
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
