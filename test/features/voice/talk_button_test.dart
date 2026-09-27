// «كلّمني» على «يومك» تحت التحية، وأكبر في نمط كبار السن، وبيظهر حتى والصوت
// مقفول — ساعتها الجمل مكتوبة في الورقة بدل ما تتقال.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  screenTest('«احجزلي ميعاد عند الدكتور حسن» → اللي فهمناه + «إنت قلت» → «صح كده» → ورقة الميعاد فيها د. حسن', (tester) async {
    await setUpWith(voiceOn: true, answers: ['احجزلي ميعاد عند الدكتور حسن']);
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    await tester.tap(find.byKey(const ValueKey('talk-button')));
    await settle(tester);

    expect(tester.widget<Text>(find.byKey(const ValueKey('talk-understood'))).data,
        'فهمت إنك عايز تحجز عند د. حسن — اليوم: لسه هتختاره — الساعة: لسه هتختارها');
    expect(tester.widget<Text>(find.byKey(const ValueKey('talk-heard'))).data, 'إنت قلت: احجزلي ميعاد عند الدكتور حسن');
    expect(find.byKey(const ValueKey('talk-retry')), findsOneWidget);
    expect(player.played, isEmpty, reason: 'التأكيد مكتوب بس');

    await tester.tap(find.byKey(const ValueKey('talk-right')));
    await settle(tester);
    expect(find.text('ميعاد جديد'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'د. حسن'), findsOneWidget);
    expect(await h.db.select(h.db.records).get(), isEmpty, reason: 'ولا حاجة اتحفظت قبل زرار الورقة');
  });

  screenTest('«… عند الدكتور حسن يوم الأحد الساعة ٥ العصر» → الاسم «د. حسن» والساعة في خانتها ٥:٠٠ م → الحفظ بيكتب الأحد الجاي ١٧:٠٠', (tester) async {
    await setUpWith(voiceOn: true, answers: ['احجزلي ميعاد عند الدكتور حسن يوم الأحد الساعة ٥ العصر']);
    tester.view.physicalSize = const Size(1000, 3200);
    await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 8)));
    await tester.tap(find.byKey(const ValueKey('talk-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('talk-right')));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'د. حسن'), findsOneWidget, reason: 'الساعة مش في الاسم');
    expect(tester.widget<Text>(find.byKey(const ValueKey('new-appt-time-line'))).data, 'الساعة ٥:٠٠ م');
    await tester.ensureVisible(find.byKey(const ValueKey('new-appt-save')));
    await tester.tap(find.byKey(const ValueKey('new-appt-save')));
    await settle(tester);

    final row = (await h.db.select(h.db.records).get()).single;
    expect(row.title, 'د. حسن');
    expect(row.doctorVisitAt, DateTime(2026, 9, 6, 17), reason: 'الحد الجاي بعد الاتنين ٣١ أغسطس، الساعة ٥ العصر');
  });
}
