// «أخدته» على الإشعار الأصلي **وكل إعادة**، والتطبيق مقتول أو في الخلفية أو
// قدّامه (آيفون، ٢٦ سبتمبر ٢٠٢٦، release): أول «أخدته» ما اتسجّلتش والتطبيق
// عايش في الخلفية — الإضافة بتبعت الزرار لإنجن تاني، مش للتطبيق اللي شغّال.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/bootstrap.dart';
import 'package:fakkarni/core/notifications/notification_service.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/services/pending_actions.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/escalation/repeat_alerts.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../features/scan/scan_test_support.dart';

/// نفس الملف اللي `PendingActionQueue.enqueue` في سويفت بتكتبه.
void _swiftQueues(Directory dir, {required String payload, required int id, required DateTime at}) {
  dir.createSync(recursive: true);
  File('${dir.path}/${at.microsecondsSinceEpoch}.json').writeAsStringSync(jsonEncode({
    'v': 1,
    'action': NotificationActions.taken,
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'payload': payload,
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Harness h;
  late int medId;
  final dueAt = DateTime(2026, 8, 31, 20); // العشا في normalDay

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('live');
    h = Harness();
    await h.setUp();
    medId = await h.meds.addMedication(
      patientId: h.services.patientId,
      name: 'Concor',
      timing: const AnchorTiming(DayAnchor.dinner, 0),
      startDate: aug31,
    );
    // آخر جدولة قبل الجرعة بشوية — الأصلي والإعادات والدرجات متجدولين
    await h.services.scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 19, 50));
  });
  tearDown(() async {
    LiveActions.door = null;
    LiveActions.store = PendingActionStore();
    await h.tearDown();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> door(String? a, String? p) =>
      handleNotificationAction(db: h.services.db, services: h.services, actionId: a, payload: p);

  /// كل رقم الخانة دي ممكن ترنّه — القاعدة ٥: كله يسكت.
  List<int> slotIds() => [
        notificationIdFor(dueAt),
        escalationIdFor(dueAt, EscalationRung.first),
        escalationIdFor(dueAt, EscalationRung.second),
        for (var i = 0; i < maxRepeats; i++) repeatIdFor(dueAt, i),
      ];

  /// اللي فعلاً بيرن: مع الدرجتين شغّالين، إعادة الـ+١٥ بتتشال (الدرجة بترن
  /// لوحدها في الدقيقة دي) — فالمتجدول الأصلي والدرجتين وإعادتين.
  List<int> ringing() => slotIds().where((id) => id != repeatIdFor(dueAt, maxRepeats - 1)).toList();

  group('(ب) الأصلي والإعادات: نفس الجرعة', () {
    test('الإشعار الأصلي وكل إعادة وكل درجة شايلين **نفس** الـpayload — جرعة العشا', () {
      final scheduled = h.sink.scheduled;
      final original = scheduled[notificationIdFor(dueAt)];
      expect(original, isNotNull);
      expect(scheduled.containsKey(repeatIdFor(dueAt, maxRepeats - 1)), isFalse, reason: '+١٥ للدرجة بس');
      for (final id in ringing().skip(1)) {
        expect(scheduled[id], isNotNull, reason: 'رقم $id متجدول');
        expect(scheduled[id]!.payload, original!.payload, reason: 'رقم $id بيشاور على جرعة تانية');
      }
      final decoded = decodePayload(original!.payload)!;
      expect(decoded.routineDay, aug31);
      expect(decoded.scheduleIds, hasLength(1), reason: 'جرعة Concor ($medId) بس');
    });

    for (final (label, id) in [
      ('الأصلي', (DateTime at) => notificationIdFor(at)),
      ('إعادة +٥', (DateTime at) => repeatIdFor(at, 0)),
      ('إعادة +١٠', (DateTime at) => repeatIdFor(at, 1)),
      ('درجة +١٥', (DateTime at) => escalationIdFor(at, EscalationRung.first)),
    ]) {
      test('«أخدته» على $label → taken، والخانة كلها اتلغت (الإعادات اللي جاية ما بترنّش)', () async {
        final n = h.sink.scheduled[id(dueAt)]!;
        await door(NotificationActions.taken, n.payload);
        final events = await h.services.events.watchDay(aug31).first;
        expect(events.single.state, DoseState.taken);
        expect(h.sink.cancelled, containsAll(slotIds()));
        // ولا حاجة باقية لجرعة الساعة ٨ دي. (نفس الرقم ممكن يرجع لجرعة ٢
        // أكتوبر — الأرقام بتتكرر كل ٣٢ يوم عن قصد، والجدولة بعد التأكيد
        // بتمشي بالساعة الحقيقية.)
        final stillForThisDose = [
          for (final e in h.sink.scheduled.entries)
            if (slotIds().contains(e.key) && e.value.at.difference(dueAt).inHours.abs() < 2) e.key,
        ];
        expect(stillForThisDose, isEmpty, reason: 'لسه فيه تنبيه للجرعة اللي اتأكّدت');
      });
    }
  });

  group('(أ) التطبيق عايش: سويفت بتسلّم للإنجن الرئيسي', () {
    Future<int?> swiftCalls(String method) async {
      const codec = StandardMethodCodec();
      ByteData? reply;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        LiveActions.channelName,
        codec.encodeMethodCall(MethodCall(method)),
        (data) => reply = data,
      );
      return reply == null ? null : codec.decodeEnvelope(reply!) as int?;
    }

    test('«أخدته» والتطبيق في الخلفية/قدّامه → drain على الإنجن الرئيسي: الصف taken على نفس القاعدة اللي «يومك» بتسمعها', () async {
      final payload = h.sink.scheduled[notificationIdFor(dueAt)]!.payload;
      LiveActions.store = PendingActionStore(directoryOverride: tmp);
      LiveActions.door = door;
      await LiveActions.listen();

      // «يومك» مفتوحة وبتسمع قبل الدوسة
      final seen = <DoseState>[];
      final sub = h.services.events.watchDay(aug31).listen((e) => seen.addAll(e.map((x) => x.state)));
      await Future<void>.delayed(Duration.zero);

      _swiftQueues(tmp, payload: payload, id: notificationIdFor(dueAt), at: DateTime(2026, 8, 31, 20, 1));
      final applied = await swiftCalls('drain');

      expect(applied, 1);
      final events = await h.services.events.watchDay(aug31).first;
      expect(events.single.state, DoseState.taken);
      expect(h.sink.cancelled, containsAll(slotIds()), reason: 'الإعادة +٥ ما ترنّش');
      expect(tmp.listSync(), isEmpty, reason: 'الدوسة اتشالت من الطابور');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, DoseState.taken, reason: '«يومك» المفتوحة عرفت على طول');
      await sub.cancel();
    });

    test('drain قبل ما الباب يتجهّز = صفر، والدوسة فاضلة في الطابور لـmain', () async {
      final payload = h.sink.scheduled[notificationIdFor(dueAt)]!.payload;
      LiveActions.store = PendingActionStore(directoryOverride: tmp);
      _swiftQueues(tmp, payload: payload, id: notificationIdFor(dueAt), at: DateTime(2026, 8, 31, 20, 1));
      await LiveActions.listen();
      expect(await swiftCalls('drain'), 0);
      expect(tmp.listSync(), hasLength(1));
    });

    test('(مقتول) الطابور بيتطبّق عند الفتح من غير الإنجن التاني — نفس الباب', () async {
      final payload = h.sink.scheduled[repeatIdFor(dueAt, 0)]!.payload;
      _swiftQueues(tmp, payload: payload, id: repeatIdFor(dueAt, 0), at: DateTime(2026, 8, 31, 20, 6));
      expect(await drainPendingActions(PendingActionStore(directoryOverride: tmp), door), 1);
      expect((await h.services.events.watchDay(aug31).first).single.state, DoseState.taken);
    });
  });

  group('المرايا', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    test('سويفت: نفس اسم القناة، والتسليم للإنجن الرئيسي بعد الطابور وقبل الإضافة — ومن غير super', () {
      expect(swift, contains('static let name = "${LiveActions.channelName}"'));
      final didReceive = swift.indexOf('didReceive response: UNNotificationResponse');
      final enqueue = swift.indexOf('PendingActionQueue.enqueue(response)', didReceive);
      final deliver = swift.indexOf('LiveActionChannel.deliver(completionHandler)', didReceive);
      final superCall = swift.indexOf('super.userNotificationCenter(', didReceive);
      expect(deliver, greaterThan(enqueue));
      expect(deliver, lessThan(superCall));
      expect(swift.substring(deliver, superCall), contains('return'), reason: 'اتسلّمت = الإضافة ما تقوّمش إنجن تاني');
      expect(swift, contains('LiveActionChannel.register(with:'));
    });

    test('main: الباب قبل «جاهز»، وبيتبدّل للخدمات الكاملة', () {
      final door = main.indexOf('LiveActions.door = door;');
      final listen = main.indexOf('await LiveActions.listen();');
      expect(door, greaterThan(0));
      expect(listen, greaterThan(door), reason: 'سويفت ما تنادي drain غير والباب موجود');
      expect(main.indexOf('LiveActions.door = (action, payload)'), greaterThan(listen));
    });
  });
}
