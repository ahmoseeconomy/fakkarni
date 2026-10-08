// «ضيف دوا» بعد تجربة الآيفون (٦ أكتوبر ٢٠٢٦): «مرتين» والبكرة واقفة،
// «10:00 الصبح» مرفوضة، «كل يوم» = «مافهمتش»، والصفوف بتزيد من غير شيل.
//
// - الكلام بالعلامات المخفية زي ما الآيفون بيرجّعه بيحرّك البكرة نفسها.
// - سطر صريح لكل نتيجة («ظبّطت …» / «مافهمتش …») — مش «سمعت: …» الجزئي.
// - سطر الأثر بيطبع أكواد الحروف والنتيجة الحقيقية.
// - البكرة الفئوية بتلحق القيمة بعد الفريم، والدوسة على الصف الظاهر بتبلّغ.
// - الصفوف = «كام مرة»؛ «عدّل» و«شيل» لكل صف؛ «اتشالت الجرعة / رجّعها»
//   مكان الصف لحد الفعل الجاي؛ آخر جرعة من غير «شيل».
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/f_wheels.dart';
import 'package:fakkarni/data/voice/voice_service.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_editor.dart';
import 'package:fakkarni/features/medication/med_voice_input.dart';

import '../../data/voice/fake_listener.dart';
import '../../data/voice/voice_service_test.dart' show FakePlayer, FakeTts;
import '../scan/scan_test_support.dart';

