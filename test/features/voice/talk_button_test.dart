// «كلّمني» على «يومك» تحت التحية، وأكبر في نمط كبار السن، وبيظهر حتى والصوت
// مقفول — ساعتها الجمل مكتوبة في الورقة بدل ما تتقال.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/db/tables.dart' show RecordKind;

import 'package:fakkarni/features/voice/command_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/features/elder/elder_home_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../../data/voice/fake_listener.dart';
import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../scan/scan_test_support.dart';

void main() {
  late Harness h;
  late FakePlayer player;

  /// زيارة قديمة عند الدكتور ده — عشان يبقى من دكاترته فعلاً.
  Future<void> seedDoctor(String name) => RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.visit,
        title: 'زيارة',
        happenedAt: DateTime(2026, 7, 1),
        doctor: name,
      );

  Future<void> setUpWith({required bool voiceOn, List<String?> answers = const [], bool mic = true}) async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: voiceOn, VoiceService.cmdHintDoneKey: true});
    h = Harness();
    await h.setUp();
    player = FakePlayer();
    final voice = VoiceService(player: player, tts: FakeTts(), listener: mic ? FakeListener(answers: answers) : null);
    await voice.load();
    final s = h.services;
    h.services = AppServices(
      db: s.db, patients: s.patients, medications: s.medications, events: s.events,
      scheduler: s.scheduler, patientId: s.patientId, voice: voice,
    );
  }

  tearDown(() => h.tearDown());

  screenTest('على «يومك»: تحت التحية، فوق كل حاجة', (tester) async {
    await setUpWith(voiceOn: true);
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    final button = find.byKey(const ValueKey('talk-button'));
    expect(button, findsOneWidget);
    expect(find.text('كلّمني'), findsOneWidget);
    expect(tester.getTopLeft(button).dy, greaterThan(tester.getTopLeft(find.text('يومك')).dy));
    expect(tester.getTopLeft(button).dy, lessThan(tester.getTopLeft(find.text('جدول النهاردة')).dy));
    expect(tester.getSize(button).height, 64);
  });

  screenTest('نمط كبار السن: أكبر (٨٠)', (tester) async {
    await setUpWith(voiceOn: true);
    await h.pump(tester, ElderHomeScreen(now: DateTime(2026, 8, 31, 8)));
    expect(tester.getSize(find.byKey(const ValueKey('talk-button'))).height, 80);
  });

  screenTest('من غير مايك في النسخة = مفيش زرار', (tester) async {
    await setUpWith(voiceOn: true, mic: false);
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    expect(find.byKey(const ValueKey('talk-button')), findsNothing);
  });

  screenTest('الصوت مقفول: الزرار موجود، والورقة بتكتب الجملة بدل ما تقولها', (tester) async {
    await setUpWith(voiceOn: false, answers: ['الجو حر النهارده']);
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    await tester.tap(find.byKey(const ValueKey('talk-button')));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('talk-understood'))).data, CommandFlow.unclearLine);
    expect(tester.widget<Text>(find.byKey(const ValueKey('talk-heard'))).data, 'إنت قلت: الجو حر النهارده');
    expect(find.byKey(const ValueKey('talk-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('talk-right')), findsNothing, reason: 'مفيش حاجة «صح» — مش فاهمين');
    expect(player.played, isEmpty, reason: 'مقفول = مكتوب مش مسموع');
    // «قول تاني» هي الدايرة نفسها — بكلمتها
    expect(find.byKey(const ValueKey('mic-orb')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('mic-orb-label'))).data, 'دوس واتكلم');
  });

  screenTest('E2 على الشاشة: «احجزلي ميعاد عند الدكتور حسن» → «الميعاد يوم إيه؟» + «دوس على الدايرة وجاوب» → «عدّل بإيدك» → الورقة فيها د. حسن', (tester) async {
    await setUpWith(voiceOn: true, answers: ['احجزلي ميعاد عند الدكتور حسن']);
    await seedDoctor('د. حسن');
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    await tester.tap(find.byKey(const ValueKey('talk-button')));
    await settle(tester);

    expect(tester.widget<Text>(find.byKey(const ValueKey('talk-question'))).data, 'الميعاد يوم إيه؟');
    expect(find.byKey(const ValueKey('talk-tap-to-answer')), findsOneWidget, reason: 'الإجابة بدوسة — مفيش سماع لوحده');
    expect(find.byKey(const ValueKey('talk-edit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('talk-edit')));
    await settle(tester);
    expect(find.text('ميعاد جديد'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'د. حسن'), findsOneWidget);
    expect(await h.db.select(h.db.records).get(), hasLength(1), reason: 'ولا حاجة اتحفظت — غير زيارته القديمة');
  });

  screenTest('«… عند الدكتور حسن يوم الأحد الساعة ٥ العصر» → الملخص الكبير و«أيوه» → الميعاد اتحجز الأحد الجاي ١٧:٠٠ من غير ورقة', (tester) async {
    await setUpWith(voiceOn: true, answers: ['احجزلي ميعاد عند الدكتور حسن يوم الأحد الساعة ٥ العصر']);
    await seedDoctor('د. حسن');
    tester.view.physicalSize = const Size(1000, 3200);
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    await tester.tap(find.byKey(const ValueKey('talk-button')));
    await settle(tester);

    expect(tester.widget<Text>(find.byKey(const ValueKey('talk-shown'))).data, 'هحجز د. حسن — يوم الأحد ٦ سبتمبر — الساعة ٥:٠٠ م');
    expect(find.byKey(const ValueKey('talk-edit')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('talk-yes')));
    await settle(tester);

    final row = (await h.db.select(h.db.records).get()).singleWhere((r) => r.doctorVisitAt != null);
    expect(row.title, 'د. حسن');
    expect(row.doctor, 'د. حسن', reason: 'الدكتور الحقيقي اتسجّل على الميعاد');
    expect(row.doctorVisitAt, DateTime(2026, 9, 6, 17), reason: 'الحد الجاي بعد الاتنين ٣١ أغسطس، الساعة ٥ العصر');
  });

  screenTest('«احجزلي عند الدكتور حسن» ومش من دكاترته → «مش لاقي …» ودوّر في القريب مني — ومفيش «صح كده»', (tester) async {
    await setUpWith(voiceOn: true, answers: ['احجزلي ميعاد عند الدكتور حسن']);
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    await tester.tap(find.byKey(const ValueKey('talk-button')));
    await settle(tester);

    expect(tester.widget<Text>(find.byKey(const ValueKey('talk-doctor-line'))).data,
        'مش لاقي د. حسن عندك — اختار من دكاترتك أو دوّر في القريب مني');
    expect(find.byKey(const ValueKey('talk-right')), findsNothing);
    expect(find.byKey(const ValueKey('talk-nearby-doctors')), findsOneWidget);
    expect(find.byKey(const ValueKey('talk-my-doctors')), findsNothing, reason: 'مفيش دكاترة في ملفه لسه');
    expect(await h.db.select(h.db.records).get(), isEmpty, reason: 'ولا دكتور اتعمل من الاسم');
  });
}
