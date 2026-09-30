// «أخدته» والتطبيق عايش كانت بتضيع (٣٠ سبتمبر ٢٠٢٦، آيفون المالك، profile):
//   queued — action=taken في pending_actions
//   Pending: الطابور — مفيش مجلد (المنصة دي مالهاش طابور)
//   Live: الإنجن الرئيسي طبّق 0 من الطابور
// سويفت كتبت الدوسة، ودارت على الإنجن الرئيسي ما لقتش المجلد (البيئة ما
// كانش فيها المسار). الإصلاح: المجلد من سويفت (مع «ready» و«drain») ومن
// مجلد المستندات — ومفيش ملف بيتشال قبل ما الجرعة تتسجّل.
//
// بيئة الاختبار نفسها هي ظرف الجهاز: مفيش FAKKARNI_DOCS، ومش iOS — فالطابور
// من غير الإصلاح بيقول «مفيش مجلد» بالظبط.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/services/notification_actions.dart' show ActionOutcome;
import 'package:fakkarni/data/services/pending_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late Directory queue;
  final applied = <String?>[];

  setUp(() {
    PendingActionStore.known = null;
    LiveActions.store = PendingActionStore();
    docs = Directory.systemTemp.createTempSync('fk_docs');
    queue = Directory('${docs.path}/$pendingActionsFolder')..createSync();
    applied.clear();
  });
  tearDown(() {
    PendingActionStore.known = null;
    LiveActions.door = null;
    docs.deleteSync(recursive: true);
  });

  /// نفس الملف اللي `PendingActionQueue.enqueue` بتكتبه.
  File swiftQueues(String name, {String action = 'taken', String payload = '{"v":1}'}) =>
      File('${queue.path}/$name.json')
        ..writeAsStringSync(jsonEncode({
          'v': 1,
          'action': action,
          'id': 7,
          'at': DateTime(2026, 9, 30, 13, 53).millisecondsSinceEpoch,
          'payload': payload,
        }));

  TapDoor door(ActionOutcome outcome) => (a, p) async {
        applied.add(p);
        return outcome;
      };

  List<String> names(Directory d) =>
      d.existsSync() ? [for (final f in d.listSync().whereType<File>()) f.uri.pathSegments.last] : const [];

  group('المجلد', () {
    test('الطريق الحي: سويفت بتسلّم الدوسة ومعاها المجلد ← بتتطبّق وتتشال (الفشل اللي على الجهاز)', () async {
      swiftQueues('a');
      LiveActions.door = door(ActionOutcome.recorded);
      final n = await LiveActions.handle(MethodCall('drain', {'folder': queue.path}));
      expect(n, 1, reason: 'الجهاز: «طبّق 0» — الدوسة ضاعت');
      expect(applied, ['{"v":1}']);
      expect(names(queue), isEmpty);
    });

    test('«ready»: سويفت بترد بالمجلد ← أي قراية بعدها بتلاقيه', () async {
      const channel = MethodChannel(LiveActions.channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'ready' ? queue.path : null,
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      expect(PendingActionStore().directory, isNull, reason: 'من غير سويفت: زي الجهاز');
      await LiveActions.listen();
      expect(PendingActionStore().directory?.path, queue.path);
    });

    test('الفتح والمحرّك التاني: المجلد من مجلد المستندات — مش من البيئة', () async {
      swiftQueues('b');
      await PendingActionStore.resolve(documents: () async => docs);
      expect(PendingActionStore().directory?.path, queue.path);
      final n = await drainPendingActions(PendingActionStore(), door(ActionOutcome.recorded));
      expect(n, 1);
      expect(names(queue), isEmpty);
    });

    test('المجلد المعروف بيكسب البيئة، وسويفت بتأكّده', () async {
      PendingActionStore.adopt(queue.path);
      expect(PendingActionStore().directory?.path, queue.path);
      await PendingActionStore.resolve(documents: () async => Directory('/elsewhere'));
      expect(PendingActionStore().directory?.path, queue.path, reason: 'resolve ما بيغيّرش المعروف');
    });

    test('مجلد المستندات وقع ← مفيش رمية، والبيئة زي ما كانت', () async {
      final got = await PendingActionStore.resolve(documents: () async => throw const FileSystemException('x'));
      expect(got, isNull);
    });
  });

  group('ولا دوسة بتتشال قبل ما الجرعة تتسجّل', () {
    setUp(() => PendingActionStore.adopt(queue.path));

    test('اتسجّلت ← اتشالت', () async {
      swiftQueues('ok');
      expect(await drainPendingActions(PendingActionStore(), door(ActionOutcome.recorded)), 1);
      expect(names(queue), isEmpty);
    });

    test('التأجيل ← اتشال', () async {
      swiftQueues('later', action: 'snooze');
      expect(
        await drainPendingActions(PendingActionStore(), door(ActionOutcome.snoozed), now: DateTime(2026, 9, 30, 13, 54)),
        1,
      );
      expect(names(queue), isEmpty);
    });

    for (final outcome in [ActionOutcome.noActiveDose, ActionOutcome.badPayload, ActionOutcome.unknownAction]) {
      test('خروج هادي (${outcome.name}) ← اتنقل لـbad/ — مش اتمسح، ومش بيتعاد', () async {
        swiftQueues('quiet');
        expect(await drainPendingActions(PendingActionStore(), door(outcome)), 0);
        expect(names(queue), isEmpty);
        expect(names(Directory('${queue.path}/$badPendingFolder')), ['quiet.json']);
        // المرة الجاية ما بتلمسهوش
        applied.clear();
        await drainPendingActions(PendingActionStore(), door(ActionOutcome.recorded));
        expect(applied, isEmpty);
      });
    }

    test('الباب رمى ← الملف فاضل، والمرة الجاية بيتسجّل', () async {
      swiftQueues('retry');
      final n = await drainPendingActions(PendingActionStore(), (a, p) async => throw StateError('قاعدة مقفولة'));
      expect(n, 0);
      expect(names(queue), ['retry.json']);
      expect(await drainPendingActions(PendingActionStore(), door(ActionOutcome.recorded)), 1);
      expect(names(queue), isEmpty);
    });

    test('ملف ما بيتقراش لحظياً ← فاضل (كان بيتمسح)، ولما يتقرا بيتسجّل', () async {
      final f = swiftQueues('locked');
      Process.runSync('chmod', ['000', f.path]);
      expect(await drainPendingActions(PendingActionStore(), door(ActionOutcome.recorded)), 0);
      expect(names(queue), ['locked.json']);
      Process.runSync('chmod', ['644', f.path]);
      expect(await drainPendingActions(PendingActionStore(), door(ActionOutcome.recorded)), 1);
      expect(names(queue), isEmpty);
    }, skip: Platform.isWindows);

    test('ملف بايظ ← اتنقل لـbad/ مش اتمسح', () async {
      File('${queue.path}/junk.json').writeAsStringSync('{not json');
      await drainPendingActions(PendingActionStore(), door(ActionOutcome.recorded));
      expect(names(queue), isEmpty);
      expect(names(Directory('${queue.path}/$badPendingFolder')), ['junk.json']);
    });

    test('المحرّك التاني: دوسته ما اتسجّلتش ← ملفها فاضل وبيتطبّق بالباب', () async {
      swiftQueues('mine', payload: 'P');
      final n = await PendingActionStore().drainOthers(
        action: 'taken',
        payload: 'P',
        mine: ActionOutcome.noActiveDose,
        door: door(ActionOutcome.recorded),
      );
      expect(n, 1, reason: 'اتطبّق بالباب بدل ما يتشال');
      expect(applied, ['P']);
    });

    test('المحرّك التاني: دوسته اتسجّلت ← ملفها بس اتشال، والباقي اتطبّق', () async {
      swiftQueues('mine', payload: 'P');
      swiftQueues('other', payload: 'Q');
      final n = await PendingActionStore().drainOthers(
        action: 'taken',
        payload: 'P',
        mine: ActionOutcome.recorded,
        door: door(ActionOutcome.recorded),
      );
      expect(n, 1);
      expect(applied, ['Q']);
      expect(names(queue), isEmpty);
    });
  });

  test('سويفت: «ready» بيرد بالمجلد، و«drain» بيبعته', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('result(PendingActionQueue.directory?.path)'));
    expect(swift, contains('ch.invokeMethod("drain", arguments: args)'));
    expect(swift, contains('["folder": \$0.path]'));
  });

  test('الفتح والمحرّك التاني بيعرفوا المجلد قبل ما يقروا الطابور', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.indexOf('await PendingActionStore.resolve();'), lessThan(main.indexOf('await drainPendingActions(PendingActionStore(), door);')));
    final boot = File('lib/app/bootstrap.dart').readAsStringSync();
    final entry = boot.substring(boot.indexOf('Future<void> onBackgroundNotificationAction('));
    expect(entry.indexOf('await PendingActionStore.resolve();'), lessThan(entry.indexOf('drainOthers(')));
    expect(entry, contains('mine: mine'));
  });
}
