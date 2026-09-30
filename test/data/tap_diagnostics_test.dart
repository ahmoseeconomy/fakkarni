// تشخيص «أخدته» اللي بتضيع (٣٠ سبتمبر ٢٠٢٦، Option B — تسجيل بس):
// كل سكّة ساكتة بقى ليها سطر — قراية الطابور، الملف اللي اتشال وليه،
// الخروج الهادي في المعالج، والمحرّك التاني. **ومفيش اسم دوا في أي سطر.**
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/notifications/notification_service.dart' show NotificationActions;
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/services/notification_actions.dart';
import 'package:fakkarni/data/services/pending_actions.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';

import '../features/scan/scan_test_support.dart';

void main() {
  final lines = <String>[];
  setUp(() {
    lines.clear();
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
  });
  tearDown(() => debugPrint = debugPrintThrottled);

  List<String> withPrefix(String p) => [for (final l in lines) if (l.contains(p)) l];

  group('الطابور', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('fk_queue'));
    tearDown(() => tmp.deleteSync(recursive: true));

    File write(String name, String content) => File('${tmp.path}/$name')..writeAsStringSync(content);
    String record({String action = 'taken', Object? at}) => jsonEncode({
          'v': 1,
          'action': action,
          'id': 7,
          'at': at ?? DateTime(2026, 9, 30, 13, 53).millisecondsSinceEpoch,
          'payload': '{"v":1}',
        });

    test('كل قراية: المجلد وكام ملف وكام اتقرا', () {
      write('a.json', record());
      write('b.json', record());
      write('ignore.txt', 'x');
      final list = PendingActionStore(directoryOverride: tmp).list();
      expect(list, hasLength(2));
      final l = withPrefix('Pending: الطابور').single;
      expect(l, contains('مجلد=${tmp.path}'));
      expect(l, contains('ملفات=2'));
      expect(l, contains('اتقرا=2'));
    });

    test('المجلد فاضي = سطر بصفر (قبل كده ولا سطر)', () {
      PendingActionStore(directoryOverride: tmp).list();
      expect(withPrefix('Pending: الطابور').single, contains('ملفات=0 — اتقرا=0'));
    });

    test('المجلد مش موجود = سطر بالمسار', () {
      final missing = Directory('${tmp.path}/nope');
      PendingActionStore(directoryOverride: missing).list();
      expect(withPrefix('Pending: الطابور').single, contains('المجلد مش موجود: ${missing.path}'));
    });

    test('ملف مش JSON بيتنقل لـbad/ (مش بيتمسح) — والسطر بيقول ليه واسمه، من غير محتواه', () {
      write('bad.json', '{secret not json');
      final list = PendingActionStore(directoryOverride: tmp).list();
      expect(list, isEmpty);
      expect(File('${tmp.path}/bad.json').existsSync(), isFalse);
      expect(File('${tmp.path}/$badPendingFolder/bad.json').existsSync(), isTrue, reason: 'مفيش دوسة بتتمسح');
      final l = withPrefix('Pending: ملف بايظ').single;
      expect(l, contains('bad.json'));
      expect(l, contains('مش JSON'));
      expect(l, isNot(contains('secret')));
      expect(withPrefix('Pending: الطابور').single, contains('ملفات=1 — اتقرا=0'));
    });

    test('مفاتيح ناقصة أو نوعها غلط بتتقال', () {
      write('noat.json', jsonEncode({'action': 'taken'}));
      write('strat.json', jsonEncode({'action': 'taken', 'at': '123'}));
      PendingActionStore(directoryOverride: tmp).list();
      final removed = withPrefix('Pending: ملف بايظ');
      expect(removed, hasLength(2));
      expect(removed.every((l) => l.contains('مفاتيح ناقصة أو نوعها غلط')), isTrue);
      expect(removed.any((l) => l.contains('at=String')), isTrue);
    });

    test('ملف ما بيتقراش = «القراية وقعت» بنوع العطل', () {
      final f = write('locked.json', record());
      Process.runSync('chmod', ['000', f.path]);
      addTearDown(() => Process.runSync('chmod', ['644', f.path]));
      final parsed = PendingAction.parseWithReason(f);
      expect(parsed.action, isNull);
      expect(parsed.reason, contains('القراية وقعت'));
    }, skip: Platform.isWindows);

    test('parse زي ما كانت: نفس النتيجة للملف السليم', () {
      final f = write('ok.json', record());
      final a = PendingAction.parse(f)!;
      expect(a.action, 'taken');
      expect(a.id, 7);
      expect(a.name, 'ok.json');
    });

    test('الصحوة لما بتشيل دوستها — سطر باسم الملف', () {
      write('mine.json', record());
      PendingActionStore(directoryOverride: tmp).removeMatching(action: 'taken', payload: '{"v":1}');
      expect(withPrefix('Pending: ملف اتشال (الصحوة').single, contains('mine.json'));
    });

    test('اتطبّق بيقول اسم الملف اللي اتشال', () async {
      write('done.json', record());
      final n = await drainPendingActions(PendingActionStore(directoryOverride: tmp), (_, _) async => ActionOutcome.recorded);
      expect(n, 1);
      expect(withPrefix('Pending: اتطبّق').single, contains('done.json اتشال'));
    });

    test('Live: الباب مش جاهز = سطر، والملف فاضل', () async {
      write('wait.json', record());
      final door = LiveActions.door;
      final store = LiveActions.store;
      LiveActions.door = null;
      LiveActions.store = PendingActionStore(directoryOverride: tmp);
      addTearDown(() {
        LiveActions.door = door;
        LiveActions.store = store;
      });
      expect(await LiveActions.drain(), 0);
      expect(withPrefix('Live: drain — الباب لسه مش جاهز'), hasLength(1));
      expect(File('${tmp.path}/wait.json').existsSync(), isTrue);
    });
  });

  group('المعالج — كل خروج هادي ليه سطر، ومفيش اسم دوا', () {
    final h = Harness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    final day = DateTime(2026, 9, 30);
    const medName = 'Concor 5mg';

    Future<(NotificationActionHandler, String)> seed() async {
      await h.meds.addMedication(
        patientId: h.services.patientId,
        name: medName,
        timing: FixedTiming(MinuteOfDay.hm(13, 53)),
        startDate: DateTime(2026, 9, 1),
      );
      final schedule = (await h.meds.activeSchedules(h.services.patientId)).single;
      final handler = NotificationActionHandler(
        medications: h.meds,
        events: DoseEventRepository(h.db),
        scheduler: h.services.scheduler,
        patientId: h.services.patientId,
      );
      return (handler, schedule.id);
    }

    void noMedName() => expect(lines.where((l) => l.contains('Concor')), isEmpty, reason: 'ولا اسم دوا في السجل');

    test('زرار مش معروف', () async {
      final (handler, _) = await seed();
      expect(await handler.handle('open', encodePayloadFor(day, ['1']), now: DateTime(2026, 9, 30, 13, 54)),
          ActionOutcome.unknownAction);
      expect(withPrefix('Handle: خروج — الزرار مش معروف').single, contains('action=open'));
      noMedName();
    });

    test('payload ما اتفكّش — بطوله، مش بمحتواه', () async {
      final (handler, _) = await seed();
      expect(await handler.handle(NotificationActions.taken, '{"v":9,"x":"hidden"}', now: DateTime(2026, 9, 30, 13, 54)),
          ActionOutcome.badPayload);
      final l = withPrefix('Handle: خروج — الـpayload ما اتفكّش').single;
      expect(l, contains('طوله 20'));
      expect(l, isNot(contains('hidden')));
    });

    test('مفيش جرعة شغّالة للإشعار ده — اليوم والجداول، من غير اسم', () async {
      final (handler, _) = await seed();
      expect(await handler.handle(NotificationActions.taken, encodePayloadFor(day, ['999']), now: DateTime(2026, 9, 30, 13, 54)),
          ActionOutcome.noActiveDose);
      final l = withPrefix('Handle: خروج — مفيش جرعة شغّالة').single;
      expect(l, contains('يوم=2026-09-30'));
      expect(l, contains('جداول=999'));
      expect(l, contains('جرعات اليوم=1'));
      noMedName();
    });

    test('اتكتب taken — والسطر من غير اسم الدوا', () async {
      final (handler, scheduleId) = await seed();
      expect(
          await handler.handle(NotificationActions.taken, encodePayloadFor(day, [scheduleId]),
              now: DateTime(2026, 9, 30, 13, 54)),
          ActionOutcome.recorded);
      final l = withPrefix('Handle: اتكتب taken').single;
      expect(l, contains('1 جرعة'));
      expect(l, contains('جداول=$scheduleId'));
      noMedName();
    });

    test('اتأجّل — سطر', () async {
      final (handler, scheduleId) = await seed();
      expect(
          await handler.handle(NotificationActions.snooze, encodePayloadFor(day, [scheduleId]),
              now: DateTime(2026, 9, 30, 13, 54)),
          ActionOutcome.snoozed);
      expect(withPrefix('Handle: اتأجّل'), hasLength(1));
      noMedName();
    });
  });

  group('المحرّك التاني (الإضافة)', () {
    final src = File('lib/app/bootstrap.dart').readAsStringSync();
    final entry = src.substring(src.indexOf('Future<void> onBackgroundNotificationAction('));

    test('أول سطر قبل تسجيل الإضافات — لو مات هناك، السطر ده بس اللي بيقول إنه قام', () {
      final first = entry.indexOf("diag('Isolate: المحرّك التاني شغّل المعالج بتاعنا");
      final binding = entry.indexOf('WidgetsFlutterBinding.ensureInitialized()');
      expect(first, greaterThan(0));
      expect(first, lessThan(binding));
    });

    test('بيقول عمل إيه في الطابور، وبيقول إنه خرج', () {
      expect(entry, contains("diag('Isolate: الطابور — دوستي اتشالت، واتطبّق \$others غيرها')"));
      final fin = entry.indexOf('} finally {');
      expect(entry.indexOf("diag('Isolate: خرجنا"), greaterThan(fin));
    });
  });

  test('السطور الجديدة بـdiag بس — مفيش debugPrint (بيطلع في release)', () {
    for (final path in [
      'lib/data/services/pending_actions.dart',
      'lib/data/services/notification_actions.dart',
    ]) {
      expect(File(path).readAsStringSync(), isNot(contains('debugPrint(')), reason: path);
    }
  });
}
