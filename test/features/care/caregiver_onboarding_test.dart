// **أربع أسئلة بعد ما الابن يستبدل الكود** — وكلهم بيتخطّوا.
//
// الإعدادات دي بتغيّر اللي بيوصل الابن وبس؛ مفيش حاجة هنا بتلمس تذكير
// الأب ولا توقيت السلّم.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_preferences.dart';
import 'package:fakkarni/domain/care/follower_profile.dart';
import 'package:fakkarni/features/care/onboarding/caregiver_onboarding_screen.dart';

import '../scan/scan_test_support.dart' show expectCaregiverDensity, screenTest, settle;

class _FakePreferences implements CaregiverPreferencesService {
  final List<CaregiverPreferences> saved = [];
  CaregiverPreferences stored = const CaregiverPreferences();

  @override
  Future<CaregiverPreferences> load(String patientUuid) async => stored;

  @override
  Future<void> save(String patientUuid, CaregiverPreferences preferences) async {
    saved.add(preferences);
    stored = preferences;
  }

  @override
  Future<List<FollowerProfile>> followers(String patientUuid) async =>
      [?stored.profile];
}

void main() {
  late _FakePreferences prefs;

  setUp(() => prefs = _FakePreferences());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: CaregiverOnboardingScreen(
          patientUuid: 'p1',
          patientName: 'الحاج أحمد',
          preferences: prefs,
        ),
      ),
    ));
    await settle(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await settle(tester);
  }

  Future<void> skip(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await settle(tester);
  }

  group('١ — اسمك وصلتك بيه', () {
    screenTest('الاسم والصلة بيتحفظوا، والعدّاد بيقول فين احنا', (tester) async {
      await pump(tester);
      expect(find.text('سؤال ١ من ٤'), findsOneWidget);
      expect(find.text('اسمك وصلتك بيه'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('follower-name')), 'محمد');
      await tester.tap(find.byKey(const ValueKey('relation-son')));
      await settle(tester);
      await next(tester);

      expect(prefs.stored.name, 'محمد');
      expect(prefs.stored.relation, FollowerRelation.son);
      // وده اللي الأب هيقراه
      expect(prefs.stored.profile!.sentence, 'محمد ابنك بيتابعك');
    });

    screenTest('و«حد تاني» بتفتح حقل نص، والنص بيتحفظ معاه', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('relation-other-text')), findsNothing,
          reason: 'الحقل مش موجود لحد ما يختار');

      await tester.enterText(find.byKey(const ValueKey('follower-name')), 'أحمد');
      await tester.tap(find.byKey(const ValueKey('relation-other')));
      await settle(tester);
      expect(find.byKey(const ValueKey('relation-other-text')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('relation-other-text')), 'أخوه');
      await settle(tester);
      await next(tester);

      expect(prefs.stored.relation, FollowerRelation.other);
      expect(prefs.stored.relationOther, 'أخوه');
      expect(prefs.stored.profile!.title, 'أحمد (أخوه)');
    });

    screenTest('التخطّي ما بيحفظش اسم فاضي', (tester) async {
      await pump(tester);
      await skip(tester);
      expect(prefs.saved, isEmpty, reason: 'اسم ما اتكتبش ما بيتحفظش');
      expect(find.text('سؤال ٢ من ٤'), findsOneWidget);
    });
  });

  group('٢ — عايز نبهك إمتى؟', () {
    screenTest('اختيار واحد، والسبب مكتوب قدّامه', (tester) async {
      await pump(tester);
      await skip(tester);

      expect(find.text('عايز نبهك إمتى؟'), findsOneWidget);
      expect(find.text('أي جرعة تفوت'), findsOneWidget);
      // **مفيش «الأدوية المهمة بس»** — العلامة دي اتشالت عن قصد، والاختيار
      // من غيرها كان معناه «مفيش تنبيهات».
      expect(find.textContaining('المهمة بس'), findsNothing);
      expect(find.textContaining('حكم طبي'), findsOneWidget);
    });

    screenTest('والقيمة المحفوظة هي الوحيدة الموجودة', (tester) async {
      await pump(tester);
      await skip(tester);
      await next(tester);
      expect(prefs.stored.alertScope, AlertScope.everyMissedDose);
      expect(AlertScope.values, hasLength(1));
    });
  });

  group('٣ — ساعات هدوء', () {
    screenTest('الوعد مكتوب على الشاشة بالحرف', (tester) async {
      await pump(tester);
      await skip(tester);
      await next(tester);

      expect(find.text('ساعات هدوء؟'), findsOneWidget);
      expect(find.text(quietHoursPromise), findsOneWidget);
      expect(find.textContaining('بيوصلك أول ما الهدوء يخلص'), findsOneWidget);
    });

    screenTest('اختيار نافذة بيتحفظ بالدقايق', (tester) async {
      await pump(tester);
      await skip(tester);
      await next(tester);
      await tester.tap(find.byKey(const ValueKey('quiet-0')));
      await settle(tester);
      await next(tester);

      expect(prefs.stored.quietFromMinute, 0);
      expect(prefs.stored.quietToMinute, 7 * 60);
      expect(prefs.stored.quietHours!.contains(DateTime(2026, 9, 22, 3)), isTrue);
    });

    screenTest('و«مفيش هدوء» هي الافتراضي', (tester) async {
      await pump(tester);
      await skip(tester);
      await next(tester);
      expect(prefs.stored.quietHours, isNull);
      await next(tester);
      expect(prefs.stored.quietHours, isNull);
    });
  });

  group('٤ — حد تاني يتابع معاك', () {
    Future<void> reachLast(WidgetTester tester) async {
      await pump(tester);
      await skip(tester);
      await next(tester);
      await next(tester);
    }

    screenTest('الطلب بيروح للأب — ومفيش كود بيتعمل هنا', (tester) async {
      await reachLast(tester);
      expect(find.text('فيه حد تاني يتابع معاك؟'), findsOneWidget);
      expect(find.textContaining('هنبعت طلب لوالدك يوافق عليه'), findsOneWidget);
      expect(find.textContaining('دي بياناته هو'), findsOneWidget);
      // ولا كود ظاهر ولا زرار بيطلب واحد
      expect(find.textContaining('الكود'), findsNothing);
    });

    screenTest('والسقف مكتوب، ومكتوب اللي بيحصل عنده', (tester) async {
      await reachLast(tester);
      expect(find.textContaining('أقصى عدد يتابعوه: ٥'), findsOneWidget);
      expect(find.textContaining('لازم واحد يخرج'), findsOneWidget);
    });

    screenTest('**وكل واحد بيدفع اشتراكه** — مكتوب قبل ما حد يتفاجئ',
        (tester) async {
      await reachLast(tester);
      expect(find.text(followerPaysLine), findsOneWidget);
      expect(followerPaysLine, contains('كل واحد بيتابع بيدفع اشتراكه هو'));
    });

    screenTest('وآخر زرار «تمام» مش «كمّل»، ومفيش تخطّى بعده', (tester) async {
      await reachLast(tester);
      expect(find.text('تمام'), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-skip')), findsNothing);
    });
  });

  screenTest('الكثافة كثافة الابن — مش نمط كبار السن', (tester) async {
    await pump(tester);
    expectCaregiverDensity(tester);
  });
}
