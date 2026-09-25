import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/features/onboarding/profile_page.dart';
import 'package:fakkarni/features/onboarding/routine_onboarding_screen.dart';
import 'package:fakkarni/core/widgets/f_wheels.dart';
import 'package:fakkarni/core/widgets/primitives.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize;
import '../../support/seeded_clock.dart';

/// النص المطلوب بالظبط وبالترتيب.
const expectedQuestions = [
  'بتصحى الساعة كام؟',
  'بتفطر الساعة كام؟',
  'بتتغدى الساعة كام؟',
  'بتتعشى الساعة كام؟',
  'بتنام الساعة كام؟',
];

class SilentSink implements ReminderSink {
  @override
  Future<void> schedule(PlannedNotification notification) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};

  @override
  Future<void> ensurePermissions() async {}
}

/// الخطوط الحقيقية — من غيرها flutter_test بيرسم كل حرف مربّع بعرض الخط
/// كله، وقياس iPhone SE تحت بيطلع أطول من الموبايل بكتير.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await load('IBM Plex Sans Arabic', [
    'IBMPlexSansArabic-Regular.ttf',
    'IBMPlexSansArabic-Medium.ttf',
    'IBMPlexSansArabic-SemiBold.ttf',
    'IBMPlexSansArabic-Bold.ttf',
  ]);
  await load('Alexandria', ['Alexandria-Medium.ttf', 'Alexandria-Bold.ttf']);
}

