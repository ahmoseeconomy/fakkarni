// «ضيف دوا» بعد مراجعة ٥ أكتوبر ٢٠٢٦: «لإيه؟» و«نوعه؟» بكرة مش شرايح
// (أول صف «من غير تحديد» بيكتب null)، «قولها بصوتك» بيملا الفورم كله بفهم
// «كلّمني» والناقص بيفضل فاضي، ومايك لكل حقل بيملاه هو وبس — ولا حاجة
// بتتحفظ غير بـ«احفظ»، والصوت مقفول على فورم الممرض.
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/widgets/f_wheels.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';

import '../../data/voice/fake_listener.dart';
import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../scan/scan_test_support.dart';

void main() {
  group('FChoiceWheel — العضو التالت في العيلة', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('بتبدأ على «من غير تحديد» ومفيش حاجة بتتكتب قبل ما تتحرّك', (tester) async {
      final written = <MedicationPurpose?>[];
      await pump(
        tester,
        FChoiceWheel<MedicationPurpose>(
          wheelKey: const ValueKey('w'),
          choices: MedicationPurpose.values,
          labelOf: (p) => p.label,
          onChanged: written.add,
        ),
      );
      expect(find.text('من غير تحديد'), findsOneWidget);
      expect(written, isEmpty, reason: 'مكان الراحة مش اختيار');

      // لفّة لـ«للضغط» (الصف اللي بعد «من غير تحديد»)
      await tester.drag(find.byKey(const ValueKey('w')), const Offset(0, -44));
      await tester.pumpAndSettle();
      expect(written, [MedicationPurpose.pressure]);

      // والرجوع لأول صف بيمسح — null
      await tester.drag(find.byKey(const ValueKey('w')), const Offset(0, 44));
      await tester.pumpAndSettle();
      expect(written.last, isNull);
    });

    testWidgets('قيمة من برّه (الصوت) بتحرّك البكرة من غير ما تتحسب اختيار', (tester) async {
      final written = <MedicineForm?>[];
      MedicineForm? value;
      late StateSetter set;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return FChoiceWheel<MedicineForm>(
              wheelKey: const ValueKey('w'),
              choices: MedicineForm.values,
              labelOf: (f) => f.label,
              value: value,
              onChanged: written.add,
            );
          },
        ),
      );
      set(() => value = MedicineForm.syrup);
      await tester.pumpAndSettle();
      final picker = tester.widget<CupertinoPicker>(find.byKey(const ValueKey('w')));
      expect(picker.scrollController!.selectedItem, MedicineForm.values.indexOf(MedicineForm.syrup) + 1);
      expect(written, isEmpty, reason: 'إحنا اللي حرّكناها — مش هو');
    });
  });

  group('«ضيف دوا» — البكر والصوت', () {
    late Harness h;
    late FakeListener listener;

    Future<void> setUpWith({List<Object?> answers = const [], bool mic = true}) async {
      SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true});
      h = Harness();
      await h.setUp();
      final voice = VoiceService(
        player: FakePlayer(),
        tts: FakeTts(),
        listener: mic ? (listener = FakeListener(answers: answers)) : null,
        micSettle: Duration.zero,
      );
      await voice.load();
      final s = h.services;
      h.services = AppServices(
        db: s.db, patients: s.patients, medications: s.medications, events: s.events,
        scheduler: s.scheduler, patientId: s.patientId, voice: voice,
      );
    }

    tearDown(() => h.tearDown());

    Future<void> pumpAdd(WidgetTester tester, {bool voiceInput = true}) async {
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.pump(tester, AddMedicationScreen(today: aug31, voiceInput: voiceInput));
      await settle(tester);
    }

    screenTest('البكرتين مكان الـ١٩ شريحة — وأول صف «من غير تحديد»', (tester) async {
      await setUpWith();
      await pumpAdd(tester);
      expect(find.byKey(const ValueKey('purpose-wheel')), findsOneWidget);
      expect(find.byKey(const ValueKey('form-wheel')), findsOneWidget);
      expect(find.byKey(const ValueKey('purpose-pressure')), findsNothing, reason: 'الشرايح اتشالت');
      expect(find.byKey(const ValueKey('form-tablet')), findsNothing);
      expect(find.text('من غير تحديد'), findsNWidgets(2));
      expectNoRedAndMinSize(tester);
    });

    screenTest('«قولها بصوتك»: جملة المالك بتملا الاسم والغرض والنوع والجرعة والأكل — ولا صف اتكتب قبل «احفظ»', (tester) async {
      await setUpWith(answers: ['كونكور ٥ مجم للضغط قرص الساعة ٩ الصبح بعد الفطار']);
      await pumpAdd(tester);

      await tester.tap(find.byKey(const ValueKey('say-it-all')));
      await settle(tester);

      expect(find.widgetWithText(TextField, 'كونكور'), findsOneWidget);
      expect(find.text('للضغط'), findsWidgets, reason: 'بكرة «لإيه؟» اتحرّكت');
      expect(find.text('قرص'), findsWidgets, reason: 'بكرة «نوعه؟» اتحرّكت');
      // ولا حاجة اتكتبت قبل «احفظ» (القاعدة ٤)
      expect(await h.db.select(h.db.medications).get(), isEmpty);

      await tester.tap(find.byKey(const ValueKey('save-medication')));
      await settle(tester);
      final med = (await h.db.select(h.db.medications).get()).single;
      expect(med.name, 'كونكور');
      expect(med.purpose, 'pressure');
      expect(med.form, 'tablet');
      expect(med.amountLabel, '5 مجم');
      final schedule = (await h.db.select(h.db.doseSchedules).get()).single;
      expect(schedule.mealRelation, 'after');
      final timing = (await h.db.select(h.db.fixedTimings).get()).single;
      expect(timing.minuteOfDay, 9 * 60, reason: 'الساعة اللي اتقالت بالحرف');
    });

    screenTest('«مرتين» من غير ساعات = صفّين فاضيين و«احفظ» مقفول — مفيش ساعة مننا', (tester) async {
      await setUpWith(answers: ['ضيف دوا بانادول مرتين في اليوم']);
      await pumpAdd(tester);
      await tester.tap(find.byKey(const ValueKey('say-it-all')));
      await settle(tester);

      expect(find.text('اختار الساعة'), findsNWidgets(2));
      final save = tester.widget<FilledButton>(
        find.descendant(of: find.byKey(const ValueKey('save-medication')), matching: find.byType(FilledButton)),
      );
      expect(save.onPressed, isNull, reason: 'الناقص بيفضل فاضي والإنسان بيكمّله');
    });

    screenTest('مش مفهوم → سطر مكتوب، ومفيش حاجة اتغيّرت', (tester) async {
      await setUpWith(answers: ['لا مش عارف']);
      await pumpAdd(tester);
      await tester.tap(find.byKey(const ValueKey('say-it-all')));
      await settle(tester);
      expect(find.byKey(const ValueKey('med-voice-note')), findsOneWidget);
      expect(find.textContaining('مش متأكد'), findsOneWidget);
      expect(find.text('من غير تحديد'), findsNWidgets(2), reason: 'البكر ما اتحرّكتش');
    });

    screenTest('سكوت → «ما سمعتش حاجة» والزرار فاضل', (tester) async {
      await setUpWith(answers: [null]);
      await pumpAdd(tester);
      await tester.tap(find.byKey(const ValueKey('say-it-all')));
      await settle(tester);
      expect(find.textContaining('ما سمعتش حاجة'), findsOneWidget);
      expect(find.byKey(const ValueKey('say-it-all')), findsOneWidget);
    });

    screenTest('مايك الحقل: «للضغط» بيملا بكرة «لإيه؟» وبس، و«شراب» بكرة «نوعه؟»', (tester) async {
      await setUpWith(answers: ['للضغط', 'شراب']);
      await pumpAdd(tester);

      await tester.tap(find.byKey(const ValueKey('field-mic-الدوا ده لإيه')));
      await settle(tester);
      expect(find.text('للضغط'), findsWidgets);
      expect(find.widgetWithText(TextField, 'للضغط'), findsNothing, reason: 'الاسم ما اتلمسش');

      await tester.tap(find.byKey(const ValueKey('field-mic-نوعه')));
      await settle(tester);
      expect(find.text('شراب'), findsWidgets);
      expect(listener.listens, 2, reason: 'دوسة = سماع واحد');
    });

    screenTest('مايك الاسم بيكتب في الحقل، و«لا» مش اسم', (tester) async {
      await setUpWith(answers: ['زيرتك', 'لا']);
      await pumpAdd(tester);
      await tester.tap(find.byKey(const ValueKey('field-mic-اسم الدوا')));
      await settle(tester);
      expect(find.widgetWithText(TextField, 'زيرتك'), findsOneWidget);
    });

    screenTest('الإذن مقفول → سطر بالسبب والصوت بيختفي من الشاشة دي', (tester) async {
      await setUpWith();
      listener.prepareOk = false;
      await pumpAdd(tester);
      await tester.tap(find.byKey(const ValueKey('say-it-all')));
      await settle(tester);
      expect(find.textContaining('الإذن'), findsOneWidget);
      expect(find.byKey(const ValueKey('say-it-all')), findsNothing);
      expect(find.byKey(const ValueKey('field-mic-اسم الدوا')), findsNothing);
    });

    screenTest('voiceInput: false (الممرض) → ولا زرار صوت، والبكر موجودة', (tester) async {
      await setUpWith();
      await pumpAdd(tester, voiceInput: false);
      expect(find.byKey(const ValueKey('say-it-all')), findsNothing);
      expect(find.byKey(const ValueKey('field-mic-اسم الدوا')), findsNothing);
      expect(find.byKey(const ValueKey('purpose-wheel')), findsOneWidget);
      expect(find.byKey(const ValueKey('form-wheel')), findsOneWidget);
    });

    screenTest('مفيش متعرّف (الكعب السحابي) → مفيش صوت، والفورم شغّال', (tester) async {
      await setUpWith(mic: false);
      await pumpAdd(tester);
      expect(find.byKey(const ValueKey('say-it-all')), findsNothing);
      expect(find.byKey(const ValueKey('purpose-wheel')), findsOneWidget);
    });

    screenTest('«قولها بصوتك» محدّد أخضر — مش مليان: «احفظ» هو الأساسي الوحيد', (tester) async {
      await setUpWith();
      await pumpAdd(tester);
      final button = tester.widget<OutlinedButton>(find.byKey(const ValueKey('say-it-all')));
      expect(button.style!.foregroundColor!.resolve({}), F.green);
      expect(find.widgetWithText(FilledButton, 'قولها بصوتك'), findsNothing);
    });
  });
}
