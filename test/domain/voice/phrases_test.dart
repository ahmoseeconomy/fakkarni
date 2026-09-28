// الجمل المتغيّرة بحتت ممدوح المسجّلة — ومن غير صوت موبايل خالص.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/voice/briefing.dart';
import 'package:fakkarni/domain/voice/phrases.dart';

import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;

void main() {
  final evening = DateTime(2026, 9, 28, 14);
  final morning = DateTime(2026, 9, 28, 7);

  group('الملخص بالحتت', () {
    test('دوا واحد — «معادها الساعة ٥ العصر»', () {
      final p = briefingPhrase(now: evening, dosesToday: 1, nextDoseAt: DateTime(2026, 9, 28, 17))!;
      expect(p.segments, ['seg_greet_evening', 'seg_today_you_have', 'seg_count_1', 'seg_its_time', 'seg_hour_5', 'seg_part_asr']);
      expect(p.text, 'مساء الخير. النهارده عندك دوا واحد، معادها الساعة ٥ العصر.');
    });

    test('دوايين — «والدوا الجاي»', () {
      final p = briefingPhrase(now: morning, dosesToday: 2, nextDoseAt: DateTime(2026, 9, 28, 9, 30))!;
      expect(p.text, 'صباح الخير. النهارده عندك دوايين، والدوا الجاي الساعة ٩ ونص الصبح.');
    });

    test('٣ أدوية وزيارة دكتور بكرة', () {
      final p = briefingPhrase(now: morning, dosesToday: 3, nextDoseAt: DateTime(2026, 9, 28, 12, 15), visitInDays: 1)!;
      expect(p.segments, [
        'seg_greet_morning', 'seg_today_you_have', 'seg_count_3', 'seg_next_dose',
        'seg_hour_12', 'seg_min_quarter', 'seg_part_noon', 'seg_visit_tomorrow',
      ]);
      expect(p.text, 'صباح الخير. النهارده عندك ٣ أدوية، والدوا الجاي الساعة ١٢ وربع الضهر. وعندك زيارة دكتور بكرة.');
    });

    test('١١ دوا — مالهاش حتة، فالجملة كلها ما بتتقالش', () {
      expect(briefingPhrase(now: morning, dosesToday: 11, nextDoseAt: DateTime(2026, 9, 28, 9)), isNull);
    });

    test('خلصوا — «خلصت أدوية النهارده كلها»', () {
      final p = briefingPhrase(now: evening, dosesToday: 4)!;
      expect(p.text, 'مساء الخير. خلصت أدوية النهارده كلها.');
    });

    test('زيارة بعد بكرة / بعد ٥ أيام', () {
      expect(briefingPhrase(now: morning, dosesToday: 0, visitInDays: 2)!.text, 'صباح الخير. وعندك زيارة دكتور بعد بكرة.');
      expect(briefingPhrase(now: morning, dosesToday: 0, visitInDays: 5)!.text, 'صباح الخير. وعندك زيارة دكتور بعد ٥ أيام.');
      expect(briefingPhrase(now: morning, dosesToday: 0), isNull, reason: 'مفيش حاجة تتقال');
    });

    test('ولا اسم دوا ولا اسم دكتور في أي حتة', () {
      final input = BriefingInput(
        now: morning,
        dosesToday: 1,
        firstDoseAt: DateTime(2026, 9, 28, 9),
        firstDoseWording: 'بعد الأكل',
        nextDoseAt: DateTime(2026, 9, 28, 9),
      );
      expect(briefingSpoken(input)!.text, isNot(contains('بعد الأكل')));
      for (final t in segmentTexts.values) {
        expect(t, isNot(matches(RegExp('[A-Za-z]'))), reason: t);
        expect(t, isNot(contains('د.')));
      }
    });
  });

  group('الساعة بالحتت', () {
    List<String>? at(int h, int m) => timeSegments(DateTime(2026, 9, 28, h, m));
    test('٥ العصر', () => expect(at(17, 0), ['seg_hour_5', 'seg_part_asr']));
    test('٩ ونص الصبح', () => expect(at(9, 30), ['seg_hour_9', 'seg_min_half', 'seg_part_morning']));
    test('١٢ وربع الضهر', () => expect(at(12, 15), ['seg_hour_12', 'seg_min_quarter', 'seg_part_noon']));
    test('٦ إلا ربع المغرب — الساعة الجاية وجزء يومها', () => expect(at(17, 45), ['seg_hour_6', 'seg_min_less_quarter', 'seg_part_maghrib']));
    test('١٢ بالليل', () => expect(at(0, 0), ['seg_hour_12', 'seg_part_night']));
    test('٩ و٧ دقايق — مالهاش حتة', () => expect(at(9, 7), isNull));
  });

  group('التشغيل', () {
    late FakePlayer player;
    late FakeTts tts;
    setUp(() {
      SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true});
      player = FakePlayer();
      tts = FakeTts();
    });

    Future<VoiceService> service(Set<String> present) async {
      final v = VoiceService(player: player, tts: tts, assetExists: (path) async => present.contains(path));
      await v.load();
      return v;
    }

    final phrase = briefingPhrase(now: evening, dosesToday: 1, nextDoseAt: DateTime(2026, 9, 28, 17))!;

    test('كل الحتت موجودة → بتتقال ورا بعض بصوت ممدوح، ومفيش صوت موبايل', () async {
      final v = await service({for (final s in phrase.segments) segmentAssetPath(s)});
      expect(await v.speakPhrase(phrase), isTrue);
      expect(player.played, [for (final s in phrase.segments) segmentAssetPath(s)]);
      expect(tts.spoken, isEmpty);
      expect(VoiceService.phraseGap.inMilliseconds, lessThanOrEqualTo(80));
    });

    test('حتة واحدة ناقصة → الجملة كلها ساكتة (ولا نصها)', () async {
      final v = await service({for (final s in phrase.segments.skip(1)) segmentAssetPath(s)});
      expect(await v.speakPhrase(phrase), isFalse);
      expect(player.played, isEmpty);
      expect(tts.spoken, isEmpty, reason: 'مفيش صوت موبايل بداله');
    });

    test('الصوت مقفول → ولا حاجة', () async {
      SharedPreferences.setMockInitialValues({});
      final v = await service({for (final s in phrase.segments) segmentAssetPath(s)});
      expect(await v.speakPhrase(phrase), isFalse);
      expect(player.played, isEmpty);
    });
  });

  test('كل حتة الكود ممكن يطلبها: ملفها موجود أو مكتوبة في segments_to_record.md — والجدول ما فيهوش حتت قديمة', () {
    final referenced = <String>{};
    void add(SpokenPhrase? p) => referenced.addAll(p?.segments ?? const []);
    for (var n = 0; n <= 12; n++) {
      for (var h = 0; h < 24; h++) {
        for (final m in [0, 15, 30, 45]) {
          final t = DateTime(2026, 9, 28, h, m);
          add(briefingPhrase(now: t, dosesToday: n, nextDoseAt: t));
          add(nextDosePhrase(t));
        }
      }
      add(todayCountPhrase(n));
      for (var d = 1; d <= 12; d++) {
        add(briefingPhrase(now: morning, dosesToday: n, visitInDays: d));
        add(briefingPhrase(now: evening, dosesToday: n, visitInDays: d));
      }
    }
    final doc = File('docs/voice/segments_to_record.md').readAsStringSync();
    final listed = {for (final m in RegExp(r'^\| `(seg_[a-z_0-9]+)` \| (.+?) \|', multiLine: true).allMatches(doc)) m.group(1)!: m.group(2)!};
    final dir = Directory('assets/voices/segments');
    final present = {
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.mp3')) f.uri.pathSegments.last.replaceAll('.mp3', ''),
    };
    for (final id in referenced) {
      expect(present.contains(id) || listed.containsKey(id), isTrue, reason: '$id مش مسجّلة ولا مكتوبة في الجدول');
      if (listed.containsKey(id)) expect(listed[id], segmentTexts[id], reason: 'نص $id في الجدول غير الكود');
    }
    for (final id in listed.keys) {
      expect(segmentTexts.containsKey(id), isTrue, reason: '$id في الجدول ومش في الكتالوج');
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/voices/segments/'));
  });

  test('مفيش صوت موبايل في الكلام اللي بيتقال للمريض — `speak(` في ملف الـTTS بس', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.endsWith('device_tts.dart'))
          if (RegExp(r'\btts\.speak\(|speakText\(').hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(offenders, isEmpty);
  });
}
