// المقدمة الصوتية أول شاشة في تنزيلة جديدة — قبل «مين ماسك التليفون ده؟» —
// فلو قال «أيوه، اتكلّم» تلاقي onb_entry بتتقال من أول شاشة.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/root.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/features/entry/entry_screen.dart';
import 'package:fakkarni/features/voice/voice_intro_screen.dart';

import '../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../support/seeded_clock.dart';
import 'root_test.dart' show SilentSink, screenTest;

void main() {
  late AppDatabase db;
  late FakePlayer player;
  late VoiceService voice;
  late AppServices services;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    final patientId = await routines.ensurePatient();
    player = FakePlayer();
    voice = VoiceService(player: player, tts: FakeTts());
    await voice.load();
    services = AppServices(
      db: db,
      routines: routines,
      medications: meds,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
          routines: routines, medications: meds, events: DoseEventRepository(db), patientId: patientId, sink: SilentSink()),
      patientId: patientId,
      voice: voice,
    );
  });
  tearDown(() => db.close());

  List<String> said() => [for (final p in player.played) p.split('/').last.replaceAll('.mp3', '')];

  Future<void> pumpRoot(WidgetTester tester) async {
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        theme: F.light,
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
        home: const AppRoot(),
      ),
    ));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  screenTest('تنزيلة جديدة: المقدمة الأول، و«أيوه» بتودّي لشاشة البداية وبتقول onb_entry', (tester) async {
    await pumpRoot(tester);
    expect(find.byType(VoiceIntroScreen), findsOneWidget);
    expect(find.byType(EntryScreen), findsNothing);
    expect(said(), ['intro_01', 'intro_02', 'intro_03', 'intro_04', 'intro_05']);

    await tester.tap(find.byKey(const ValueKey('intro-yes')));
    // الحفظ والطابور كام دورة — نبض محدود أطول من أي انتقال
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(find.text('مين ماسك التليفون ده؟ تقدر تغيّر أو تضيف حد تاني في أي وقت.'), findsOneWidget);
    expect(said().skip(5).toList(), ['intro_yes', 'onb_entry']);
  });

  screenTest('«تخطّي» → شاشة البداية ساكتة، والمقدمة ما بترجعش', (tester) async {
    await pumpRoot(tester);
    await tester.tap(find.byKey(const ValueKey('intro-skip')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(said().where((id) => id.startsWith('onb_')), isEmpty);
    expect(voice.introDone, isTrue);
  });
}