void main() {
  late Harness h;

  Future<void> setUpWith({List<Object?> answers = const []}) async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true});
    h = Harness();
    await h.setUp();
    final voice = VoiceService(
      player: FakePlayer(),
      tts: FakeTts(),
      listener: FakeListener(answers: answers),
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

  Future<void> pumpAdd(WidgetTester tester, {bool mics = true}) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, AddMedicationScreen(today: aug31));
    await settle(tester);
    if (mics) {
      await tester.tap(find.byKey(const ValueKey('voice-input-switch')));
      await settle(tester);
    }
  }

  int item(WidgetTester tester, String key) =>
      tester.widget<CupertinoPicker>(find.byKey(ValueKey(key))).scrollController!.selectedItem;

  String? note(WidgetTester tester, String forWhat) {
    final f = find.byKey(ValueKey('mic-note-$forWhat'));
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  Future<void> mic(WidgetTester tester, String forWhat) async {
    await tester.tap(find.byKey(ValueKey('field-mic-$forWhat')));
    await settle(tester);
  }

  List<String> rowTexts(WidgetTester tester) => [
        for (var i = 0; find.byKey(ValueKey('dose-row-$i')).evaluate().isNotEmpty; i++)
          tester
              .widgetList<Text>(find.descendant(of: find.byKey(ValueKey('dose-row-$i')), matching: find.byType(Text)))
              .map((t) => t.data ?? '')
              .elementAt(1),
      ];

  group('الكلام زي ما الآيفون رجّعه — بالعلامات المخفية — بيحرّك البكرة', () {
    screenTest('«مرتين» بعلامتين: البكرة على «مرتين»، وسطر «ظبّطت» مش «سمعت»', (tester) async {
      await setUpWith(answers: ['\u200Fمرتين\u200E.']);
      await pumpAdd(tester);
      expect(item(tester, 'count-wheel'), 0);
      await mic(tester, 'كام مرة');
      expect(item(tester, 'count-wheel'), 1, reason: 'البكرة نفسها اتحرّكت');
      expect(find.byKey(const ValueKey('dose-row-1')), findsOneWidget);
      expect(note(tester, 'كام مرة'), 'ظبّطت «مرتين».');
    });

    screenTest('«كل يوم» بعلامة جوّه: من «كل كام ساعة» لـ«كل يوم»', (tester) async {
      await setUpWith(answers: ['كل ١٢ ساعة', 'كل\u200F يوم.']);
      await pumpAdd(tester);
      await mic(tester, 'بياخده إزاي');
      expect(item(tester, 'pattern-wheel'), 1);
      await mic(tester, 'بياخده إزاي');
      expect(item(tester, 'pattern-wheel'), 0, reason: '«كل يوم»');
      expect(note(tester, 'بياخده إزاي'), 'ظبّطت «كل يوم».');
    });

    screenTest('«10:00 الصبح» بعلامات اتجاه، و«10 الصبح»، و«تسعة ونص بالليل»', (tester) async {
      await setUpWith(answers: ['\u200E10:00\u200E الصبح', '10 الصبح', 'تسعة ونص بالليل']);
      await pumpAdd(tester);
      int clock() => tester.widget<FTimeWheel>(find.byType(FTimeWheel)).value.minutes;
      await mic(tester, 'الساعة');
      expect(clock(), 10 * 60);
      expect(note(tester, 'الساعة'), 'ظبّطت الساعة «١٠:٠٠ ص».');
      await pickTime(tester, const MinuteOfDay(8 * 60));
      await mic(tester, 'الساعة');
      expect(clock(), 10 * 60);
      await mic(tester, 'الساعة');
      expect(clock(), 21 * 60 + 30);
    });

    screenTest('الفشل بيقول «مافهمتش» باللي اتسمع — مش «سمعت»', (tester) async {
      await setUpWith(answers: ['تسعة']);
      await pumpAdd(tester);
      await mic(tester, 'الساعة');
      expect(note(tester, 'الساعة'), startsWith('مافهمتش «تسعة»'));
      expect(note(tester, 'الساعة'), contains('صباح أو مساء'));
    });

    screenTest('السطر الجزئي «سمعت: …» بيتمسح قبل المعالج — النجاح ليه سطره', (tester) async {
      await setUpWith(answers: ['للضغط']);
      await pumpAdd(tester);
      await mic(tester, 'الدوا ده لإيه');
      expect(find.textContaining('سمعت'), findsNothing);
      expect(note(tester, 'الدوا ده لإيه'), 'ظبّطت «للضغط».');
    });

    screenTest('سطر الأثر: أكواد الحروف بالـhex والنتيجة الحقيقية — عمره ما يقول «اتقبلت»', (tester) async {
      final lines = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      await setUpWith(answers: ['\u200Fمرتين', 'كلام تاني']);
      await pumpAdd(tester);
      try {
        await mic(tester, 'كام مرة');
        await mic(tester, 'كام مرة');
      } finally {
        debugPrint = old;
      }
      final trace = lines.where((l) => l.contains('MedVoice: heard=')).toList();
      expect(trace, hasLength(2));
      expect(trace[0], contains('hex=[200f 645 631 62a 64a 646]'));
      expect(trace[0], contains('→ ظبّطت «مرتين».'));
      expect(trace[1], contains('→ مافهمتش'));
      expect(trace.join(), isNot(contains('اتقبلت')));
    });
  });

  test('MedVoiceSession: «سمعت: …» الجزئي بيتمسح قبل المعالج — ومعالج ساكت بيتسجّل كده، مش «اتقبلت»', () async {
    SharedPreferences.setMockInitialValues({VoiceService.enabledKey: true});
    final voice = VoiceService(
      player: FakePlayer(),
      tts: FakeTts(),
      listener: FakeListener(answers: ['مرتين']),
      micSettle: Duration.zero,
    );
    await voice.load();
    final session = MedVoiceSession(voice);
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    String? seenByHandler = 'لسه';
    try {
      await session.hearAndApply('كام مرة', (_) => seenByHandler = session.note);
    } finally {
      debugPrint = old;
    }
    expect(seenByHandler, isNull, reason: 'السطر الجزئي اتمسح قبل المعالج');
    expect(session.note, isNull);
    expect(lines.singleWhere((l) => l.contains('MedVoice: heard=')), contains('→ المعالج ما كتبش نتيجة'));
  });

  group('FChoiceWheel — بتلحق القيمة، والدوسة على الصف الظاهر بتبلّغ', () {
    Future<void> pumpWheel(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(MaterialApp(
        theme: F.light,
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: child))),
      ));
      await tester.pump();
    }

    testWidgets('قيمة من برّه بتتطبّق بعد الفريم — وبآخر قيمة لو اتغيّرت مرتين', (tester) async {
      int? value = 1;
      late StateSetter set;
      final written = <int?>[];
      await pumpWheel(
        tester,
        StatefulBuilder(builder: (context, setState) {
          set = setState;
          return FChoiceWheel<int>(
            wheelKey: const ValueKey('w'),
            noneLabel: null,
            choices: const [1, 2, 3, 4],
            labelOf: (n) => '$n',
            value: value,
            onChanged: written.add,
          );
        }),
      );
      set(() => value = 2);
      await tester.pump();
      set(() => value = 3);
      await tester.pump();
      await tester.pump();
      expect(item(tester, 'w'), 2, reason: 'آخر قيمة (٣)');
      expect(written, isEmpty, reason: 'إحنا اللي حرّكناها');
    });

    testWidgets('الدوسة على الصف اللي البكرة واقفة عليه بتبلّغ — الرجوع لـ«مرة» ممكن', (tester) async {
      final written = <int?>[];
      await pumpWheel(
        tester,
        FChoiceWheel<int>(
          wheelKey: const ValueKey('w'),
          noneLabel: null,
          choices: const [1, 2, 3],
          labelOf: (n) => '$n',
          value: 2, // الحالة «٢»…
          onChanged: written.add,
        ),
      );
      // …والبكرة باينة على «١» (اللي حصل على الآيفون)
      tester.widget<CupertinoPicker>(find.byKey(const ValueKey('w'))).scrollController!.jumpToItem(0);
      await tester.pump();
      written.clear();
      await tester.tap(find.byKey(const ValueKey('w')));
      await tester.pump();
      expect(written, [1], reason: 'الصف الظاهر اتبلّغ رغم إنه ما اتحرّكش');
    });

    testWidgets('الدوسة على صف جنبه بتلف عليه وبتبلّغه', (tester) async {
      final written = <int?>[];
      await pumpWheel(
        tester,
        FChoiceWheel<int>(
          wheelKey: const ValueKey('w'),
          noneLabel: null,
          choices: const [1, 2, 3],
          labelOf: (n) => '$n',
          value: 1,
          onChanged: written.add,
        ),
      );
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(item(tester, 'w'), 1);
      expect(written.last, 2);
    });
  });

  group('«مواعيد الجرعات» — العدد = الصفوف، «عدّل» و«شيل»، و«رجّعها»', () {
    screenTest('التقليل بيشيل من الآخر بساعاته، والزيادة بتوزّع زي أول مرة', (tester) async {
      await setUpWith();
      await pumpAdd(tester, mics: false);
      await pickWheel(tester, const ValueKey('count-wheel'), 2); // ٣ مرات
      await pickTime(tester, const MinuteOfDay(9 * 60));
      expect(rowTexts(tester), ['الساعة ٩:٠٠ ص', 'الساعة ٢:٢٠ م', 'الساعة ٧:٤٠ م']);

      await pickWheel(tester, const ValueKey('count-wheel'), 1); // مرتين
      expect(rowTexts(tester), ['الساعة ٩:٠٠ ص', 'الساعة ٢:٢٠ م'], reason: 'من الآخر — والباقي بساعاته');

      await pickWheel(tester, const ValueKey('count-wheel'), 2); // ٣ تاني
      expect(rowTexts(tester), hasLength(3));
      expect(find.text('اختار الساعة'), findsNothing, reason: 'الجديد اتوزّع — مش فاضي');
    });

    screenTest('بعد تعديل بالإيد: الزيادة ما بتلمسش الصفوف، والجديد في أوسع فجوة بالنهار', (tester) async {
      await setUpWith(answers: ['تسعة الصبح وتسعة بالليل']);
      await pumpAdd(tester);
      await pickWheel(tester, const ValueKey('count-wheel'), 1);
      await mic(tester, 'المواعيد');
      expect(rowTexts(tester), ['الساعة ٩:٠٠ ص', 'الساعة ٩:٠٠ م']);
      await pickWheel(tester, const ValueKey('count-wheel'), 2);
      expect(rowTexts(tester), ['الساعة ٩:٠٠ ص', 'الساعة ٩:٠٠ م', 'الساعة ٣:٠٠ م']);
    });

    screenTest('«شيل» بيشيل الجرعة دي والعدد بينزل، و«رجّعها» مكانها بنفس ساعتها', (tester) async {
      await setUpWith();
      await pumpAdd(tester, mics: false);
      await pickWheel(tester, const ValueKey('count-wheel'), 2);
      await pickTime(tester, const MinuteOfDay(9 * 60));

      await tester.tap(find.byKey(const ValueKey('dose-remove-1')));
      await settle(tester);
      expect(item(tester, 'count-wheel'), 1, reason: 'العدد نزل لـ«مرتين»');
      expect(rowTexts(tester), ['الساعة ٩:٠٠ ص', 'الساعة ٧:٤٠ م']);
      expect(find.text('اتشالت الجرعة'), findsOneWidget);
      // السطر مكان الصف التاني بالظبط
      final y0 = tester.getTopLeft(find.byKey(const ValueKey('dose-row-0'))).dy;
      final yUndo = tester.getTopLeft(find.byKey(const ValueKey('dose-undo'))).dy;
      final y1 = tester.getTopLeft(find.byKey(const ValueKey('dose-row-1'))).dy;
      expect(y0 < yUndo && yUndo < y1, isTrue);
      expect(find.byType(AlertDialog), findsNothing, reason: 'من غير نافذة تأكيد');

      await tester.tap(find.byKey(const ValueKey('dose-restore')));
      await settle(tester);
      expect(rowTexts(tester), ['الساعة ٩:٠٠ ص', 'الساعة ٢:٢٠ م', 'الساعة ٧:٤٠ م']);
      expect(item(tester, 'count-wheel'), 2);
      expect(find.text('اتشالت الجرعة'), findsNothing);
    });

    screenTest('«رجّعها» بتفضل من غير عدّاد، وبتمشي مع الفعل الجاي على الجرعات', (tester) async {
      await setUpWith();
      await pumpAdd(tester, mics: false);
      await pickWheel(tester, const ValueKey('count-wheel'), 2);
      await pickTime(tester, const MinuteOfDay(9 * 60));
      await tester.tap(find.byKey(const ValueKey('dose-remove-0')));
      await settle(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('اتشالت الجرعة'), findsOneWidget, reason: 'مفيش وقت بيخلّصها');
      await pickTime(tester, const MinuteOfDay(10 * 60));
      expect(find.text('اتشالت الجرعة'), findsNothing);
    });

    screenTest('آخر جرعة: مفيش «شيل» — والكارت بيفضل لحد ما «رجّعها» تمشي، وبعدها بيستخبى', (tester) async {
      await setUpWith();
      await pumpAdd(tester, mics: false);
      await pickWheel(tester, const ValueKey('count-wheel'), 1);
      await pickTime(tester, const MinuteOfDay(9 * 60));
      expect(find.byKey(const ValueKey('dose-remove-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('dose-remove-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dose-remove-1')));
      await settle(tester);
      expect(item(tester, 'count-wheel'), 0, reason: '«مرة»');
      expect(find.byKey(const ValueKey('dose-row-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('dose-remove-0')), findsNothing, reason: 'آخر جرعة ما بتتشالش');
      expect(find.byKey(const ValueKey('dose-restore')), findsOneWidget);

      await pickTime(tester, const MinuteOfDay(10 * 60));
      expect(find.text('مواعيد الجرعات'), findsNothing, reason: 'جرعة واحدة = الكارت مستخبي (2A)');
    });

    screenTest('«عدّل» بيفتح محرّر الجرعة دي — والزرارين بكلمتهم و٥٦ أو أكتر', (tester) async {
      await setUpWith();
      await pumpAdd(tester, mics: false);
      await pickWheel(tester, const ValueKey('count-wheel'), 1);
      for (final k in ['dose-edit-0', 'dose-remove-0']) {
        expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(F.minTapTarget));
      }
      expect(find.descendant(of: find.byKey(const ValueKey('dose-edit-0')), matching: find.text('عدّل')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('dose-remove-0')), matching: find.text('شيل')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dose-edit-1')));
      await settle(tester);
      expect(find.byType(DoseEditor), findsOneWidget);
    });

    screenTest('«كل كام ساعة»: «عدّل» من غير «شيل» — الشيل بيكسر الفاصل', (tester) async {
      await setUpWith();
      await pumpAdd(tester, mics: false);
      await pickWheel(tester, const ValueKey('pattern-wheel'), 1);
      expect(find.byKey(const ValueKey('dose-edit-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('dose-remove-0')), findsNothing);
    });

    screenTest('«أكتر» = ٥ صفوف ظاهرة قدّامه وبكرة العدد على ٥ — مش زيادة مستخبية', (tester) async {
      await setUpWith();
      await pumpAdd(tester, mics: false);
      await pickWheel(tester, const ValueKey('count-wheel'), 4); // «أكتر»
      expect(find.byKey(const ValueKey('count-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('dose-row-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('dose-row-5')), findsNothing);
      expect(find.text('اختار الساعة'), findsNWidgets(5), reason: 'من غير ساعة أولى: فاضيين وذهبي — «احفظ» مقفول');
    });
  });
}
