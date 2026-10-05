// «كلّمني»: اسمع ← افهم محلي ← (السحابة) ← «صح كده؟» ← نفّذ بنفس سكّة الزرار.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fakkarni/domain/places/specialty.dart';

import 'package:fakkarni/domain/voice/nlu/nlu.dart';

import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/ai/command_reader.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/data/repositories/not_bought_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/data/repositories/visit_questions_repository.dart';
import 'package:fakkarni/data/repositories/vitals_repository.dart';
import 'package:fakkarni/data/voice/speech_listener.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/domain/voice/mic_state.dart';
import 'package:fakkarni/domain/voice/voice_catalog.dart';
import 'package:fakkarni/features/voice/command_flow.dart';
import 'package:fakkarni/features/voice/voice_flags.dart';

import '../../data/voice/fake_listener.dart';
import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../scan/scan_test_support.dart' show Harness, aug31;
import '../../support/legacy_anchor.dart';

class FakeReader implements VoiceCommandReader {
  FakeReader({this.result = const CloudReadResult()});
  CloudReadResult result;
  final transcripts = <String>[];
  DateTime? lastNow;
  @override
  Future<CloudReadResult> read(String transcript, {DateTime? now}) async {
    transcripts.add(transcript);
    lastNow = now;
    return result;
  }
}

