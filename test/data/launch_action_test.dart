import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/notifications/notification_service.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/notification_actions.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import '../support/seeded_clock.dart';

/// **العيب اللي الجهاز كشفه (٢٠ سبتمبر ٢٠٢٦):** على iOS والتطبيق مقفول،
/// دوسة «أخدته» من شاشة القفل ما بتعدّيش لا على الـisolate ولا على
/// `_onTap` — الرد بيستنى في `getNotificationAppLaunchDetails()`.
/// و`init()` كانت بتاخد منه الـpayload وترمي الـactionId، فالزرار بيبقى
/// دوسة عادية: التطبيق بيفتح على الجرعة والصف عمره ما اتكتب.
void main() {
  final normalDay = DayRoutine(
    wake: MinuteOfDay.hm(7),
    breakfast: MinuteOfDay.hm(7, 30),
    lunch: MinuteOfDay.hm(14, 30),
    dinner: MinuteOfDay.hm(20),
    sleep: MinuteOfDay.hm(23, 30),
  );

  NotificationResponse launch({String? actionId, int id = 1}) =>
      NotificationResponse(
        notificationResponseType: actionId == null
            ? NotificationResponseType.selectedNotification
            : NotificationResponseType.selectedNotificationAction,
        id: id,
        actionId: actionId,
        payload: 'p$id',
      );

  setUp(NotificationService.resetForTest);
  tearDown(NotificationService.resetForTest);

  group('رد الإطلاق بيوصل للمعالج، مش لـlastPayload', () {
    test('زرار «أخدته» بيترجّع للمعالجة — وعمره ما ينزل lastPayload', () {
      final response = launch(actionId: NotificationActions.taken);

      expect(NotificationService.applyLaunchResponse(response), same(response));
      expect(NotificationService.lastPayload.value, isNull,
          reason: 'لو نزل هنا، الزرار بيتحوّل لدوسة عادية والجرعة ما بتتكتبش');
    });

    test('«فكّرني بعدين» زيه بالظبط', () {
      final response = launch(actionId: NotificationActions.snooze);

      expect(NotificationService.applyLaunchResponse(response), same(response));
      expect(NotificationService.lastPayload.value, isNull);
    });

    test('دوسة عادية من غير زرار بتفضل تنزل lastPayload زي ما هي', () {
      final response = launch();

      expect(NotificationService.applyLaunchResponse(response), isNull);
      expect(NotificationService.lastPayload.value, 'p1');
    });

    test('مفيش رد إطلاق → مفيش حاجة', () {
      expect(NotificationService.applyLaunchResponse(null), isNull);
      expect(NotificationService.lastPayload.value, isNull);
    });

    test('زرار مش بتاعنا بيتعامل كدوسة عادية', () {
      final response = launch(actionId: 'something_else');

      expect(NotificationService.applyLaunchResponse(response), isNull);
      expect(NotificationService.lastPayload.value, 'p1');
    });
  });

  group('مرة واحدة بس لكل (جرعة، زرار)', () {
    test('نفس الرد مرتين → التانية مش بترجّع حاجة', () {
      final response = launch(actionId: NotificationActions.taken);

      expect(NotificationService.applyLaunchResponse(response), isNotNull);
      expect(NotificationService.applyLaunchResponse(response), isNull,
          reason: 'init() تانية معناها إعادة جدولة ورفع على الفاضي');
    });

    test('جرعة تانية بترجّع عادي', () {
      expect(
          NotificationService.applyLaunchResponse(
              launch(actionId: NotificationActions.taken, id: 1)),
          isNotNull);
      expect(
          NotificationService.applyLaunchResponse(
              launch(actionId: NotificationActions.taken, id: 2)),
          isNotNull);
    });

    test('_onTap على نفس الرد بعد الإطلاق → المعالج ما بيتندهش تاني', () {
      final response = launch(actionId: NotificationActions.taken);
      final seen = <String>[];
      NotificationService.onAction = (action, payload) => seen.add(action);

      expect(NotificationService.applyLaunchResponse(response), isNotNull);
      NotificationService.tapForTest(response);

      expect(seen, isEmpty, reason: 'البابين بيوصلوا لنفس الجرعة');
      NotificationService.onAction = null;
    });

    test('_onTap لوحده (من غير رد إطلاق) بيشتغل عادي', () {
      final seen = <String>[];
      NotificationService.onAction = (action, payload) => seen.add(action);

      NotificationService.tapForTest(launch(actionId: NotificationActions.taken));

      expect(seen, [NotificationActions.taken]);
      NotificationService.onAction = null;
    });
  });

  group('السكّة الحقيقية، مش نسخة منها', () {
    // الدرس المكتوب في الأعراف: اختبار بيمرّ على جملة غير اللي التطبيق
    // بينفّذها مش شمول — ده مكان أعمى. الحارس ده بيثبّت إن `init()` نفسها
    // بتعدّي على [applyLaunchResponse]، مش بس إن الدالة شغّالة لوحدها.
    final source =
        File('lib/core/notifications/notification_service.dart').readAsStringSync();

    test('init بتمرّر رد الإطلاق كامل على القرار', () {
      expect(source, contains('applyLaunchResponse(response)'));
    });

    test('ومحدش بياخد الـpayload من رد الإطلاق على طول', () {
      expect(source, isNot(contains('launch.notificationResponse?.payload')),
          reason: 'ده بالظبط السطر اللي كان بيرمي الـactionId');
    });

    test('main بتعالج رد الإطلاق قبل أي تهيئة سحابة', () {
      // التعليقات بتتشال الأول: الشرح فوق بيسمّي نفس الدوال، ومقارنة
      // مواضع على نص فيه شرح بتقيس التعليق مش الكود.
      final main = File('lib/main.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final handled = main.indexOf('door(launched.actionId');
      final cloud = main.indexOf('initSupabaseAuth()');
      final token = main.indexOf('FirebaseTokenSource.initialise()');
      expect(handled, isNot(-1));
      expect(handled, lessThan(cloud),
          reason: 'إطلاق الخلفية عمره ثواني — الصف قبل الشبكة');
      expect(handled, lessThan(token));
    });
  });

  test('رد إطلاق بزرار بيكتب الجرعة فعلاً — زي ما main بتعمل', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final sink = _Sink();
    final routines = RoutineRepository(db);
    final patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    await meds.addMedication(
      patientId: patientId,
      name: 'Concor',
      timing: AnchorTiming(DayAnchor.breakfast, -30),
      startDate: DateTime(2026, 8, 31),
      amountLabel: 'قرص',
    );
    final events = DoseEventRepository(db);
    final scheduler = ReminderScheduler(
      routines: routines,
      medications: meds,
      events: events,
      patientId: patientId,
      sink: sink,
    );
    await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 6));

    final first = sink.scheduled.values
        .where((n) => isDoseId(n.id))
        .reduce((a, b) => a.at.isBefore(b.at) ? a : b);

    // نفس السطرين اللي في main بالظبط
    final response = NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotificationAction,
      id: first.id,
      actionId: NotificationActions.taken,
      payload: first.payload,
    );
    final action = NotificationService.applyLaunchResponse(response);
    expect(action, isNotNull);
    await NotificationActionHandler(
      routines: routines,
      medications: meds,
      events: events,
      scheduler: scheduler,
      patientId: patientId,
    ).handle(action!.actionId, action.payload);

    final taken = (await db.select(db.doseEvents).get())
        .where((e) => e.state == DoseState.taken);
    expect(taken, isNotEmpty, reason: 'ده الوعد كله');
    expect(NotificationService.lastPayload.value, isNull);
  });
}

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
