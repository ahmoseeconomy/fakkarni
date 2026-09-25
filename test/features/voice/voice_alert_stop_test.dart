// تنبيه الجرعة بيكسب على الشاشة كمان: فتح شاشة التذكير بيسكّت الرفيق.
// ومفيش أي استيراد للجدولة أو الإشعارات في ملفات الصوت.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/reminder/reminder_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/voice/voice_service_test.dart';
import '../scan/scan_test_support.dart';

void main() {
  late Harness h;
  setUp(() async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true});
    h = Harness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  screenTest('شاشة التذكير بتتفتح → الكلام بيقف', (tester) async {
    final player = FakePlayer();
    final tts = FakeTts();
    final voice = VoiceService(player: player, tts: tts);
    await voice.load();
    final s = h.services;
    final services = AppServices(
      db: s.db, routines: s.routines, medications: s.medications, events: s.events,
      scheduler: s.scheduler, patientId: s.patientId, voice: voice,
    );
    final id = await h.meds.addMedication(
      patientId: s.patientId,
      name: 'Concor',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: aug31,
    );
    await s.scheduler.rescheduleAll(now: aug31.add(const Duration(hours: 6)));

    // بيتكلم (تسجيل واقف مستني) …
    player.holdPlayback = true;
    unawaited(voice.speakLine('help_today'));
    await tester.pump();
    expect(voice.caption.value, isNotNull);

    // … وشاشة التذكير بتتفتح
    h.services = services;
    await h.pump(tester, ReminderScreen(routineDay: aug31, scheduleIds: ['$id']));
    expect(player.stops, greaterThanOrEqualTo(1));
    expect(tts.stops, greaterThanOrEqualTo(1));
    expect(voice.caption.value, isNull);
  });

  test('ملفات الصوت ما بتستوردش الجدولة ولا الإشعارات — الرفيق ما يقدرش يلمس التذكير', () {
    final banned = ['scheduling/', 'reminder_plan', 'reminder_scheduler', 'notification_service', 'escalation/'];
    for (final dir in ['lib/data/voice', 'lib/domain/voice']) {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        final src = f.readAsStringSync();
        for (final b in banned) {
          expect(src.contains("import '") && src.contains(b), isFalse, reason: '${f.path} بيستورد $b');
        }
      }
    }
    // وملف الجدولة ما بيعرفش الصوت
    for (final p in ['lib/data/services/reminder_scheduler.dart', 'lib/data/services/reminder_plan.dart', 'lib/core/notifications/notification_service.dart']) {
      expect(File(p).readAsStringSync().contains('voice'), isFalse, reason: '$p فيه صوت');
    }
  });
}
