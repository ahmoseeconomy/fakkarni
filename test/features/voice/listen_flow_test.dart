// اسمع ← افهم ← «فهمت: …» ← «صح كده؟» ← طبّق — ومفيش تطبيق من غير «أيوه».
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/voice/answer_parser.dart';
import 'package:fakkarni/features/voice/listen_flow.dart';

import '../../data/voice/fake_listener.dart';
import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;

void main() {
  late FakePlayer player;
  late FakeTts tts;
  late FakeListener listener;
  late VoiceService voice;
  late List<SpokenTime> applied;

  Future<void> setUpWith({bool permission = true, bool prepareOk = true, List<String?> answers = const [], bool enabled = true}) async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: enabled});
    player = FakePlayer();
    tts = FakeTts();
    listener = FakeListener(permission: permission, prepareOk: prepareOk, answers: answers);
    voice = VoiceService(player: player, tts: tts, listener: listener);
    await voice.load();
    applied = [];
  }

  List<String> said() => [for (final p in player.played) p.split('/').last.replaceAll('.mp3', '')];

  ListenFlow<SpokenTime> flow({bool force = false}) => ListenFlow<SpokenTime>(
        voice: voice,
        parse: (h) => parseTime(h, hint: DayPartHint.morning),
        describe: (t) => 'الساعة ${t.hour}:${t.minute}',
        onApply: (t) async => applied.add(t),
        force: force,
      );

  test('سمع «تمانية ونص» → قال اللي فهمه → «صح كده؟» → «أيوه» بالصوت → اتطبّق', () async {
    await setUpWith(answers: ['تمانية ونص', 'أيوه']);
    final f = flow();
    await f.start();
    expect(said(), ['lis_listening', 'lis_confirm']);
    expect(tts.spoken, ['فهمت: الساعة 8:30']);
    expect(applied, [const SpokenTime(8, 30)]);
    expect(f.phase, ListenPhase.done);
    expect(listener.listens, 2);
  });

  test('من غير «أيوه» مفيش تطبيق — الزرارين فاضلين، و«أيوه» بالإيد بتطبّق', () async {
    await setUpWith(answers: ['تمانية ونص', null]);
    final f = flow();
    await f.start();
    expect(f.phase, ListenPhase.confirming);
    expect(f.heardText, 'الساعة 8:30');
    expect(applied, isEmpty, reason: 'مفيش تطبيق من غير تأكيد');
    await f.confirmYes();
    expect(applied, [const SpokenTime(8, 30)]);
    expect(f.phase, ListenPhase.done);
  });

  test('«لأ» بالصوت = اسمع تاني من الأول، وبعدين «أيوه» بتطبّق التانية', () async {
    await setUpWith(answers: ['تمانية', 'لأ', 'تسعة', 'أيوه']);
    final f = flow();
    await f.start();
    expect(applied, [const SpokenTime(9, 0)]);
    expect(said().where((s) => s == 'lis_listening'), hasLength(2));
    expect(listener.listens, 4);
  });

  test('«لأ، قول تاني» بالإيد وإحنا لسه بنسمع → سماع جديد مش تطبيق', () async {
    await setUpWith();
    listener.hold = true;
    final f = flow();
    unawaited(f.start());
    await listener.untilListening();
    listener.hear('تمانية');
    await listener.untilListening(); // سماع «أيوه» مفتوح
    expect(f.phase, ListenPhase.confirming);
    expect(f.heardText, 'الساعة 8:0');
    await f.confirmNo();
    await listener.untilListening(); // دورة جديدة
    expect(f.phase, ListenPhase.listening);
    listener.hear('عشرة');
    await listener.untilListening();
    expect(f.heardText, 'الساعة 10:0');
    expect(applied, isEmpty);
    listener.hear('أيوه');
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(applied, [const SpokenTime(10, 0)]);
    expect(f.phase, ListenPhase.done);
  });

  test('كلام مش مفهوم → «معلش، مافهمتش» — ومفيش تطبيق', () async {
    await setUpWith(answers: ['يمكن بكرة']);
    final f = flow();
    await f.start();
    expect(f.phase, ListenPhase.notUnderstood);
    expect(said(), ['lis_listening', 'lis_not_understood']);
    expect(tts.spoken, isEmpty);
    expect(applied, isEmpty);
  });

  test('سكوت (null) = مافهمتش برضه', () async {
    await setUpWith(answers: [null]);
    final f = flow();
    await f.start();
    expect(f.phase, ListenPhase.notUnderstood);
  });

  test('الإذن: «محتاج إذن الميكروفون» قبل طلب النظام، والرفض بيخفي الزرار ويقول «كمّل بإيدك»', () async {
    await setUpWith(permission: false, prepareOk: false);
    final f = flow();
    expect(f.available, isTrue);
    await f.start();
    expect(said(), ['lis_mic_permission', 'lis_mic_denied']);
    expect(listener.prepares, 1);
    expect(listener.listens, 0);
    expect(voice.micDenied, isTrue);
    expect(f.available, isFalse, reason: 'الزرار بيختفي — كل حاجة بالإيد');
  });

  test('الإذن اتوافق عليه: الجملة قبل الطلب وبعدها السماع عادي', () async {
    await setUpWith(permission: false, prepareOk: true, answers: ['تمانية', 'أيوه']);
    await flow().start();
    expect(said().first, 'lis_mic_permission');
    expect(applied, hasLength(1));
    expect(voice.micDenied, isFalse);
  });

  test('تنبيه الجرعة بيكسب: stop() وإحنا بنسمع → السماع بيتقفل والكل بيرجع idle في صمت', () async {
    await setUpWith();
    listener.hold = true;
    final f = flow();
    unawaited(f.start());
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.phase, ListenPhase.listening);
    final alert = ValueNotifier<String?>(null);
    voice.attachAlertSignal(alert);
    alert.value = '{"v":1}';
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(listener.stops, greaterThanOrEqualTo(1));
    expect(f.phase, ListenPhase.idle);
    expect(said().where((s) => s == 'lis_not_understood'), isEmpty, reason: 'إحنا اللي قطعناه — مش «مافهمتش»');
    expect(applied, isEmpty);
  });

  test('الصوت مقفول = مفيش زرار؛ المقدمة (force) بتسمع والجمل بتتقال', () async {
    await setUpWith(enabled: false, answers: ['أيوه', 'أيوه']);
    expect(flow().available, isFalse);
    final yes = <bool>[];
    final f = ListenFlow<bool>(
      voice: voice,
      parse: parseYesNo,
      describe: (v) => v ? 'أيوه' : 'لأ',
      onApply: (v) async => yes.add(v),
      force: true,
    );
    expect(f.available, isTrue);
    await f.start();
    expect(yes, [true]);
    expect(said(), ['lis_listening', 'lis_confirm']);
  });

  test('من غير مايك في النسخة = مفيش زرار ومفيش سماع', () async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true});
    final v = VoiceService(player: FakePlayer(), tts: FakeTts());
    await v.load();
    final f = ListenFlow<bool>(voice: v, parse: parseYesNo, describe: (v) => '', onApply: (_) async {});
    expect(f.available, isFalse);
    await f.start();
    expect(f.phase, ListenPhase.idle);
  });
}
