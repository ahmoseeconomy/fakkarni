// «كلّمني» بيجاوب من بيانات المريض هو — على الموبايل، بقواعد، من غير ذكاء:
// الدوا الجاي، أخدته ولا لأ، أدوية النهارده، المواعيد، آخر قياس. ومن غير
// ما يعمل دكتور من اسم اتقال لوحده.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/db/tables.dart' show GlucoseContext, RecordKind;
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/places/specialty.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/voice/nlu/nlu.dart';
import 'package:fakkarni/features/voice/command_flow.dart';
import 'package:fakkarni/features/voice/command_parser.dart';
import 'package:fakkarni/features/voice/voice_flags.dart';

import '../../data/voice/fake_listener.dart';
import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../scan/scan_test_support.dart' show Harness, aug31;

void main() {
  group('القارئ — الأسئلة بالمصري', () {
    final now = DateTime(2026, 8, 31, 13);
    VoiceCommand p(String s) => parseCommand(s, now: now);

    test('«دوا الضغط الجاي امتى؟» → الدوا الجاي، للضغط', () {
      final c = p('دوا الضغط الجاي امتى؟');
      expect(c.intent, CommandIntent.nextDose);
      expect(c.medWords, 'الضغط');
    });

    test('«الدوا الجاي امتى؟» → الدوا الجاي من غير اسم', () {
      final c = p('الدوا الجاي امتى؟');
      expect(c.intent, CommandIntent.nextDose);
      expect(c.medWords, isNull);
    });

    test('«أخدت دوا الصبح؟» → سؤال عن الصبح', () {
      final c = p('أخدت دوا الصبح؟');
      expect(c.intent, CommandIntent.doseStatus);
      expect(c.dayPart, DayPart.morning);
      expect(c.medWords, isNull);
    });

    for (final said in ['أخدت الكونكور؟', 'خدت الكونكور ولا لأ', 'هو أنا أخدت الكونكور', 'يا ترى أخدت الكونكور']) {
      test('«$said» → سؤال عن الكونكور', () {
        final c = p(said);
        expect(c.intent, CommandIntent.doseStatus);
        expect(c.medWords, 'الكونكور');
      });
    }

    test('«أخدت الكونكور» من غير سؤال = خبر — بيعدّي على «صح كده؟»', () {
      expect(p('أخدت الكونكور').intent, CommandIntent.markTaken);
    });

    for (final said in ['باخد إيه النهارده؟', 'أدويتي النهارده إيه', 'هاخد إيه النهارده']) {
      test('«$said» → أدوية النهارده', () => expect(p(said).intent, CommandIntent.todayList));
    }

    for (final said in ['ميعاد الدكتور امتى؟', 'عندي مواعيد إيه؟', 'مواعيدي الجاية امتى']) {
      test('«$said» → المواعيد الجاية', () => expect(p(said).intent, CommandIntent.upcomingAppointments));
    }

    test('«آخر تحليل سكر كام؟» → آخر قياس سكر — مش سؤال طبي', () {
      final c = p('آخر تحليل سكر كام؟');
      expect(c.intent, CommandIntent.latestReading);
      expect(c.readingType, VitalType.sugar);
    });

    test('«آخر قياس ضغط كان كام» → الضغط', () {
      final c = p('آخر قياس ضغط كان كام');
      expect(c.intent, CommandIntent.latestReading);
      expect(c.readingType, VitalType.bp);
    });

    test('«آخر تحليل صورة دم» → اسم التحليل', () {
      final c = p('آخر تحليل صورة دم');
      expect(c.intent, CommandIntent.latestReading);
      expect(c.readingType, isNull);
      expect(c.labWords, 'صوره دم');
    });

    test('«ضغطي عالي؟» لسه سؤال طبي — ما بنحكمش على رقم', () {
      expect(p('ضغطي عالي؟').intent, CommandIntent.medicalQuestion);
    });
  });

  group('الردود من بياناته', () {
    late Harness h;
    late FakePlayer player;
    late VoiceService voice;
    final now = DateTime(2026, 8, 31, 13);
    final nearby = <(NearbyPlace, Specialty?)>[];
    late List<AppointmentPrefill> booked;

    setUp(() async {
      voiceCommandsCloud = false;
      SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true, VoiceService.cmdHintDoneKey: true});
      h = Harness();
      await h.setUp();
      player = FakePlayer();
      nearby.clear();
      booked = [];
    });
    tearDown(() => h.tearDown());

    Future<int> seed(String name, int hour, {MedicationPurpose? purpose}) => h.meds.addMedicationWithDoses(
          patientId: h.services.patientId,
          name: name,
          timings: [FixedTiming(MinuteOfDay.hm(hour))],
          startDate: aug31,
          purpose: purpose,
        );

    Future<CommandFlow> flowWith(List<String?> answers, {List<String> doctors = const []}) async {
      voice = VoiceService(player: player, tts: FakeTts(), listener: FakeListener(answers: answers));
      await voice.load();
      final s = h.services;
      return CommandFlow(
        voice: voice,
        services: AppServices(
          db: s.db, patients: s.patients, medications: s.medications, events: s.events,
          scheduler: s.scheduler, patientId: s.patientId, voice: voice,
        ),
        routineDay: aug31,
        clock: () => now,
        onOpenAdd: (_) async => false,
        onOpenAppointment: (p) async {
          booked.add(p);
          return false;
        },
        doctorsFor: () async => doctors,
        onOpenNearby: (p, sp) async => nearby.add((p, sp)),
      );
    }

    /// Concor ٩ الصبح (ضغط) اتاخد، Aspirin ٩ الصبح لسه، Glucophage ٩ بالليل جاي.
    Future<void> day() async {
      final concor = await seed('Concor', 9, purpose: MedicationPurpose.pressure);
      await seed('Aspirin', 9);
      await seed('Glucophage', 21);
      await h.services.scheduler.rescheduleAll(now: now);
      final schedule = (await h.meds.schedulesFor(concor)).single;
      await h.services.events.markTaken(int.parse(schedule.id), aug31);
    }

    test('«دوا الضغط الجاي امتى؟» → Concor بكرة (النهارده اتاخد) — بالغرض', () async {
      await day();
      final f = await flowWith(['دوا الضغط الجاي امتى؟']);
      await f.start();
      expect(f.phase, CommandPhase.answering);
      expect(f.shown, startsWith('Concor الجاي بكرة الساعة'));
    });

    test('«كونكور الجاي امتى» من غير كلمة «دوا» → بيتطابق على أدويته بالصوت', () async {
      await day();
      final f = await flowWith(['كونكور الجاي امتى']);
      await f.start();
      expect(f.shown, startsWith('Concor الجاي بكرة'));
    });

    test('«الدوا الجاي امتى؟» → أول جرعة لسه ما اتأكدتش', () async {
      await day();
      final f = await flowWith(['الدوا الجاي امتى؟']);
      await f.start();
      expect(f.shown, contains('Aspirin'), reason: 'Aspirin بتاع ٩ لسه ما اتأكدش — هي «الجاية» فعلاً');
    });

    test('«أخدت الكونكور؟» → أيوه والساعة', () async {
      await day();
      final before = [for (final e in await h.db.select(h.db.doseEvents).get()) '${e.id}:${e.state}'];
      final f = await flowWith(['أخدت الكونكور؟']);
      await f.start();
      expect(f.shown, startsWith('أيوه، أخدت Concor الساعة'));
      expect([for (final e in await h.db.select(h.db.doseEvents).get()) '${e.id}:${e.state}'], before, reason: 'سؤال — مفيش كتابة');
    });

    test('«أخدت الأسبرين؟» → لأ، لسه ما اتأكدش — من غير ما يسجّل حاجة', () async {
      await day();
      final f = await flowWith(['أخدت الأسبرين؟']);
      await f.start();
      expect(f.shown, startsWith('لأ، Aspirin بتاع الساعة'));
      expect(f.phase, CommandPhase.answering, reason: 'مش «صح كده؟» — ده سؤال');
    });

    test('«أخدت دوا الصبح؟» → كل جرعات الصبح بحالتها', () async {
      await day();
      final f = await flowWith(['أخدت دوا الصبح؟']);
      await f.start();
      expect(f.shown, contains('أيوه، أخدت Concor'));
      expect(f.shown, contains('لأ، Aspirin'));
      expect(f.shown, isNot(contains('Glucophage')), reason: 'دوا بالليل');
    });

    test('«أخدت الكونكور» (خبر) وهو متأكّد خلاص → حالته بدل «مفيش جرعة مستنية»', () async {
      await day();
      final f = await flowWith(['أخدت الكونكور']);
      await f.start();
      expect(f.shown, startsWith('أيوه، أخدت Concor'));
    });

    test('«باخد إيه النهارده؟» → القايمة بالساعات والحالة', () async {
      await day();
      final f = await flowWith(['باخد إيه النهارده؟']);
      await f.start();
      expect(f.shown, startsWith('النهارده عندك'));
      expect(f.shown, startsWith('النهارده عندك جرعتين: '));
      expect(f.shown, contains('Concor (أخدته)'));
      expect(f.shown, contains('Aspirin (لسه ما اتأكدش)'));
      expect(f.shown, contains('Glucophage الساعة'));
    });

    test('دوا مش عنده → «مش لاقي دوا اسمه كده عندك» + أدويته شرايح، والدوسة بتجاوب', () async {
      await day();
      final f = await flowWith(['أخدت البنادول؟']);
      await f.start();
      expect(f.shown, CommandFlow.unknownMedicineLine);
      expect(f.medChoices, ['Aspirin', 'Concor', 'Glucophage']);
      await f.pickMedicine('Glucophage');
      expect(f.shown, startsWith('Glucophage معاده الساعة'));
      expect(f.medChoices, isEmpty);
    });

    test('«عندي مواعيد إيه؟» → مواعيده الجاية من الملف', () async {
      await h.services.checkups.bookAppointment(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'د. هشام',
        day: DateTime(2026, 9, 3),
        today: now,
      );
      final f = await flowWith(['عندي مواعيد إيه؟']);
      await f.start();
      expect(f.shown, startsWith('مواعيدك الجاية'));
      expect(f.shown, contains('د. هشام'));
    });

    test('«آخر تحليل سكر كام؟» → آخر رقم متسجّل وتاريخه، ومن غير أي حكم', () async {
      final f0 = await flowWith(['آخر تحليل سكر كام؟']);
      await f0.start();
      expect(f0.shown, 'مفيش قياس سكر متسجّل عندك.');

      await ReadingsRepository(h.db).add(patientId: h.services.patientId, valueMgDl: 120, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 8, 30, 8));
      final f = await flowWith(['آخر تحليل سكر كام؟']);
      await f.start();
      expect(f.shown, startsWith('آخر قياس سكر ١٢٠ — صايم'));
      for (final judge in ['عالي', 'واطي', 'طبيعي', 'مرتفع', 'منخفض', 'دكتورك']) {
        expect(f.shown, isNot(contains(judge)), reason: judge);
      }
    });

    group('الحجز ما بيعملش دكتور', () {
      test('دكتوره الوحيد بالاسم ده → اتعبّى بيه', () async {
        final f = await flowWith(['احجزلي عند الدكتور هشام بكرة'], doctors: ['د. هشام سعيد']);
        await f.start();
        // E2: اليوم اتقال (بكرة)، والساعة بتتسأل — والاسم من ملفه
        expect(f.phase, CommandPhase.asking);
        await f.editInForm();
        expect(booked.single.doctor, 'د. هشام سعيد');
        expect(booked.single.name, 'د. هشام سعيد');
      });

      test('كذا دكتور بالاسم → «أنهي واحد؟» والاختيار بيتعبّى', () async {
        final f = await flowWith(['احجزلي عند الدكتور حسن'], doctors: ['د. حسن علي', 'د. حسن فؤاد', 'د. هشام']);
        await f.start();
        expect(f.phase, CommandPhase.pickingDoctor);
        expect(f.doctorOptions, ['د. حسن علي', 'د. حسن فؤاد']);
        await f.pickDoctor('د. حسن فؤاد');
        expect(f.phase, CommandPhase.asking, reason: 'اليوم لسه — بيتسأل');
        expect(f.shown, 'الميعاد يوم إيه؟');
        await f.editInForm();
        expect(booked.single.doctor, 'د. حسن فؤاد');
      });

      test('مفيش → «مش لاقي …» ودكاترته والقريب مني — ولا دكتور اتعمل ولا ورقة اتفتحت', () async {
        final f = await flowWith(['احجزلي ميعاد عند الدكتور حسن عيون'], doctors: ['د. هشام']);
        await f.start();
        expect(f.phase, CommandPhase.pickingDoctor);
        expect(f.shown, 'مش لاقي د. حسن عندك — اختار من دكاترتك أو دوّر في القريب مني');
        expect(f.doctorMissing, 'د. حسن');
        expect(f.canConfirmReview, isFalse, reason: 'مفيش «صح كده» على اسم مش حقيقي');
        expect(booked, isEmpty);
        expect(await RecordsRepository(h.db).all(h.services.patientId), isEmpty);

        f.showSavedDoctors();
        expect(f.doctorOptions, ['د. هشام']);
        await f.searchNearbyDoctor();
        expect(nearby.single, (NearbyPlace.doctor, Specialty.eyes));
      });

      test('دكاترته من الملف نفسه (عمود الدكتور) — الافتراضي', () async {
        await RecordsRepository(h.db).add(
          patientId: h.services.patientId, kind: RecordKind.prescription, title: 'روشتة', happenedAt: DateTime(2026, 7, 1), doctor: 'د. حسن علي');
        voice = VoiceService(player: player, tts: FakeTts(), listener: FakeListener(answers: ['احجزلي عند الدكتور حسن']));
        await voice.load();
        final s = h.services;
        final f = CommandFlow(
          voice: voice,
          services: AppServices(db: s.db, patients: s.patients, medications: s.medications, events: s.events, scheduler: s.scheduler, patientId: s.patientId, voice: voice),
          routineDay: aug31,
          clock: () => now,
          onOpenAdd: (_) async => false,
        );
        await f.start();
        expect(f.shown, 'الميعاد يوم إيه؟', reason: 'د. حسن علي اتلقى من ملفه — والسؤال الجاي اليوم');
        await f.editInForm();
      });
    });

    test('«أقرب دكتور عيون» → «القريب مني» على الدكاترة والتخصص', () async {
      final f = await flowWith(['أقرب دكتور عيون']);
      await f.start();
      expect(nearby.single, (NearbyPlace.doctor, Specialty.eyes));
    });
  });
}