void main() {
  late Harness h;
  late FakePlayer player;
  late FakeTts tts;
  late FakeListener listener;
  late VoiceService voice;
  late List<AddMedPrefill> opened;
  late bool saveResult;
  final now = DateTime(2026, 8, 31, 20, 5);

  setUp(() async {
    voiceCommandsCloud = true;
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true, VoiceService.cmdHintDoneKey: true});
    h = Harness();
    await h.setUp();
    player = FakePlayer();
    tts = FakeTts();
    opened = [];
    saveResult = true;
  });
  tearDown(() => h.tearDown());

  final nearby = <NearbyPlace>[];
  final nearbySpecialties = <Specialty?>[];

  Future<CommandFlow> flowWith(List<String?> answers, {FakeReader? reader, bool Function()? cloudAllowed, void Function()? onCloudUsed, Future<bool> Function(AppointmentPrefill)? onOpenAppointment, List<String> doctors = const []}) async {
    nearby.clear();
    nearbySpecialties.clear();
    listener = FakeListener(answers: answers);
    // حتت ممدوح «موجودة» — عشان الجمل المتركّبة تتقال في الاختبار
    voice = VoiceService(player: player, tts: tts, listener: listener, assetExists: (_) async => true);
    await voice.load();
    final s = h.services;
    return CommandFlow(
      voice: voice,
      services: AppServices(
        db: s.db, patients: s.patients, medications: s.medications, events: s.events,
        scheduler: s.scheduler, patientId: s.patientId, voice: voice,
      ),
      routineDay: aug31,
      reader: reader,
      cloudAllowed: cloudAllowed,
      onCloudUsed: onCloudUsed,
      clock: () => now,
      onOpenAdd: (p) async {
        opened.add(p);
        return saveResult;
      },
      onOpenAppointment: onOpenAppointment,
      doctorsFor: () async => doctors,
      onOpenNearby: (p, s) async {
        nearby.add(p);
        nearbySpecialties.add(s);
      },
    );
  }

  List<String> said() => [for (final p in player.played) p.split('/').last.replaceAll('.mp3', '')];

  Future<int> seed(String name, {DayAnchor anchor = DayAnchor.dinner, MedicationPurpose? purpose}) async {
    return h.meds.addMedicationWithDoses(
      patientId: h.services.patientId,
      name: name,
      timings: [AnchorTiming(anchor, 0)],
      startDate: aug31,
      purpose: purpose,
    );
  }

  Future<void> schedule() => h.services.scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 19, 55));

  Future<DoseState> stateOf(String name) async =>
      (await h.services.events.watchDay(aug31).first).firstWhere((d) => d.medicationName == name).state;

  group('أخدت الدوا', () {
    test('«أخدت الدوا» وجرعة واحدة مستنية → مكتوبة كبير + «صح كده؟» المسجّلة → دوسة «أيوه» → نفس سكّة الزرار', () async {
      await seed('Concor');
      await schedule();
      final at = DateTime(2026, 8, 31, 20);
      final f = await flowWith(['أخدت الدوا', 'أيوه']);
      await f.start();
      expect(f.phase, CommandPhase.confirming);
      expect(f.shown, contains('أخدت Concor'));
      expect(tts.spoken, isEmpty, reason: '«فهمت: …» بصوت الموبايل اتشالت — كانت آلية');
      expect(listener.listens, 1, reason: '«أيوه» بالإيد — مفيش سماع تاني لوحده');
      await f.confirmYes();
      expect(f.phase, CommandPhase.done);
      expect(await stateOf('Concor'), DoseState.taken);
      expect(h.sink.cancelled, containsAll([notificationIdFor(at), escalationIdFor(at, EscalationRung.first), repeatIdFor(at, 0)]),
          reason: 'القاعدة الخامسة — نفس confirmGroup');
      expect(said(), containsAllInOrder(['lis_confirm', 'help_confirm_done']));
      expect(said(), isNot(contains('lis_listening')), reason: 'ولا جملة قبل المايك');
    });

    test('من غير «أيوه» مفيش كتابة — والزرار بالإيد بيكتب', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['أخدت الدوا', null]);
      await f.start();
      expect(f.phase, CommandPhase.confirming);
      expect(await stateOf('Concor'), DoseState.pending, reason: 'لسه ما أكّدش');
      await f.confirmYes();
      expect(await stateOf('Concor'), DoseState.taken);
    });

    test('«لأ» → «تمام، مش هعمل حاجة» وولا حاجة اتغيّرت', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['أخدت الدوا', 'لأ']);
      await f.start();
      await f.confirmNo();
      expect(f.phase, CommandPhase.answering);
      expect(listener.listens, 1, reason: 'مفيش سماع بيبدأ لوحده بعد دوسة');
      expect(said().last, 'cmd_cancelled');
      expect(await stateOf('Concor'), DoseState.pending);
      expect(h.sink.cancelled, isEmpty);
    });

    test('«أخدت دوا الضغط» بيطابق بالغرض على القايمة المحلية — والسحابة ما اتسألتش', () async {
      await seed('Concor', purpose: MedicationPurpose.pressure);
      await seed('Glucophage', purpose: MedicationPurpose.sugar);
      await schedule();
      final reader = FakeReader();
      final f = await flowWith(['أخدت دوا الضغط'], reader: reader);
      await f.start();
      await f.confirmYes();
      expect(await stateOf('Concor'), DoseState.taken);
      expect(await stateOf('Glucophage'), isNot(DoseState.taken));
      expect(reader.transcripts, isEmpty, reason: 'المحلي فهم');
    });

    test('دواءين مستنيين ومحدش اتسمّى → «أنهي واحد؟» بأزرار — والاختيار بيأكّد', () async {
      await seed('Concor');
      await seed('Glucophage', anchor: DayAnchor.lunch);
      await schedule();
      final f = await flowWith(['أخدت الدوا', 'أيوه']);
      await f.start();
      expect(f.phase, CommandPhase.choosing);
      expect(f.candidates.map((c) => c.dose.medicationName), containsAll(['Concor', 'Glucophage']));
      expect(await stateOf('Concor'), DoseState.pending);
      await f.choose(f.candidates.firstWhere((c) => c.dose.medicationName == 'Glucophage'));
      expect(f.phase, CommandPhase.confirming);
      await f.confirmYes();
      expect(await stateOf('Glucophage'), DoseState.taken);
      expect(await stateOf('Concor'), isNot(DoseState.taken));
    });

    test('دوا اتسمّى ومفيش جرعة له مستنية → جملة على الشاشة ومفيش كتابة', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['أخدت دوا الفيتامين']);
      await f.start();
      expect(f.phase, CommandPhase.answering);
      expect(f.shown, contains('مفيش جرعة'));
      expect(await stateOf('Concor'), DoseState.pending);
    });
  });

  group('قراية بس', () {
    test('«إيه دوايا الجاي» → مكتوب بالاسم، ومن غير صوت موبايل — ومفيش تأكيد', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['إيه دوايا الجاي']);
      await f.start();
      expect(f.phase, CommandPhase.answering);
      expect(f.shown, 'معاد Concor كان الساعة ٨ بالليل — ولسه ما اتأكدش.', reason: '٨:٠٠ فاتت بخمس دقايق');
      expect(tts.spoken, isEmpty);
      expect(said(), isEmpty, reason: 'اللي فات معاده مالوش حتت — مكتوب وبس');
      expect(listener.listens, 1, reason: 'مفيش سماع للتأكيد');
    });

    test('«الدوا الجاي إمتى» قبل معاده → «دواك الجاي … الساعة …»، ومن غير حاجة النهارده → بكرة', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['الدوا الجاي إمتى']);
      // الساعة ٧ بالليل — قبل العشا
      final early = CommandFlow(
        voice: voice, services: f.services, routineDay: aug31, clock: () => DateTime(2026, 8, 31, 19),
        onOpenAdd: (_) async => false,
      );
      await early.start();
      expect(early.shown, 'دواك الجاي Concor الساعة ٨ بالليل.');
      expect(tts.spoken, isEmpty);
      expect(said(), ['seg_next_dose_start', 'seg_hour_8', 'seg_part_night'],
          reason: 'بصوت ممدوح بالحتت، ومن غير اسم الدوا');
    });

    test('«إيه أدويتي النهارده» → قايمة بحد أقصى خمسة و«حاجات تانية على الشاشة»', () async {
      for (final (i, a) in [DayAnchor.wake, DayAnchor.breakfast, DayAnchor.lunch, DayAnchor.dinner, DayAnchor.sleep].indexed) {
        await h.meds.addMedication(patientId: h.services.patientId, name: 'M$i', timing: AnchorTiming(a, 0), startDate: aug31);
        await h.meds.addMedication(patientId: h.services.patientId, name: 'X$i', timing: AnchorTiming(a, 15), startDate: aug31);
      }
      await schedule();
      final f = await flowWith(['إيه أدويتي النهارده']);
      await f.start();
      expect(f.shown, contains('النهارده عندك ١٠ جرعات'));
      expect(f.shown, contains('وحاجات تانية على الشاشة'));
      expect('M0 M1 M2 M3 M4 X0 X1 X2 X3 X4'.split(' ').where((n) => f.shown.contains(n)).length, 5);
      expect(tts.spoken, isEmpty);
      expect(said(), ['seg_today_you_have', 'seg_count_10'], reason: 'العدد بس بيتقال — الأسامي مكتوبة');
    });

    test('سؤال طبي → «دي حاجة لازم تسأل فيها الدكتور» وبس', () async {
      final f = await flowWith(['أزود الجرعة؟']);
      await f.start();
      expect(said().last, 'gen_no_medical');
      expect(tts.spoken, isEmpty);
    });
  });

  group('ضيفلي دوا', () {
    test('E2: «ضيفلي دوا الضغط الساعة ٨ الصبح بعد الفطار» → «اسم الدوا إيه؟» → دوسة وإجابة → الملخص + «صح كده؟» → **ولا صف قبل «أيوه»** → بعدها اتحفظ', () async {
      final f = await flowWith(['ضيفلي دوا الضغط الساعة ٨ الصبح بعد الفطار', 'كونكور', 'عدّي']);
      await f.start();
      expect(f.phase, CommandPhase.asking);
      expect(f.shown, 'اسم الدوا إيه؟', reason: '«الضغط» غرض مش اسم');
      expect(tts.spoken, isEmpty, reason: 'مفيش صوت موبايل');
      expect(listener.listens, 1, reason: 'مفيش سماع لوحده — الإجابة بدوسة (١أ)');
      await f.tapMic();
      // الغرض جه من «دوا الضغط» فما بيتسألش — النوع بيتسأل و«عدّي» بتعدّيه
      expect(f.shown, 'نوعه إيه؟');
      await f.tapMic();
      expect(f.phase, CommandPhase.confirming);
      expect(f.shown, 'هضيف كونكور — للضغط — الساعة ٨:٠٠ ص — بعد الأكل');
      expect(said().last, 'lis_confirm');
      expect(await h.meds.currentMedicines(h.services.patientId), isEmpty, reason: 'ولا صف قبل «أيوه»');
      await f.confirmYes();
      final saved = await h.meds.activeSchedules(h.services.patientId);
      expect(saved.single.medicationName, 'كونكور');
      expect(saved.single.timing, const FixedTiming(MinuteOfDay(8 * 60)));
      expect(saved.single.mealRelation, MealRelation.after);
      expect((await h.db.select(h.db.medications).get()).single.purpose, 'pressure');
      expect(opened, isEmpty, reason: 'اتحفظ من غير فورم');
      expect(said().last, 'cmd_done');
    });

    test('«عدّل بإيدك» وهو بيتسأل → الفورم متعبّي باللي اتقال، ورجع من غير حفظ → مفيش «عملتها»', () async {
      saveResult = false;
      final f = await flowWith(['ضيفلي دوا اسمه زنك مرتين في اليوم']);
      await f.start();
      expect(f.shown, 'الجرعة رقم ١ الساعة كام؟', reason: 'مرتين من غير ساعات = سؤال لكل جرعة');
      await f.editInForm();
      expect(opened.single.name, 'زنك');
      expect(opened.single.timings, isEmpty, reason: 'ولا ساعة مننا');
      expect(opened.single.emptyDoses, 2, reason: 'صفين فاضيين يختار ساعاتهم');
      expect(said().where((s) => s == 'cmd_done'), isEmpty);
    });
  });

  group('الفهم الجديد (NLU) — ٢٧ سبتمبر ٢٠٢٦', () {
    for (final (said, place) in [
      ('عايز أقرب صيدلية', NearbyPlace.pharmacy),
      ('أقرب دكتور', NearbyPlace.doctor),
      ('أقرب مستشفى', NearbyPlace.hospital),
      ('أقرب معمل تحاليل', NearbyPlace.lab),
    ]) {
      test('«$said» → «القريب مني» على طول، من غير تأكيد', () async {
        final f = await flowWith([said]);
        await f.start();
        expect(nearby, [place]);
        expect(f.phase, CommandPhase.done);
        expect(tts.spoken, isEmpty);
      });
    }

    test('«عايزك تضيف لي دواء اسمه كونكور وآخده كل ١٢ ساعة» → «أول جرعة الساعة كام؟» → الفاصل بيكمّل', () async {
      final f = await flowWith(['عايزك تضيف لي دواء اسمه كونكور وآخده كل ١٢ ساعة', '٨ الصبح', 'قرص', 'للضغط']);
      await f.start();
      expect(f.shown, 'أول جرعة الساعة كام؟');
      await f.tapMic();
      // وبعد الساعات: النوع والغرض — اختياريين، وهنا بيجاوبهم فعلاً
      expect(f.shown, 'نوعه إيه؟');
      await f.tapMic();
      expect(f.shown, 'الدوا ده لإيه؟');
      await f.tapMic();
      expect(f.shown, 'هضيف كونكور — قرص — للضغط — الساعة ٨:٠٠ ص و٨:٠٠ م');
      await f.confirmYes();
      expect((await h.meds.activeSchedules(h.services.patientId)).map((s) => s.timing),
          containsAll([const FixedTiming(MinuteOfDay(8 * 60)), const FixedTiming(MinuteOfDay(20 * 60))]));
      final med = (await h.db.select(h.db.medications).get()).single;
      expect(med.form, 'tablet');
      expect(med.purpose, 'pressure');
    });

    // «بطنه» = باطنة (طلب المالك، ٢٩ سبتمبر ٢٠٢٦) — تخصص في خانته، مش دكتور اسمه «بطنه»
    test('«احجز دكتور بطنه بكرة الساعة ٥ العصر» → كله اتقال → الملخص → «أيوه» → الميعاد اتحجز بنفس دالة الزرار', () async {
      final f = await flowWith(['احجز دكتور بطنه بكرة الساعة ٥ العصر']);
      await f.start();
      expect(f.phase, CommandPhase.confirming);
      expect(f.shown, 'هحجز دكتور باطنة — بكرة — الساعة ٥:٠٠ م');
      expect(await RecordsRepository(h.services.db).all(h.services.patientId), isEmpty, reason: 'ولا صف قبل «أيوه»');
      await f.confirmYes();
      final rows = await RecordsRepository(h.services.db).all(h.services.patientId);
      expect(rows.single.title, 'دكتور باطنة');
      expect(rows.single.doctor, isNull, reason: 'مفيش دكتور مخترع');
      expect(rows.single.doctorVisitAt, DateTime(2026, 9, 1, 17));
    });

    test('«احجزلي ميعاد عند الدكتور حسن يوم الأحد الساعة ٥ العصر» → د. حسن من ملفه، الأحد الجاي، ٥ م → «أيوه» → اتحجز', () async {
      final f = await flowWith(['احجزلي ميعاد عند الدكتور حسن يوم الأحد الساعة ٥ العصر'], doctors: ['د. حسن']);
      await f.start();
      expect(f.shown, 'هحجز د. حسن — يوم الأحد ٦ سبتمبر — الساعة ٥:٠٠ م');
      await f.confirmYes();
      final row = (await RecordsRepository(h.services.db).all(h.services.patientId)).single;
      expect(row.doctor, 'د. حسن');
      expect(row.doctorVisitAt, DateTime(2026, 9, 6, 17));
    });

    test('مش مفهوم → «مش متأكد…» مكتوبة، و«عيد كلامك» بتسمع تاني — مش طريق مسدود', () async {
      final f = await flowWith(['الجو حر', 'أقرب صيدلية']);
      await f.start();
      expect(f.phase, CommandPhase.reviewing);
      expect(f.shown, CommandFlow.unclearLine);
      expect(f.canConfirmReview, isFalse);
      await f.retry();
      expect(nearby, [NearbyPlace.pharmacy]);
    });

    test('تعادل بين نيتين → «قصدك إيه؟» بزرار لكل واحدة، والدوسة بتكمّل بنفس الجملة', () async {
      final f = await flowWith(['ضيف دوا كونكور واحجز ميعاد دكتور']);
      await f.start();
      expect(f.phase, CommandPhase.clarifying);
      expect(f.clarifyOptions.map((o) => o.label), containsAll(['أضيف دوا', 'أحجز ميعاد دكتور']));
      await f.clarify(NluIntent.addMedication);
      expect(f.phase, CommandPhase.asking);
      expect(f.shown, 'بتاخده كام مرة في اليوم، والساعة كام؟');
    });

    test('«ضيف دوا كونكور» من غير ساعة → بيسأل، مش ٩ الصبح', () async {
      final f = await flowWith(['ضيف دوا كونكور']);
      await f.start();
      expect(f.shown, 'بتاخده كام مرة في اليوم، والساعة كام؟');
      expect(await h.meds.currentMedicines(h.services.patientId), isEmpty);
    });

    test('«لا» لوحدها عمرها ما تبقى اسم دوا — بيسأل عن الاسم', () async {
      final f = await flowWith(['ضيف دوا لا']);
      await f.start();
      expect(f.shown, 'اسم الدوا إيه؟');
    });

    test('«أخدت الدوا» و«ضغطي ١٢٠ على ٨٠» لسه بالقارئ القديم', () async {
      final f = await flowWith(['ضغطي ١٢٠ على ٨٠']);
      await f.start();
      expect(f.phase, CommandPhase.confirming, reason: 'القياس كارت «صح كده؟» زي ما كان');
    });
  });

  group('مش مفهوم والسحابة', () {
    test('مش مفهوم ومفيش سحابة → «مافهمتش»، والتانية ورا بعض «كمّل بإيدك»', () async {
      final f = await flowWith(['الجو حر', 'الجو حر']);
      await f.start();
      expect(said().last, 'lis_not_understood');
      await f.again();
      expect(said().last, 'gen_try_hands');
    });

    test('مش مفهوم محلي → «ثانية واحدة» → السحابة بتاخد الكلام المكتوب بس → وبعدها زي المحلي', () async {
      await seed('Concor');
      await schedule();
      final reader = FakeReader(result: const CloudReadResult(tool: CloudTool(tool: 'mark_taken')));
      var used = 0;
      final f = await flowWith(['عملت اللي المفروض'], reader: reader, onCloudUsed: () => used++);
      await f.start();
      await f.confirmYes();
      expect(reader.transcripts, ['عملت اللي المفروض'], reason: 'المحلي ما فهمش — والكلام المكتوب بس هو اللي راح');
      expect(reader.lastNow, now, reason: 'وتاريخ النهارده معاه');
      expect(await stateOf('Concor'), DoseState.taken);
      expect(said(), containsAllInOrder(['cmd_thinking', 'lis_confirm', 'help_confirm_done']));
      expect(used, 1);
    });

    test('السحابة وقعت (مهلة) → «كمّل بإيدك»', () async {
      final reader = FakeReader(result: const CloudReadResult(error: 'timeout'));
      final f = await flowWith(['كلام غريب خالص'], reader: reader);
      await f.start();
      expect(said().last, 'gen_try_hands');
    });

    test('السحابة ما فهمتش → «مافهمتش»', () async {
      final reader = FakeReader(result: const CloudReadResult(tool: null));
      final f = await flowWith(['كلام غريب خالص'], reader: reader);
      await f.start();
      expect(said().last, 'lis_not_understood');
    });

    test('الحد اليومي خلص → «كفاية كده النهارده» والسحابة ما اتسألتش', () async {
      final reader = FakeReader();
      final f = await flowWith(['كلام غريب خالص'], reader: reader, cloudAllowed: () => false);
      await f.start();
      expect(said().last, 'cmd_limit');
      expect(reader.transcripts, isEmpty);
    });

    test('العلم مقفول → السحابة ما اتسألتش حتى لو موجودة', () async {
      voiceCommandsCloud = false;
      final reader = FakeReader();
      final f = await flowWith(['كلام غريب خالص'], reader: reader);
      await f.start();
      expect(reader.transcripts, isEmpty);
      expect(said().last, 'lis_not_understood');
    });

    test('السحابة رجّعت ضيفلي بكلمات → بتتفهم محلي — ونفس الأسئلة', () async {
      final reader = FakeReader(
          result: const CloudReadResult(tool: CloudTool(tool: 'add_medication', args: {'name': 'السكر', 'times': ['15:00'], 'meal_relation': 'after_meal'})));
      final f = await flowWith(['xyz', 'جلوكوفاج', 'عدّي'], reader: reader);
      await f.start();
      expect(f.shown, 'اسم الدوا إيه؟', reason: '«السكر» غرض — السحابة كمان بتعدّي من نفس الأسئلة');
      await f.tapMic();
      expect(f.shown, 'نوعه إيه؟');
      await f.tapMic();
      expect(f.shown, 'هضيف جلوكوفاج — للسكر — الساعة ٣:٠٠ م — بعد الأكل');
      await f.confirmYes();
      expect((await h.meds.activeSchedules(h.services.patientId)).single.timing, const FixedTiming(MinuteOfDay(15 * 60)));
    });
  });

  test('أول دوسة خالص: «تقدر تقولّي مثلاً…» **مكتوبة** تحت «سامعك…» — ما بتتقالش قبل المايك', () async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true});
    final f = await flowWith(const []);
    listener.hold = true;
    final run = f.start();
    await listener.untilListening();
    expect(f.phase, CommandPhase.listening);
    expect(f.shown, 'سامعك…');
    expect(f.hint, voiceLine('cmd_hint'));
    expect(said(), isEmpty, reason: 'ولا جملة قبل المايك');
    expect(voice.cmdHintDone, isTrue);
    listener.hear(null);
    await run;
  });

  test('الكلام بيتكتب وهو بيتقال', () async {
    final f = await flowWith(const []);
    listener.hold = true;
    final run = f.start();
    await listener.untilListening();
    listener.partial('أخدت');
    expect(f.partial, 'أخدت');
    listener.hear(null);
    await run;
  });

  test('الدوسة بتكسب: «أيوه» و«صح كده؟» لسه بتتقال → اتكتبت على طول والجملة وقفت', () async {
    await seed('Concor');
    await schedule();
    final f = await flowWith(['أخدت الدوا']);
    player.holdPlayback = true;
    final run = f.start();
    for (var i = 0; i < 80 && f.phase != CommandPhase.confirming; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.phase, CommandPhase.confirming);
    expect(voice.speaking, isTrue);
    player.holdPlayback = false;
    await f.confirmYes();
    expect(await stateOf('Concor'), DoseState.taken);
    await run;
    expect(f.sessions, 1, reason: 'سماع واحد لكل دوسة');
  });

  test('الصوت مقفول: نفس الجمل مكتوبة على الشاشة، ومفيش تسجيل بيتقال', () async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: false, VoiceService.cmdHintDoneKey: true});
    final f = await flowWith(['أزود الجرعة؟']);
    expect(f.available, isTrue);
    await f.start();
    expect(f.shown, voiceLine('gen_no_medical'));
    expect(player.played, isEmpty);
    expect(tts.spoken, isEmpty);
  });

  test('تنبيه الجرعة بيكسب: stop() وإحنا بنسمع → idle في صمت', () async {
    final f = await flowWith(const []);
    listener.hold = true;
    unawaited(f.start());
    await listener.untilListening();
    expect(f.phase, CommandPhase.listening);
    final alert = ValueNotifier<String?>(null);
    voice.attachAlertSignal(alert);
    alert.value = '{"v":1}';
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(f.phase, CommandPhase.idle);
    expect(said().where((s) => s == 'lis_not_understood'), isEmpty);
  });

  group('الماكينة (MicOrb)', () {
    test('سكوت = راحة: ولا «مافهمتش»، والدايرة «دوس واتكلم»، ومفيش سماع لوحده', () async {
      final f = await flowWith([null]);
      await f.start();
      expect(f.phase, CommandPhase.idle);
      expect(f.mic, MicState.idle);
      expect(f.note, isNotNull);
      expect(said(), isEmpty);
      expect(f.failures, 0, reason: 'السكوت مش تعثّر');
      await Future<void>.delayed(Duration.zero);
      expect(listener.listens, 1);
    });

    test('«أيوه» بالصوت على «صح كده؟» ← نفس سكّة الزرار؛ مش واضح ← نسأل تاني', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['أخدت الدوا', 'يمكن', 'ايوه']);
      await f.start();
      expect(f.phase, CommandPhase.confirming);
      await f.tapMic();
      expect(f.phase, CommandPhase.confirming, reason: '«يمكن» مش أيوه');
      expect(f.shown, contains('أخدت Concor'), reason: 'اللي اتفهم رجع مكانه');
      expect(await stateOf('Concor'), DoseState.pending);
      await f.tapMic();
      expect(await stateOf('Concor'), DoseState.taken);
      expect(listener.listens, 3, reason: 'كل سماع دوسة');
    });

    test('«لأ» بالصوت ← «تمام، مش هعمل حاجة»', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['أخدت الدوا', 'لأ']);
      await f.start();
      await f.tapMic();
      expect(said().last, 'cmd_cancelled');
      expect(await stateOf('Concor'), DoseState.pending);
    });

    test('مقاطعة: الرد بيتقال ← دوسة الدايرة تسكّته وتسمع على طول', () async {
      final f = await flowWith(['أزود الجرعة؟', 'إيه أدويتي النهارده']);
      player.holdPlayback = true;
      unawaited(f.start());
      for (var i = 0; i < 50 && f.phase != CommandPhase.answering; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(f.mic, MicState.speaking);
      bool? speakingAtListen;
      listener.onListen = () => speakingAtListen = voice.speaking;
      player.holdPlayback = false;
      await f.tapMic();
      expect(speakingAtListen, isFalse);
      expect(listener.listens, 2);
    });

    test('القاطع: ٥ وقعات في ١٠ ثواني ← «كلّمني» يتقفل على الشاشة دي', () async {
      var t = DateTime(2026, 9, 26, 10);
      listener = FakeListener(answers: List.filled(6, const ListenFailed('error_listen_failed')));
      voice = VoiceService(player: player, tts: tts, listener: listener);
      await voice.load();
      final s = h.services;
      final f = CommandFlow(
        voice: voice,
        services: AppServices(db: s.db, patients: s.patients, medications: s.medications, events: s.events, scheduler: s.scheduler, patientId: s.patientId, voice: voice),
        routineDay: aug31,
        clock: () => now,
        onOpenAdd: (_) async => false,
        onStartFailure: (_) async {},
        breaker: MicBreaker(clock: () => t),
      );
      for (var i = 0; i < 4; i++) {
        await f.tapMic();
        expect(f.available, isTrue);
        t = t.add(const Duration(seconds: 1));
      }
      await f.tapMic();
      expect(f.available, isFalse);
      expect(f.mic, MicState.off);
      await f.tapMic();
      expect(listener.listens, 5);
    });
  });

  group('«كلّمني» v2 — الأدوات', () {
    Future<List<String>> questions() async =>
        [for (final q in await VisitQuestionsRepository(h.services.db).watch(h.services.patientId).first) q.body];

    test('«احجزلي ميعاد دكتور يوم الحد الساعة ٥» → «الصبح ولا بالليل؟» → «العصر» → الملخص → «أيوه»', () async {
      final f = await flowWith(['احجزلي ميعاد دكتور يوم الحد الساعة ٥', 'العصر']);
      await f.start();
      expect(f.shown, 'الساعة ٥ الصبح ولا بالليل؟', reason: '«الساعة ٥» من غير جزء اليوم ما بتتخمّنش');
      expect(tts.spoken, isEmpty);
      await f.tapMic();
      expect(f.shown, 'هحجز زيارة دكتور — يوم الأحد ٦ سبتمبر — الساعة ٥:٠٠ م');
      await f.confirmYes();
      final row = (await RecordsRepository(h.services.db).all(h.services.patientId)).single;
      expect(row.doctorVisitAt, DateTime(2026, 9, 6, 17));
    });

    test('ميعاد معمل من غير يوم → «الميعاد يوم إيه؟» → «بكرة» → الساعة → «من غير ساعة» → «أيوه»', () async {
      final f = await flowWith(['احجزلي معمل تحليل سكر', 'بكرة', 'من غير ساعة']);
      await f.start();
      expect(f.shown, 'الميعاد يوم إيه؟');
      await f.tapMic();
      expect(f.shown, 'الساعة كام؟ ولو مش عارف قول «من غير ساعة».');
      await f.tapMic();
      expect(f.shown, 'هحجز تحليل سكر — بكرة — من غير ساعة');
      await f.confirmYes();
      final row = (await RecordsRepository(h.services.db).all(h.services.patientId)).single;
      expect(CheckupService.kindOf(row), FollowKind.lab);
      expect(row.labBookingAt, isNotNull);
      expect(said().last, 'cmd_done');
    });

    test('«الساعة ٩» لوحدها → «الصبح ولا بالليل؟» — مش تخمين', () async {
      final f = await flowWith(['ضيف دوا الكونكور الساعة ٩', 'بالليل', null, 'عدّي', 'عدّي']);
      await f.start();
      expect(f.shown, 'الساعة ٩ الصبح ولا بالليل؟');
      await f.tapMic();
      expect(f.shown, 'نوعه إيه؟');
      // **السكوت ما بيعدّيش** (إصلاح ٥ أكتوبر — عطل المحاكي): دوسة بنفَس
      // تفكير بتسيب السؤال مكانه، و«عدّي» بالكلمة هي اللي بتعدّي
      await f.tapMic();
      expect(f.shown, 'نوعه إيه؟', reason: 'السكوت سايب السؤال');
      await f.tapMic();
      expect(f.shown, 'الدوا ده لإيه؟');
      await f.tapMic();
      expect(f.shown, startsWith('هضيف'));
      expect(f.shown, contains('٩:٠٠ م'));
      expect(tts.spoken, isEmpty);
    });

    test('«بعد الفطار» من غير ساعة → كلمة الأكل بتفضل، والساعات بتتسأل', () async {
      final f = await flowWith(['ضيفلي دوا الكونكور بعد الفطار', 'مرة واحدة', 'تمانية الصبح', 'عدّي', 'عدّي']);
      await f.start();
      expect(f.shown, 'بتاخده كام مرة في اليوم، والساعة كام؟');
      await f.tapMic();
      expect(f.shown, 'تاخده الساعة كام؟');
      await f.tapMic();
      await f.tapMic(); // نوعه إيه؟ → عدّي
      await f.tapMic(); // الدوا ده لإيه؟ → عدّي
      expect(f.shown, contains('بعد الأكل'));
      await f.confirmYes();
      expect((await h.meds.activeSchedules(h.services.patientId)).single.mealRelation, MealRelation.after);
    });

    test('إجابة مش مفهومة مرتين → الفورم بيتفتح متعبّي باللي اتقال', () async {
      final f = await flowWith(['ضيف دوا كونكور', 'مش عارف', 'برضه مش عارف']);
      await f.start();
      await f.tapMic();
      expect(f.phase, CommandPhase.asking);
      expect(f.note, contains('قولها تاني'));
      await f.tapMic();
      expect(opened.single.name, 'كونكور');
      expect(await h.meds.currentMedicines(h.services.patientId), isEmpty);
    });

    test('«لأ» على الملخص → ولا صف، و«عدّل بإيدك» على الملخص بيفتح الفورم', () async {
      final f = await flowWith(['ضيف دوا كونكور قرص للضغط الساعة ٩ بالليل']);
      await f.start();
      // النوع والغرض اتقالوا في الجملة — **مفيش سؤال عليهم**
      expect(f.phase, CommandPhase.confirming);
      expect(f.shown, contains('قرص'));
      expect(f.shown, contains('للضغط'));
      expect(f.canEditInForm, isTrue);
      await f.confirmNo();
      expect(await h.meds.currentMedicines(h.services.patientId), isEmpty);
      final g = await flowWith(['ضيف دوا كونكور قرص للضغط الساعة ٩ بالليل']);
      await g.start();
      await g.editInForm();
      expect(opened.single.timings, [const FixedTiming(MinuteOfDay(21 * 60))]);
    });

    test('«ضغطي ١٢٠ على ٨٠» → كارت تأكيد + «صح كده؟» المسجّلة → **ولا صف قبل «أيوه»** → بعدها اتكتب', () async {
      final f = await flowWith(['ضغطي ١٢٠ على ٨٠']);
      await f.start();
      expect(f.phase, CommandPhase.confirming);
      expect(f.shown, contains('الضغط'));
      expect(said().last, 'lis_confirm');
      expect(tts.spoken, isEmpty, reason: 'مفيش «فهمت:» بصوت الموبايل');
      expect(await VitalsRepository(h.services.db).all(h.services.patientId), isEmpty, reason: 'لسه ما قالش أيوه');
      await f.confirmYes();
      final saved = await VitalsRepository(h.services.db).all(h.services.patientId);
      expect(saved.single.value, 120);
      expect(saved.single.value2, 80);
      expect(said().last, 'cmd_done');
    });

    test('«لأ» على القياس → ولا صف', () async {
      final f = await flowWith(['وزني ٨٠ كيلو']);
      await f.start();
      await f.confirmNo();
      expect(await VitalsRepository(h.services.db).all(h.services.patientId), isEmpty);
      expect(said().last, 'cmd_cancelled');
    });

    test('«السكر ١٥٠» → «صايم ولا بعد الأكل؟» → «صايم» → تأكيد → قياس سكر', () async {
      final f = await flowWith(['السكر ١٥٠', 'صايم']);
      await f.start();
      expect(tts.spoken, isEmpty, reason: 'السؤال مكتوب — مفيش صوت موبايل');
      expect(f.phase, CommandPhase.confirming);
      await f.confirmYes();
      final readings = await ReadingsRepository(h.services.db).watchRecent(h.services.patientId).first;
      expect(readings.single.valueMgDl, 150);
    });

    test('«فكرني أسأل الدكتور عن الصداع» → تأكيد → سؤال في «أسئلة العيلة»', () async {
      final f = await flowWith(['فكرني أسأل الدكتور عن الصداع']);
      await f.start();
      expect(f.shown, contains('الصداع'));
      expect(await questions(), isEmpty);
      await f.confirmYes();
      expect(await questions(), ['الصداع']);
    });

    test('«اشتريت الكونكور» → تأكيد → العلامة بتتشال', () async {
      final id = await seed('Concor');
      await NotBoughtRepository(h.services.db).markNotBought(id);
      final f = await flowWith(['اشتريت الكونكور']);
      await f.start();
      expect(f.shown, contains('Concor'));
      expect(await NotBoughtRepository(h.services.db).all(h.services.patientId), hasLength(1));
      await f.confirmYes();
      expect(await NotBoughtRepository(h.services.db).all(h.services.patientId), isEmpty);
    });

    test('«فكرني بعدين» → تأجيل الجرعة المستنية بنفس سكّة الزرار (ربع ساعة)', () async {
      await seed('Concor');
      await schedule();
      final f = await flowWith(['فكرني بعدين']);
      await f.start();
      expect(f.shown, contains('ربع ساعة'));
      expect(h.sink.scheduled.keys.where(isSnoozeId), isEmpty);
      await f.confirmYes();
      expect(h.sink.scheduled.keys.where(isSnoozeId), hasLength(1));
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(said(), contains('help_later'), reason: 'نفس جملة زرار «لاحقًا»');
    });

    test('«مواعيدي الجاية إيه» و«الدوا فاضل كام» → رد مكتوب، ومفيش تأكيد ولا صوت موبايل', () async {
      final f = await flowWith(['مواعيدي الجاية إيه']);
      await f.start();
      expect(f.phase, CommandPhase.answering);
      expect(f.shown, contains('مفيش مواعيد'));
      final g = await flowWith(['الدوا فاضل كام']);
      await g.start();
      expect(g.phase, CommandPhase.answering);
      expect(g.shown, contains('مخزون'));
      expect(tts.spoken, isEmpty);
    });

    test('«خلصت» وهو بيسمع: اللي اتسمع هو الطلب — من غير ما نستنى السكوت', () async {
      final f = await flowWith(const []);
      listener.hold = true;
      final run = f.start();
      await listener.untilListening();
      listener.partial('إيه أدويتي النهارده');
      await f.tapMic();
      await run;
      expect(f.phase, CommandPhase.answering);
      expect(f.shown, contains('أدوية'));
    });

    test('«كلّمني» بيسمع بنافذة الطلب (٣٠ ثانية / ٢٫٥ سكوت)، والرد القصير بنافذة الرد', () async {
      final f = await flowWith(['ضغطي ١٢٠ على ٨٠', 'ايوه']);
      await f.start();
      expect(listener.lastSilence, const Duration(milliseconds: 2500));
      expect(listener.lastMaxLength, const Duration(seconds: 30));
      await f.tapMic();
      expect(listener.lastSilence, const Duration(milliseconds: 1500));
      expect(listener.lastMaxLength, const Duration(seconds: 10));
    });

    test('رد السحابة بأداة غلط الشكل = مش مفهوم، مش عطل', () async {
      final reader = FakeReader(result: const CloudReadResult(tool: CloudTool(tool: 'add_appointment', args: {'kind': 'dentist'})));
      final f = await flowWith(['xyz'], reader: reader);
      await f.start();
      expect(said().last, 'lis_not_understood');
    });
  });
}
