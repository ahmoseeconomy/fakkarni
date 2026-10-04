// «كلّمني» E1 (طلب المدير، ٤ أكتوبر ٢٠٢٦): بيجاوب من بياناته بس — ولا عن
// حاجة مش عنده، ولا تخمين، والطبي للدكتور زي ما هو.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/domain/medication/meal_relation.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/voice/command_flow.dart';
import 'package:fakkarni/features/voice/command_parser.dart';
import 'package:fakkarni/features/voice/fact_answers.dart';
import 'package:fakkarni/features/voice/voice_flags.dart';

import '../../data/voice/fake_listener.dart';
import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../scan/scan_test_support.dart' show Harness, aug31;

void main() {
  group('الفهم', () {
    final cases = <String, CommandIntent>{
      'باخد الكونكور إمتى': CommandIntent.medInfo,
      'باخد الجلوكوفاج الساعة كام': CommandIntent.medInfo,
      'مين دكاترتي': CommandIntent.myDoctors,
      'الدكاترة بتوعي مين': CommandIntent.myDoctors,
      'ملخص الأسبوع': CommandIntent.weeklySummary,
      'الأسبوع ده ماشي إزاي': CommandIntent.weeklySummary,
      'التحليل إمتى': CommandIntent.upcomingAppointments,
      'إمتى ميعاد دكتور حسام': CommandIntent.upcomingAppointments,
      // لسه زي ما هي
      'الدوا الجاي إمتى': CommandIntent.nextDose,
      'إيه أدويتي النهارده': CommandIntent.todayList,
      'احجز ميعاد الأسبوع الجاي': CommandIntent.addAppointment,
      // الطبي للدكتور — حتى مع اسم دوا
      'جرعة الكونكور كام': CommandIntent.medicalQuestion,
      'الكونكور ده لإيه وبيعمل صداع': CommandIntent.medicalQuestion,
      'ممكن أزود جرعة الكونكور': CommandIntent.medicalQuestion,
    };
    for (final e in cases.entries) {
      test('«${e.key}» → ${e.value.name}', () => expect(parseCommand(e.key).intent, e.value));
    }
    test('الفلتر والاسم بيتفهموا', () {
      final c = parseCommand('إمتى ميعاد دكتور حسام');
      expect(c.apptKind, AppointmentKind.doctor);
      expect(c.withWhom, 'د. حسام');
      expect(parseCommand('التحليل إمتى').apptKind, AppointmentKind.lab);
      expect(parseCommand('باخد الكونكور إمتى').medWords, 'الكونكور');
    });
  });

  group('الجمل', () {
    test('المواعيد بكلمة الأكل، والجرعة/الغرض من المحفوظ أو «مش متسجّل»', () {
      const m = MedFact(name: 'Concor', minutes: [21 * 60, 9 * 60], mealLabel: 'بعد الأكل');
      expect(medInfoText(m, MedInfoAspect.times), startsWith('بتاخد Concor الساعة'));
      expect(medInfoText(m, MedInfoAspect.times), endsWith('— بعد الأكل.'));
      expect(medInfoText(m, MedInfoAspect.amount), contains('مش متسجّلة'));
      expect(medInfoText(m, MedInfoAspect.purpose), contains('ده سؤال للدكتور'));
      expect(doctorsText(const []), 'مفيش دكاترة متسجّلين في ملفك لسه.');
      expect(doctorsText(const ['د. حسام', 'د. منى']), 'دكاترتك: د. حسام، د. منى.');
    });
  });

  group('من بياناته', () {
    late Harness h;
    late FakePlayer player;
    final now = DateTime(2026, 8, 31, 20, 5);
    setUp(() async {
      voiceCommandsCloud = false;
      SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true, VoiceService.cmdHintDoneKey: true});
      h = Harness();
      await h.setUp();
      player = FakePlayer();
    });
    tearDown(() => h.tearDown());

    Future<CommandFlow> flowWith(List<String?> answers, {List<String> doctors = const []}) async {
      final voice = VoiceService(player: player, tts: FakeTts(), listener: FakeListener(answers: answers), assetExists: (_) async => true);
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
        doctorsFor: () async => doctors,
      );
    }

    test('«باخد الكونكور إمتى» → ساعاته المتسجّلة وكلمة الأكل', () async {
      await h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: 'Concor',
        timings: const [FixedTiming(MinuteOfDay.hm(9)), FixedTiming(MinuteOfDay.hm(21))],
        startDate: aug31,
        mealRelation: MealRelation.after,
      );
      final f = await flowWith(['باخد الكونكور إمتى']);
      await f.start();
      expect(f.phase, CommandPhase.answering);
      expect(f.shown, startsWith('بتاخد Concor الساعة'));
      expect(f.shown, contains('بعد الأكل'));
    });

    test('دوا مش عنده → «مش لاقي دوا اسمه كده عندك» وأدويته شرايح — مفيش رد عنه', () async {
      await h.meds.addMedication(
          patientId: h.services.patientId, name: 'Concor', timing: const FixedTiming(MinuteOfDay.hm(9)), startDate: aug31);
      final f = await flowWith(['باخد الأسبرين إمتى']);
      await f.start();
      expect(f.shown, CommandFlow.unknownMedicineLine);
      expect(f.medChoices, ['Concor']);
    });

    test('«مين دكاترتي» → الأسامي اللي في ملفه وبس', () async {
      final f = await flowWith(['مين دكاترتي'], doctors: const ['د. حسام']);
      await f.start();
      expect(f.shown, 'دكاترتك: د. حسام.');
    });

    test('«ميعاد د. حسام إمتى» ومفيش ميعاد معاه → بنقول كده، مش ميعاد تاني', () async {
      await h.services.checkups.bookAppointment(
        patientId: h.services.patientId,
        kind: FollowKind.visit,
        title: 'د. منى',
        day: DateTime(2026, 9, 3),
        today: now,
      );
      final f = await flowWith(['إمتى ميعاد دكتور حسام']);
      await f.start();
      expect(f.shown, 'مفيش ميعاد جاي مع د. حسام متسجّل عندك.');
    });

    test('«التحليل إمتى» → ميعاد المعمل بس، مش زيارة الدكتور', () async {
      final checkups = h.services.checkups;
      await checkups.bookAppointment(patientId: h.services.patientId, kind: FollowKind.visit, title: 'د. منى', day: DateTime(2026, 9, 2), today: now);
      await checkups.bookAppointment(patientId: h.services.patientId, kind: FollowKind.lab, title: 'صورة دم', day: DateTime(2026, 9, 5), today: now);
      final f = await flowWith(['التحليل إمتى']);
      await f.start();
      expect(f.shown, contains('صورة دم'));
      expect(f.shown, isNot(contains('منى')));
      expect((await RecordsRepository(h.db).all(h.services.patientId)).length, 2, reason: 'سؤال، مفيش كتابة');
    });

    test('«ملخص الأسبوع» → نفس سطور كارت Phase D من القاعدة', () async {
      final id = await h.meds.addMedication(
          patientId: h.services.patientId, name: 'Concor', timing: const FixedTiming(MinuteOfDay.hm(9)), startDate: DateTime(2026, 8, 1));
      final scheduleId = int.parse((await h.meds.activeSchedules(h.services.patientId)).single.id);
      expect(id, isPositive);
      for (final (d, state) in [(30, DoseState.taken), (29, DoseState.missed)]) {
        await h.services.events.confirmDose(
            doseScheduleId: scheduleId, routineDay: DateTime(2026, 8, d), scheduledAt: DateTime(2026, 8, d, 9), state: state);
      }
      final f = await flowWith(['ملخص الأسبوع']);
      await f.start();
      expect(f.shown, contains('ملخص الأسبوع — ٢٤ أغسطس لـ٣٠ أغسطس'));
      expect(f.shown, contains('اتاخد ١ من ٢ جرعات'));
      expect(f.shown, contains('ما اتأكدتش: ١ — Concor'));
    });
  });
}
