// «ساعدني» واحد بس على «يومك» — جنب العنوان، وبيشرح الشاشة كلها بالترتيب.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/elder/elder_home_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../scan/scan_test_support.dart';

void main() {
  late Harness h;
  late FakePlayer player;
  final now = DateTime(2026, 8, 31, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true, VoiceService.cmdHintDoneKey: true});
    h = Harness();
    await h.setUp();
    player = FakePlayer();
    final voice = VoiceService(player: player, tts: FakeTts());
    await voice.load();
    final s = h.services;
    h.services = AppServices(
      db: s.db, patients: s.patients, medications: s.medications, events: s.events,
      scheduler: s.scheduler, patientId: s.patientId, voice: voice,
    );
  });
  tearDown(() => h.tearDown());

  Finder helpButtons() => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('help-'));

  screenTest('زرار واحد بس — جنب «يومك» — حتى والأقسام اللي كان ليها زراير ظاهرة', (tester) async {
    await h.meds.addMedication(patientId: h.services.patientId, name: 'Concor', timing: FixedTiming(MinuteOfDay.hm(9)), startDate: DateTime(2026, 8, 31));
    await h.services.scheduler.rescheduleAll(now: now);
    await h.pump(tester, TodayScreen(now: now));

    expect(find.text('جدول النهاردة'), findsOneWidget);
    expect(find.text('معلومة تهمك'), findsOneWidget, reason: 'قسم كان ليه «ساعدني» لوحده');
    expect(helpButtons(), findsOneWidget);
    expect(find.byKey(const ValueKey('help-help_today')), findsOneWidget);
    // جنب العنوان
    final help = tester.getCenter(find.byKey(const ValueKey('help-help_today')));
    final title = tester.getCenter(find.text('يومك'));
    expect((help.dy - title.dy).abs(), lessThan(30));

    await tester.tap(find.byKey(const ValueKey('help-help_today')));
    await settle(tester);
    expect([for (final p in player.played) p.split('/').last.replaceAll('.mp3', '')],
        ['help_today', 'help_next_dose', 'help_appointments', 'help_progress', 'help_tip'],
        reason: 'الشاشة بالترتيب: الأدوية ← المواعيد ← الباقي');
  });

  screenTest('نمط كبار السن ما اتلمسش — زراير أقسامه زي ما هي', (tester) async {
    await h.pump(tester, ElderHomeScreen(now: now));
    expect(find.byKey(const ValueKey('help-help_today')), findsOneWidget);
  });
}
