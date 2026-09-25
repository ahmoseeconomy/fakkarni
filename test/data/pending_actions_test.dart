// «أخدته» من شاشة القفل عمرها ما تضيع (٢٥ سبتمبر ٢٠٢٦، آيفون حقيقي، نسخة
// profile): الإضافة ضيّعت أربع دوسات من خمسة. سويفت بتكتب كل دوسة ملف،
// ودارت بتطبّق الطابور عند الفتح والرجوع وفي الـisolate.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/bootstrap.dart';
import 'package:fakkarni/core/notifications/notification_service.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/services/pending_actions.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../features/scan/scan_test_support.dart';

File _queue(Directory dir, {required String action, String? payload, required DateTime at, String name = ''}) {
  dir.createSync(recursive: true);
  final f = File('${dir.path}/${name.isEmpty ? at.millisecondsSinceEpoch : name}.json');
  f.writeAsStringSync(jsonEncode({
    'v': 1,
    'action': action,
    'id': 1000123,
    'at': at.millisecondsSinceEpoch,
    'payload': ?payload,
  }));
  return f;
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('pending'));
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('الطابور', () {
    test('الأقدم الأول، والملف البايظ بيتشال من غير ما يوقّع', () {
      _queue(tmp, action: 'taken', at: DateTime(2026, 9, 25, 23, 36), payload: 'b');
      _queue(tmp, action: 'snooze', at: DateTime(2026, 9, 25, 19, 33), payload: 'a');
      File('${tmp.path}/bad.json').writeAsStringSync('{not json');
      final store = PendingActionStore(directoryOverride: tmp);
      final list = store.list();
      expect([for (final a in list) a.payload], ['a', 'b']);
      expect(File('${tmp.path}/bad.json').existsSync(), isFalse);
      expect(list.first.id, 1000123);
    });

    test('مفيش مجلد = مفيش طابور، ومفيش رمي', () {
      expect(PendingActionStore(directoryOverride: Directory('${tmp.path}/none')).list(), isEmpty);
    });

    test('drain: بيطبّق ويشيل؛ اللي وقع بيفضل للفتحة الجاية؛ التاني مرة لا-عملية', () async {
      final now = DateTime(2026, 9, 26, 8);
      _queue(tmp, action: 'taken', at: now.subtract(const Duration(hours: 8)), payload: 'ok');
      _queue(tmp, action: 'taken', at: now.subtract(const Duration(hours: 7)), payload: 'boom');
      final store = PendingActionStore(directoryOverride: tmp);
      final seen = <String?>[];
      Future<void> door(String? a, String? p) async {
        seen.add(p);
        if (p == 'boom') throw StateError('قاعدة مقفولة');
      }

      expect(await drainPendingActions(store, door, now: now), 1);
      expect(seen, ['ok', 'boom']);
      expect([for (final a in store.list()) a.payload], ['boom'], reason: 'الفاشل فاضل');
      seen.clear();
      expect(await drainPendingActions(store, (a, p) async => seen.add(p), now: now), 1);
      expect(seen, ['boom']);
      expect(store.list(), isEmpty);
    });

    test('تأجيل أقدم من المهلة بيتشال من غير تطبيق — والتأكيد بيتطبّق مهما كان عمره', () async {
      final now = DateTime(2026, 9, 26, 8);
      _queue(tmp, action: NotificationActions.snooze, at: now.subtract(const Duration(hours: 9)), payload: 'old');
      _queue(tmp, action: NotificationActions.snooze, at: now.subtract(const Duration(minutes: 10)), payload: 'fresh');
      _queue(tmp, action: NotificationActions.taken, at: now.subtract(const Duration(days: 2)), payload: 'taken');
      final seen = <String?>[];
      await drainPendingActions(PendingActionStore(directoryOverride: tmp), (a, p) async => seen.add(p), now: now);
      expect(seen, ['taken', 'fresh']);
      expect(tmp.listSync().whereType<File>(), isEmpty);
    });

    test('removeMatching بيشيل دوسة الـisolate بس', () {
      _queue(tmp, action: 'taken', at: DateTime(2026, 9, 25, 10), payload: 'mine');
      _queue(tmp, action: 'taken', at: DateTime(2026, 9, 25, 11), payload: 'other');
      final store = PendingActionStore(directoryOverride: tmp)..removeMatching(action: 'taken', payload: 'mine');
      expect([for (final a in store.list()) a.payload], ['other']);
    });
  });

  group('الباب الحقيقي', () {
    late Harness h;
    setUp(() async {
      h = Harness();
      await h.setUp();
    });
    tearDown(() => h.tearDown());

    test('دوسة «أخدته» اتكتبت في الطابور وإحنا مقفولين → عند الفتح الجرعة taken والإعادات والدرجات اتلغت', () async {
      final s = h.services;
      final id = await h.meds.addMedication(
        patientId: s.patientId,
        name: 'Nexium',
        timing: const AnchorTiming(DayAnchor.dinner, 0),
        startDate: aug31,
      );
      // آخر جدولة قبل الجرعة بشوية، والدوسة بعدها بخمس دقايق
      await s.scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 19, 55));
      final now = DateTime(2026, 8, 31, 20, 5);
      final at = DateTime(2026, 8, 31, 20);
      final doseId = notificationIdFor(at);
      final before = h.sink.scheduled.keys.toSet();
      expect(before, contains(doseId));
      final rung1 = escalationIdFor(at, EscalationRung.first);
      final repeat0 = repeatIdFor(at, 0);
      expect(before, containsAll([rung1, repeat0]), reason: 'الدرجات والإعادات متجدولة قبل الدوسة');

      // سويفت كتبت الدوسة — والإضافة ما شغّلتش أي isolate
      _queue(tmp, action: NotificationActions.taken, at: now, payload: encodePayloadFor(aug31, ['$id']));

      final applied = await drainPendingActions(
        PendingActionStore(directoryOverride: tmp),
        (a, p) => handleNotificationAction(db: s.db, services: s, actionId: a, payload: p),
        now: now.add(const Duration(minutes: 3)),
      );
      expect(applied, 1);
      final events = await s.events.watchDay(aug31).first;
      expect(events.single.state, DoseState.taken, reason: '«يومك» تفتح على الجرعة متأكّدة');
      expect(h.sink.cancelled, containsAll([doseId, rung1, repeat0]), reason: 'القاعدة الخامسة: الخانة كلها سكتت');
      expect(tmp.listSync().whereType<File>(), isEmpty);
    });
  });

  group('المرايا والترتيب', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final root = File('lib/app/root.dart').readAsStringSync();
    final boot = File('lib/app/bootstrap.dart').readAsStringSync();

    test('سويفت بتكتب نفس المجلد ونفس المفاتيح، قبل الإضافة، وبتاخد مهلة خلفية', () {
      expect(swift, contains('static let folder = "$pendingActionsFolder"'));
      for (final key in ['"action"', '"payload"', '"at"', '"id"']) {
        expect(swift, contains(key), reason: 'مفتاح $key');
      }
      expect(swift, contains('static let category = "fakkarni_dose"'));
      expect(File('lib/core/notifications/notification_service.dart').readAsStringSync(), contains("'fakkarni_dose'"));
      final didReceive = swift.indexOf('didReceive response: UNNotificationResponse');
      final enqueue = swift.indexOf('PendingActionQueue.enqueue(response)', didReceive);
      final superCall = swift.indexOf('super.userNotificationCenter(', didReceive);
      expect(enqueue, greaterThan(didReceive));
      expect(enqueue, lessThan(superCall), reason: 'الطابور قبل ما الإضافة تاخد الرد');
      expect(swift, contains('beginBackgroundTask(withName: "FakkarniPendingAction")'));
      expect(swift, contains('setenv("FAKKARNI_DOCS"'), reason: 'المسار لدارت من غير قناة');
    });

    test('main: الطابور بعد تهيئة الإشعارات وقبل السحابة', () {
      final init = main.indexOf('NotificationService.init(');
      final drain = main.indexOf('drainPendingActions(');
      final cloud = main.indexOf('final cloud = await initSupabaseAuth();');
      expect(drain, greaterThan(init));
      expect(drain, lessThan(cloud), reason: 'إطلاق خلفية عمره ثواني — الوعد قبل الشبكة');
    });

    test('الرجوع للمقدمة: الطابور قبل إعادة الجدولة — والـisolate بيشيل دوسته ويطبّق الباقي', () {
      final resumed = root.indexOf('AppLifecycleState.resumed');
      final drain = root.indexOf('drainPendingActions(', resumed);
      final resched = root.indexOf('rescheduleAll()', resumed);
      expect(drain, greaterThan(resumed));
      expect(drain, lessThan(resched));
      final done = boot.indexOf("diag('Isolate: خلص المعالج");
      expect(boot.indexOf('drainOthers(action: response.actionId, payload: response.payload', done), greaterThan(done));
    });
  });
}