void main() {
  setUpAll(_loadFonts);
  late AppDatabase db;
  late RoutineRepository routines;
  late AppServices services;
  var finished = false;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    final medications = MedicationRepository(db, clock: seededLongAgo);
    final patientId = await routines.ensurePatient();
    finished = false;
    services = AppServices(
      db: db,
      routines: routines,
      medications: medications,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
        routines: routines,
        medications: medications,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: SilentSink(),
      ),
      patientId: patientId,
    );
  });

  tearDown(() => db.close());

  Future<void> pumpOnboarding(WidgetTester tester, {bool askProfile = false}) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: RoutineOnboardingScreen(
              onDone: () => finished = true,
              askProfile: askProfile,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('الخمس أسئلة بتظهر بالترتيب وبالنص المكتوب بالظبط',
      (tester) async {
    await pumpOnboarding(tester);

    for (final question in expectedQuestions) {
      expect(find.text(question), findsOneWidget, reason: question);
      await tapAndSettle(tester, 'تمام');
    }

    expect(finished, isTrue);
  });

  testWidgets('كل شاشة فيها «مش دلوقتي» — ومفيش «مش متأكد» بتكتب افتراضي', (tester) async {
    await pumpOnboarding(tester);

    for (var i = 0; i < expectedQuestions.length; i++) {
      expect(find.text('مش دلوقتي'), findsOneWidget);
      expect(find.text('مش متأكد'), findsNothing);
      await tapAndSettle(tester, 'مش دلوقتي');
    }
    expect(finished, isTrue, reason: 'التخطّي ما بيوقفش حد');
  });
  testWidgets('«مش دلوقتي» في كل سؤال → صف موجود وكل مرساة **مش متحددة** — مفيش افتراضي اتكتب كأنه اختاره', (tester) async {
    await pumpOnboarding(tester);

    for (var i = 0; i < expectedQuestions.length; i++) {
      await tapAndSettle(tester, 'مش دلوقتي');
    }

    final saved = await routines.getRoutine(services.patientId);
    expect(saved, isNotNull, reason: 'التطبيق بيكمّل — الصف موجود');
    expect(saved, DayRoutine.none);
    expect(saved!.isComplete, isFalse);
    for (final a in DayAnchor.values) {
      expect(saved.isSet(a), isFalse, reason: a.name);
    }
  });
  testWidgets('تخطّي سؤال واحد بس: الباقي متحدد زي ما جاوب، وهو لوحده مش متحدد', (tester) async {
    await pumpOnboarding(tester);
    await tapAndSettle(tester, 'تمام'); // الصحيان — الاقتراح النصّاني
    await tapAndSettle(tester, 'مش دلوقتي'); // الفطار
    for (var i = 0; i < 3; i++) {
      await tapAndSettle(tester, 'تمام');
    }
    final saved = (await routines.getRoutine(services.patientId))!;
    expect(saved.unset, {DayAnchor.breakfast});
    expect(saved.wake, MinuteOfDay.hm(6, 30));
    expect(saved.isSet(DayAnchor.dinner), isTrue);
  });

  testWidgets('البكرة بتغيّر الوقت المعروض وبيتحفظ — بالدقيقة الواحدة', (tester) async {
    await pumpOnboarding(tester);

    // أول سؤال: البكرة واقفة على ٦:٣٠ والوقت الكبير بيقوله
    expect(find.text('٦:٣٠ ص'), findsOneWidget);
    // خانة واحدة لفوق على الدقايق = دقيقة واحدة، مش خمسة
    await tester.drag(find.byKey(FTimeWheel.minutesKey), const Offset(0, -FTimeWheel.itemExtent));
    await tester.pumpAndSettle();
    expect(find.text('٦:٣١ ص'), findsOneWidget);

    for (var i = 0; i < expectedQuestions.length; i++) {
      await tapAndSettle(tester, i == 0 ? 'تمام' : 'مش دلوقتي');
    }

    final saved = await routines.getRoutine(services.patientId);
    expect(saved!.wake, MinuteOfDay.hm(6, 31));
  });

  testWidgets('مفيش اقتراحات خالص — البكرة ظاهرة على طول', (tester) async {
    await pumpOnboarding(tester);
    expect(find.byType(FTimeWheel), findsOneWidget);
    expect(find.byType(AnchorChip), findsNothing, reason: 'شريحة وبعدها بكرة خطوتين لنفس الرقم');
    expect(find.text('٦:٠٠ ص'), findsNothing);
    expect(find.text('٧:٠٠ ص'), findsNothing);
  });

  testWidgets('كل زرار أساسي ٦٤ وكل نص مش أقل من ١٧', (tester) async {
    await pumpOnboarding(tester);

    final button = tester.getSize(find.byType(FilledButton));
    expect(button.height, greaterThanOrEqualTo(F.primaryButtonHeight));

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
      }
    }
  });

  testWidgets('مفيش سحب بالإيد بين الأسئلة', (tester) async {
    await pumpOnboarding(tester);

    await tester.drag(find.text('بتصحى الساعة كام؟'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('بتصحى الساعة كام؟'), findsOneWidget);
  });

  testWidgets('خمس نقط تقدّم: الحالية ذهبية والباقي line، وبتتحرك مع الأسئلة', (tester) async {
    await pumpOnboarding(tester);

    Color dot(int i) =>
        (tester.widget<Container>(find.byKey(ValueKey('dot-$i'))).decoration! as BoxDecoration).color!;
    expect(dot(1), F.gold);
    for (var i = 2; i <= 5; i++) {
      expect(dot(i), F.line, reason: 'نقطة $i');
    }
    // مفيش عدّاد نصّي ولا شريط تقدّم قديم
    expect(find.textContaining('سؤال ١ من'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tapAndSettle(tester, 'تمام');
    expect(dot(1), F.line);
    expect(dot(2), F.gold);
  });

  testWidgets('أرقام الراحة هي افتراضيات README (٦:٣٠ — ٧:٣٠ — ٢:٠٠ — ٨:٠٠ — ١١:٣٠) — بس معلّمة إنها مش بتاعته', (tester) async {
    await pumpOnboarding(tester);
    for (var i = 0; i < expectedQuestions.length; i++) {
      await tapAndSettle(tester, 'مش دلوقتي');
    }
    final saved = (await routines.getRoutine(services.patientId))!;
    expect(saved.wake, MinuteOfDay.hm(6, 30));
    expect(saved.breakfast, MinuteOfDay.hm(7, 30));
    expect(saved.lunch, MinuteOfDay.hm(14));
    expect(saved.dinner, MinuteOfDay.hm(20));
    expect(saved.sleep, MinuteOfDay.hm(23, 30));
    expect(saved.unset, DayAnchor.values.toSet(), reason: 'أماكن راحة، مش إجابات');
  });

  testWidgets('البكرة واقفة على مكان الراحة (٦:٣٠) والوقت الكبير بيقوله من غير ما يدوس', (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('٦:٣٠ ص'), findsOneWidget);
    await tapAndSettle(tester, 'تمام');
    expect((await routines.getRoutine(services.patientId)), isNull, reason: 'لسه أربع أسئلة');
  });

  group('«نتعرّف عليك» قبل الأسئلة (المخطط 21)', () {
    Future<void> pumpTall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpOnboarding(tester, askProfile: true);
    }

    FilledButton next(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'كمّل'));

    /// صفحة الاسم ← الجنس ← السن، بـ«كمّل» بين كل صفحة والتانية.
    Future<void> toAge(WidgetTester tester, String name, String sex) async {
      await tester.enterText(find.byType(TextField), name);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, 'كمّل');
      await tapAndSettle(tester, sex);
      await tapAndSettle(tester, 'كمّل');
    }

    testWidgets('تلات صفحات، سؤال في كل صفحة: الاسم ← الجنس ← السن، و«كمّل» مقفولة لحد ما يجاوب', (tester) async {
      await pumpTall(tester);

      expect(find.text('نتعرّف عليك'), findsOneWidget);
      expect(find.text('اسمك إيه؟'), findsOneWidget);
      expect(find.text('راجل ولا ست؟'), findsNothing, reason: 'الجنس صفحة لوحده');
      expect(find.byKey(const ValueKey('age-wheel')), findsNothing, reason: 'السن صفحة لوحده');
      expect(find.text(expectedQuestions.first), findsNothing, reason: 'الأسئلة بعدين');
      expect(next(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'الحاج أحمد');
      await tester.pumpAndSettle();
      expect(next(tester).onPressed, isNotNull);
      await tapAndSettle(tester, 'كمّل');

      expect(find.text('راجل ولا ست؟'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(next(tester).onPressed, isNull, reason: 'لسه الجنس');
      await tapAndSettle(tester, 'راجل');
      expect(next(tester).onPressed, isNotNull);
      await tapAndSettle(tester, 'كمّل');

      expect(find.byKey(const ValueKey('age-wheel')), findsOneWidget);
      expect(find.text('راجل ولا ست؟'), findsNothing);
      expect(next(tester).onPressed, isNotNull, reason: 'السن اختياري');
      expect(await services.routines.getPatient(services.patientId).then((r) => r?.sex), isNull,
          reason: 'ولا حاجة بتتحفظ قبل آخر صفحة');
      expectNoRedAndMinSize(tester);
    });

    testWidgets('«رجوع» بيرجع صفحة، والمكتوب بيفضل زي ما هو', (tester) async {
      await pumpTall(tester);
      expect(find.byKey(const ValueKey('onboarding-back')), findsNothing, reason: 'أول صفحة ومفيش شاشة قبلها هنا');
      await toAge(tester, 'الحاج أحمد', 'راجل');

      await tester.tap(find.byKey(const ValueKey('onboarding-back')));
      await tester.pumpAndSettle();
      expect(find.text('راجل ولا ست؟'), findsOneWidget);
      final male = tester.widget<AnchorChip>(find.byKey(const ValueKey('sex-m')));
      expect(male.selected, isTrue, reason: 'الاختيار فاضل');

      await tester.tap(find.byKey(const ValueKey('onboarding-back')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'الحاج أحمد'), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-back')), findsNothing);
    });

    testWidgets('ست → الأسئلة بالمؤنث، والجنس والاسم اتحفظوا، والسن null لو ما اختارتش', (tester) async {
      await pumpTall(tester);

      await toAge(tester, 'الحاجة فاطمة', 'ست');
      // الكلام على الصفحة نفسها بيتبع الجنس فوراً
      expect(find.textContaining('بتفطري الساعة كام؟'), findsOneWidget);
      await tapAndSettle(tester, 'كمّل');

      expect(find.text('بتصحي الساعة كام؟'), findsOneWidget);
      expect(find.text('مش دلوقتي'), findsOneWidget, reason: 'التخطّي محايد — كلمة واحدة للاتنين');
      expect(find.text('بتصحى الساعة كام؟'), findsNothing);

      final row = (await services.routines.getPatient(services.patientId))!;
      expect(row.name, 'الحاجة فاطمة');
      expect(row.sex, Sex.f);
      expect(row.age, isNull, reason: 'مش بنكتب سن ما اتقالش');
    });

    /// بيحرّك البكرة [items] خانة: بالسالب لفوق (سن أكبر)، بالموجب لتحت.
    Future<void> spin(WidgetTester tester, int items) async {
      await tester.drag(find.byType(CupertinoPicker), Offset(0, -AgeWheel.itemExtent * items));
      await tester.pumpAndSettle();
    }

    String hint(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('age-hint'))).data!;

    testWidgets('راجل وحرّك البكرة → الأسئلة بالمذكر والسن اللي وقف عنده اتحفظ', (tester) async {
      await pumpTall(tester);

      await toAge(tester, 'الحاج أحمد', 'راجل');
      await spin(tester, 5); // ٦٠ → ٦٥
      expect(hint(tester), 'سنّك ٦٥ سنة');
      await tapAndSettle(tester, 'كمّل');

      expect(find.text('بتصحى الساعة كام؟'), findsOneWidget);
      expect(find.text('مش دلوقتي'), findsOneWidget);
      final row = (await services.routines.getPatient(services.patientId))!;
      expect(row.sex, Sex.m);
      expect(row.age, 65);
    });

    testWidgets('البكرة واقفة على ٦٠ ومفيش حاجة بتتكتب لحد ما تتحرّك', (tester) async {
      await pumpTall(tester);
      await toAge(tester, 'الحاج أحمد', 'راجل');
      // البكرة موجودة، والتلميح بيقول حرّكها، ومفيش سن معروض
      expect(find.byKey(const ValueKey('age-wheel')), findsOneWidget);
      expect(hint(tester), AgeWheel.hint);
      expect(find.textContaining('سنّك ٦٠'), findsNothing);
      expect(AgeWheel.minAge, 18, reason: 'مريض بأدوية مزمنة ممكن يكون عنده ٢٠');
      expect(AgeWheel.maxAge, 110);

      await tapAndSettle(tester, 'كمّل');
      final row = (await services.routines.getPatient(services.patientId))!;
      expect(row.age, isNull, reason: 'البكرة واقفة على ٦٠ مش معناه إنه قال ٦٠');
    });

    testWidgets('سن صغير بيتحفظ زي ما هو — مفيش أرضية ٦٠', (tester) async {
      await pumpTall(tester);
      await toAge(tester, 'محمد', 'راجل');
      await spin(tester, -30); // ٦٠ → ٣٠
      expect(hint(tester), 'سنّك ٣٠ سنة');
      await tapAndSettle(tester, 'كمّل');
      final row = (await services.routines.getPatient(services.patientId))!;
      expect(row.age, 30);
    });

    testWidgets('«مش عايز أقول» بترجّع null بعد ما اختار، والبكرة بترجع لـ٦٠', (tester) async {
      await pumpTall(tester);
      await toAge(tester, 'الحاج أحمد', 'راجل');
      await spin(tester, 5);
      expect(hint(tester), 'سنّك ٦٥ سنة');

      await tapAndSettle(tester, 'مش عايز أقول');
      expect(hint(tester), AgeWheel.hint);
      final wheel = tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
      expect(wheel.scrollController!.selectedItem, AgeWheel.restAge - AgeWheel.minAge);

      await tapAndSettle(tester, 'كمّل');
      final row = (await services.routines.getPatient(services.patientId))!;
      expect(row.age, isNull);
    });

    testWidgets('ست → «مش عايزة أقول» — الصيغة بتمشي مع إجابة الجنس', (tester) async {
      await pumpTall(tester);
      await toAge(tester, 'الحاجة فاطمة', 'ست');
      expect(find.text('مش عايزة أقول'), findsOneWidget);
      expect(find.text('مش عايز أقول'), findsNothing);
    });

    testWidgets('على iPhone SE: كل صفحة و«كمّل» بتاعتها ظاهرين من غير لفّ ومن غير فيض', (tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpOnboarding(tester, askProfile: true);

      void fits(String page) {
        expect(tester.takeException(), isNull, reason: 'فيض — $page');
        final button = tester.getRect(find.widgetWithText(FilledButton, 'كمّل'));
        expect(button.bottom, lessThanOrEqualTo(667), reason: page);
        expect(button.top, greaterThanOrEqualTo(0), reason: page);
        expectNoRedAndMinSize(tester);
      }

      fits('الاسم');
      await tester.enterText(find.byType(TextField), 'الحاج أحمد');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, 'كمّل');
      fits('الجنس');
      await tapAndSettle(tester, 'راجل');
      await tapAndSettle(tester, 'كمّل');
      fits('السن');
      final button = tester.getRect(find.widgetWithText(FilledButton, 'كمّل'));
      final wheel = tester.getRect(find.byKey(const ValueKey('age-wheel')));
      expect(wheel.height, AgeWheel.wheelHeight);
      final clear = tester.getRect(find.text('مش عايز أقول'));
      expect(clear.bottom, lessThanOrEqualTo(button.top),
          reason: 'كتلة السن كلها فوق «كمّل» من غير لفّ: ${wheel.bottom} / ${clear.bottom} / ${button.top}');
    });

    testWidgets('الجنس متسجّل قبل كده → الأسئلة على طول من غير «نتعرّف عليك»', (tester) async {
      await services.routines.saveProfile(services.patientId, name: 'الحاج أحمد', sex: Sex.m);
      await pumpTall(tester);
      expect(find.text('نتعرّف عليك'), findsNothing);
      expect(find.text(expectedQuestions.first), findsOneWidget);
    });
  });
}
