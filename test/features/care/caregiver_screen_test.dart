import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/features/care/caregiver_screen.dart';

import '../scan/scan_test_support.dart' show settle, screenTest, expectNoRedAndMinSize;

/// «دلوقتي» ثابتة للاختبارات: ٣١ أغسطس ٢٠٢٦، ٢ الضهر.
final now = DateTime(2026, 8, 31, 14);

class FakeCaregiverRemote implements CaregiverRemote {
  CaregiverSnapshot? next;
  CareCircleException? failure;
  int calls = 0;

  @override
  Future<CaregiverPatient?> linkedPatient() async => next?.patient;

  @override
  Future<CaregiverSnapshot?> snapshot() async {
    calls++;
    final f = failure;
    if (f != null) throw f;
    return next;
  }
}

CaregiverDoseEvent event(
  String name,
  DateTime at,
  String state, {
  DateTime? actedAt,
}) =>
    CaregiverDoseEvent(
      uuid: '$name-${at.millisecondsSinceEpoch}',
      medicationName: name,
      amountLabel: 'قرص واحد',
      scheduledAt: at,
      state: state,
      actedAt: actedAt,
    );

CaregiverSnapshot snapshot(
  List<CaregiverDoseEvent> events, {
  List<CaregiverAlert> alerts = const [],
  DateTime? lastUpdated,
}) =>
    CaregiverSnapshot(
      patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
      medications: const [
        CaregiverMedication(uuid: 'm1', name: 'Concor 5mg', amountLabel: 'قرص واحد'),
      ],
      events: events,
      alerts: alerts,
      lastUpdated: lastUpdated ?? DateTime(2026, 8, 31, 13, 30),
    );

/// تنبيه سيرفر على جرعة الساعة ٨ الصبح، اتبعت +٦٠ (٩:٠٠).
CaregiverAlert alert({
  String doseState = 'pending',
  String deliveryStatus = 'sent',
}) =>
    CaregiverAlert(
      uuid: 'esc-1',
      medicationName: 'Concor 5mg',
      scheduledAt: DateTime(2026, 8, 31, 8),
      doseState: doseState,
      deliveryStatus: deliveryStatus,
      createdAt: DateTime(2026, 8, 31, 9),
      sentAt: deliveryStatus == 'sent' ? DateTime(2026, 8, 31, 9) : null,
    );

void main() {
  late FakeCaregiverRemote remote;

  setUp(() => remote = FakeCaregiverRemote());

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CaregiverScreen(remote: remote, now: now),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('أب ظبّط أدويته بالليل: كل الجرعات بكرة → الجملة اللي بتقول اللي جاي، وقايمة بكرة، مش شاشة فاضية',
      (tester) async {
    // «دلوقتي» ٢ الضهر ٣١ أغسطس — ولا جرعة النهارده ولا في الأسبوع اللي فات
    remote.next = snapshot([
      event('Glucophage 500', DateTime(2026, 9, 1, 21), 'pending'),
      event('Concor 5mg', DateTime(2026, 9, 1, 7), 'pending'),
    ]);
    await pumpScreen(tester);

    expect(find.text('مفيش جرعات النهارده — أول جرعة بكرة الساعة ٧:٠٠ الصبح'), findsOneWidget,
        reason: 'الأول بالوقت، حتى لو الصفوف جات بترتيب تاني');
    expect(find.text('مفيش جرعات متسجّلة النهارده لسه.'), findsNothing);

    // قايمة بكرة — متعلّمة بكرة، ومرتبة بالوقت
    expect(find.text('بكرة ٧:٠٠ ص'), findsOneWidget);
    expect(find.text('بكرة ٩:٠٠ م'), findsOneWidget);
    final concorTop = tester.getTopLeft(find.text('بكرة ٧:٠٠ ص')).dy;
    final glucophageTop = tester.getTopLeft(find.text('بكرة ٩:٠٠ م')).dy;
    expect(concorTop, lessThan(glucophageTop));
    expect(find.text('لسه ما اتأكدتش'), findsNothing, reason: 'بكرة مش متأخرة');

    // الشريط: جملة واحدة بدل سبع شَرطات
    expect(find.text('لسه بدري. أول جرعة هتبان هنا أول ما تتسجّل'), findsOneWidget);
    expect(find.text('—'), findsNothing);

    // قراية بس
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('عدّل'), findsNothing);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«بكرة» يعني تاريخ بكرة بالظبط: جرعات بعد بكرة ما بتدخلش القايمة', (tester) async {
    // جهاز الأب بيدفع حوالي يومين قدام — فلتر «بعد دلوقتي» كان هيجيب بعد بكرة
    // تحت عنوان «بكرة». الفلتر على تاريخ بكرة نفسه.
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 9, 1, 7), 'pending'),
      event('Glucophage 500', DateTime(2026, 9, 2, 6), 'pending'),
      event('Telfast', DateTime(2026, 9, 2, 22), 'pending'),
    ]);
    await pumpScreen(tester);

    expect(find.text('مفيش جرعات النهارده — أول جرعة بكرة الساعة ٧:٠٠ الصبح'), findsOneWidget,
        reason: 'أول جرعة بكرة — مش ٦ الصبح بتاعة بعد بكرة');
    expect(find.text('بكرة ٧:٠٠ ص'), findsOneWidget);
    expect(find.textContaining('Glucophage'), findsNothing);
    expect(find.textContaining('Telfast'), findsNothing);
  });

  screenTest('فيه جرعات الأسبوع ده → الشريط بأيامه زي ما هو، مش الجملة', (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 29, 8), 'taken', actedAt: DateTime(2026, 8, 29, 8, 2)),
      event('Concor 5mg', DateTime(2026, 9, 1, 8), 'pending'),
    ]);
    await pumpScreen(tester);

    expect(find.text('لسه بدري. أول جرعة هتبان هنا أول ما تتسجّل'), findsNothing);
    // الكسر بقى مكتوب بالكلام — «١/١» محدش كان بيعرف يقراها
    expect(find.text('١ من ١ اتأكدت'), findsOneWidget);
    expect(find.text('مفيش بيانات'), findsWidgets, reason: 'يوم من غير خبر بيقول كده');
    expect(find.textContaining('أول جرعة بكرة الساعة ٨:٠٠ الصبح'), findsOneWidget,
        reason: 'النهارده فاضي — بكرة فيها');
  });

  screenTest('كله متأكد → أخضر هادي، ومفيش ذهبي ولا أحمر', (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken',
          actedAt: DateTime(2026, 8, 31, 8, 5)),
      event('Telfast', DateTime(2026, 8, 31, 12), 'skipped'),
    ]);
    await pumpScreen(tester);

    expect(find.text('متابعة الحاج أحمد'), findsOneWidget);
    expect(find.textContaining('اتاخد'), findsOneWidget);
    expect(find.text('قال مش هياخده'), findsOneWidget);
    expect(find.text('لسه ما اتأكدتش'), findsNothing);
    expect(find.textContaining('آخر تحديث من موبايل والدك'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('جرعة عدّى وقتها من غير تأكيد → «لسه ما اتأكدتش» بالذهبي — مش «فاتت» ومفيش أحمر',
      (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 31, 8), 'pending'), // فاتت الساعة ٨
      event('Telfast', DateTime(2026, 8, 31, 20), 'pending'), // لسه جاية
    ]);
    await pumpScreen(tester);

    final flag = tester.widget<Text>(find.text('لسه ما اتأكدتش'));
    expect(flag.style?.color, F.gold);
    expect(find.textContaining('فاتت'), findsNothing, reason: 'بنبلّغ مش بنحكم');
    expect(find.textContaining('جاي'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });


  screenTest('جهاز الأب كتب «اتنست» → بنعرضها بالحرف بالذهبي، ومفيش أحمر',
      (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed'),
    ]);
    await pumpScreen(tester);

    final flag = tester.widget<Text>(find.text('اتنست — لسه ما اتأكدتش'));
    expect(flag.style?.color, F.gold);
    expectNoRedAndMinSize(tester);
  });

  screenTest('أسبوع فاضي → رسالة هادية والشاشة شغّالة', (tester) async {
    remote.next = snapshot(const []);
    await pumpScreen(tester);

    expect(find.textContaining('مفيش جرعات متسجّلة النهارده'), findsOneWidget,
        reason: 'مفيش حاجة النهارده ولا بكرة — الجملة القديمة هي الحقيقة');
    // سبع شَرطات بتتقري تطبيق بايظ — جملة واحدة مكانهم
    expect(find.text('—'), findsNothing);
    expect(find.text('لسه بدري. أول جرعة هتبان هنا أول ما تتسجّل'), findsOneWidget);
  });

  screenTest('أوفلاين وفيه بيانات محمّلة → الجملة فوق والبيانات القديمة لسه ظاهرة',
      (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken'),
    ]);
    await pumpScreen(tester);
    expect(find.textContaining('Concor'), findsWidgets);

    // السحب-للتحديث موصول (الودجت موجودة وonRefresh بتاعنا)
    expect(
      tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh,
      isNotNull,
    );

    // النت قطع — والرجوع للمقدمة (المحفّز التاني المتفق عليه) بيحدّث
    remote.failure = const CareCircleException(CareCircleFailure.offline);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(remote.calls, 2);
    expect(
      find.text('مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.'),
      findsOneWidget,
    );
    expect(find.textContaining('Concor'), findsWidgets, reason: 'القديم بيفضل');
  });

  screenTest('أوفلاين من غير أي بيانات → الجملة والشاشة مش بتقع', (tester) async {
    remote.failure = const CareCircleException(CareCircleFailure.offline);
    await pumpScreen(tester);

    expect(find.textContaining('مفيش نت'), findsOneWidget);
    expect(find.byType(CaregiverScreen), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('لوحة الأسبوع بتقول هي إيه، والكسر مكتوب بالكلام', (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 30, 8), 'taken', actedAt: DateTime(2026, 8, 30, 8, 2)),
      event('Telfast', DateTime(2026, 8, 30, 20), 'taken', actedAt: DateTime(2026, 8, 30, 20, 5)),
    ]);
    await pumpScreen(tester);

    // عنوان بيقول اللوحة دي إيه — «٤/١٦» لوحدها محدش كان بيعرف يقراها
    expect(find.text('آخر أسبوع'), findsOneWidget);
    expect(find.text('٢ من ٢ اتأكدت'), findsOneWidget);
    // **مفيش بيانات ≠ مفيش جرعات** — الشَرطة كانت بتخلط الاتنين
    expect(find.text('مفيش بيانات'), findsWidgets);
    expect(find.text('—'), findsNothing);
    expect(find.byKey(const ValueKey('week-strip')), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('أسبوع من غير ولا جرعة: جملة واحدة، مش جدول شَرطات', (tester) async {
    remote.next = snapshot([]);
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('week-empty')), findsOneWidget);
    expect(find.text('لسه بدري. أول جرعة هتبان هنا أول ما تتسجّل'), findsOneWidget);
    expect(find.byKey(const ValueKey('week-strip')), findsNothing);
    expect(find.text('مفيش بيانات'), findsNothing, reason: 'سبع مرات «مفيش بيانات» جدول فاضي بكلام');
  });

  screenTest('شريط الأسبوع: يوم فيه غير مؤكّد فايت بيتلوّن ذهبي', (tester) async {
    remote.next = snapshot([
      event('A', DateTime(2026, 8, 30, 8), 'taken'),
      event('B', DateTime(2026, 8, 30, 20), 'pending'), // امبارح، ما اتأكدتش
      event('C', DateTime(2026, 8, 29, 8), 'taken'),
    ]);
    await pumpScreen(tester);

    // امبارح: ١ من ٢ بالذهبي — أول امبارح: ١ من ١ أخضر
    final yesterday = tester.widget<Text>(find.text('١ من ٢ اتأكدت'));
    expect(yesterday.style?.color, F.gold);
    final dayBefore = tester.widget<Text>(find.text('١ من ١ اتأكدت'));
    expect(dayBefore.style?.color, F.greenDeep);
  });
  group('تنبيهات السيرفر — سجل اللي حصل، فوق الشاشة', () {
    screenTest('تنبيه واحد → بطاقة ذهبية فوق شريط الأسبوع بالسطرين', (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed')],
        alerts: [alert()],
      );
      await pumpScreen(tester);

      final header = find.text('⚠ والدك ما أكّدش جرعة Concor 5mg الساعة ٨:٠٠ ص');
      expect(header, findsOneWidget);
      expect(tester.widget<Text>(header).style?.color, F.gold);
      expect(find.text('السيرفر بلّغك النهارده ٩:٠٠ ص'), findsOneWidget);
      expect(find.textContaining('أكّدها بعدين'), findsNothing);

      // فوق لوحة الأسبوع — الأحدث الأول يعني أوّل حاجة في الصفحة
      expect(
        tester.getTopLeft(header).dy,
        lessThan(tester.getTopLeft(find.text('آخر أسبوع')).dy),
      );
      expectNoRedAndMinSize(tester);
    });

    // **الجرعة المقفولة مالهاش تنبيه — ولا واحدة فيهم** (جولة ٢٦).
    //
    // الجولة ٤.٢ج كانت بتسيب البطاقة وتزوّد «أكّدها بعدين ✓». العنوان
    // فضل «والدك ما أكّدش جرعة …» بالبنط العريض فوق جرعة اتاخدت، والابن
    // بيقرا الجملة مش الـ✓. القرار اتغيّر: مفيش بطاقة خالص.
    for (final state in ['taken', 'skipped', 'superseded']) {
      screenTest('حالة «$state» → مفيش بطاقة تنبيه خالص', (tester) async {
        remote.next = snapshot(
          [event('Concor 5mg', DateTime(2026, 8, 31, 8), state)],
          alerts: [alert(doseState: state)],
        );
        await pumpScreen(tester);

        expect(find.textContaining('والدك ما أكّدش جرعة'), findsNothing,
            reason: 'جرعة اتقفلت — تنبيه عنها كدب');
        expect(find.textContaining('أكّدها بعدين'), findsNothing);
        expect(find.text('تنبيهات'), findsNothing, reason: 'قسم فاضي ما يتعرضش');
        expectNoRedAndMinSize(tester);
      });
    }

    for (final state in ['pending', 'missed']) {
      screenTest('حالة «$state» → بطاقة ذهبية مفتوحة', (tester) async {
        remote.next = snapshot(
          [event('Concor 5mg', DateTime(2026, 8, 31, 8), state)],
          alerts: [alert(doseState: state)],
        );
        await pumpScreen(tester);

        final header = find.textContaining('والدك ما أكّدش جرعة');
        expect(header, findsOneWidget);
        expect(tester.widget<Text>(header).style?.color, F.gold);
        expect(find.text('تنبيهات'), findsOneWidget);
        expectNoRedAndMinSize(tester);
      });
    }

    screenTest('مقفولة ومفتوحة مع بعض → المفتوحة بس هي اللي بتبان', (tester) async {
      final taken = CaregiverAlert(
        uuid: 'esc-2',
        medicationName: 'Telfast',
        scheduledAt: DateTime(2026, 8, 31, 12),
        doseState: 'taken',
        deliveryStatus: 'sent',
        createdAt: DateTime(2026, 8, 31, 13),
        sentAt: DateTime(2026, 8, 31, 13),
      );
      remote.next = snapshot(
        [
          event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed'),
          event('Telfast', DateTime(2026, 8, 31, 12), 'taken'),
        ],
        alerts: [taken, alert()],
      );
      await pumpScreen(tester);

      expect(find.textContaining('جرعة Concor'), findsOneWidget);
      expect(find.textContaining('جرعة Telfast'), findsNothing,
          reason: 'اتاخدت — مفيش تنبيه عنها');
      expectNoRedAndMinSize(tester);
    });

    screenTest('الأقسام بترتيبها: تنبيهات ← آخر أسبوع ← جرعات النهارده ← الجديد ← أدويته',
        (tester) async {
      final base = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed')],
        alerts: [alert()],
      );
      remote.next = CaregiverSnapshot(
        patient: base.patient,
        medications: base.medications,
        events: base.events,
        alerts: base.alerts,
        lastUpdated: base.lastUpdated,
        // عشان قسم «الجديد» يبان أصلاً
        readings: [
          CaregiverReading(
            uuid: 'g1',
            valueMgDl: 128,
            measuredAt: DateTime(2026, 8, 31, 8),
            context: 'fasting',
            updatedAt: DateTime(2026, 8, 31, 8, 5),
          ),
        ],
      );
      await pumpScreen(tester);

      double y(String heading) => tester.getTopLeft(find.text(heading)).dy;
      // التنبيه المفتوح فوق: جرعة فايتة دلوقتي أعجل من أي حاجة تانية.
      expect(y('تنبيهات'), lessThan(y('آخر أسبوع')));
      expect(y('آخر أسبوع'), lessThan(y('جرعات النهارده')));
      // وجرعات اليوم قبل «الجديد» — ده اللي الابن فاتح الشاشة عشانه.
      expect(y('جرعات النهارده'), lessThan(y('الجديد')));
      // والأدوية آخر قسم: مرجع، مش حالة.
      expect(y('الجديد'), lessThan(y('أدويته')));
      expectNoRedAndMinSize(tester);
    });

    test('الحالات المفتوحة متعرّفة في مكان واحد، وشاملة', () {
      // القايمة اللي بتروح للاستعلام مشتقة من switch شامل على [DoseState]،
      // فحالة جديدة بتكسر الترجمة بدل ما تبقى تنبيه محدش قرره.
      expect(openDoseStateNames, ['pending', 'missed']);
      expect(isOpenDoseState(DoseState.pending), isTrue);
      expect(isOpenDoseState(DoseState.missed), isTrue);
      expect(isOpenDoseState(DoseState.taken), isFalse);
      expect(isOpenDoseState(DoseState.skipped), isFalse);
      expect(isOpenDoseState(DoseState.superseded), isFalse);
      // وكل حالة موجودة اتقرر فيها — مفيش واحدة اتنست
      expect(DoseState.values.length, 5);
    });

    test('الفلترة في الاستعلام نفسه — مش في الودجت', () {
      // الابن ما يشيلش صفوف عمره ما هيعرضها. الاختبار بيقرا المصدر لأن
      // الاستعلام ده ما بيتنفّذش في `flutter test`.
      final source = File('lib/data/care/supabase_caregiver_remote.dart').readAsStringSync();
      expect(source.contains("inFilter('dose_events.state', openDoseStateNames)"), isTrue);
    });

    screenTest('no_token → تنبيه داخل التطبيق، القناة محتاجة تفعيل — مش فشل ومش «بلّغك»',
        (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed')],
        alerts: [alert(deliveryStatus: 'no_token')],
      );
      await pumpScreen(tester);

      expect(find.text('تنبيه داخل التطبيق — إشعار الجهاز محتاج تفعيل'),
          findsOneWidget);
      expect(find.textContaining('السيرفر بلّغك'), findsNothing);
      expect(find.textContaining('ما وصلش'), findsNothing,
          reason: 'السيرفر قرّر وسجّل — ده مش فشل');
      expectNoRedAndMinSize(tester);
    });

    screenTest('failed → فشل حقيقي، بيتقال كده', (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed')],
        alerts: [alert(deliveryStatus: 'failed')],
      );
      await pumpScreen(tester);

      expect(find.text('السيرفر حاول يبلّغك النهارده ٩:٠٠ ص — الإشعار ما وصلش'),
          findsOneWidget);
      expect(find.textContaining('السيرفر بلّغك'), findsNothing);
      expectNoRedAndMinSize(tester);
    });

    screenTest('مفيش تنبيهات → مفيش بطاقة ولا جملة فاضية', (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken')],
      );
      await pumpScreen(tester);

      expect(find.textContaining('والدك ما أكّدش'), findsNothing);
      expect(find.textContaining('السيرفر'), findsNothing);
      expect(find.textContaining('تنبيه'), findsNothing);
    });
  });

  group('تذييل «آخر تحديث» — سكوت الموبايل نفسه خبر', () {
    screenTest('تحديث النهارده → رمادي هادي، مفيش ذهبي', (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken')],
        lastUpdated: now.subtract(const Duration(hours: 2)),
      );
      await pumpScreen(tester);

      final footer = tester.widget<Text>(
        find.textContaining('آخر تحديث من موبايل والدك'),
      );
      expect(footer.style?.color, F.mutedDark);
      expect(find.textContaining('عدّى يوم'), findsNothing);
      expectNoRedAndMinSize(tester);
    });

    screenTest('عدّى يوم من غير أي جديد → التذييل ذهبي وبيقول اطمن عليه',
        (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken')],
        lastUpdated: now.subtract(const Duration(hours: 30)),
      );
      await pumpScreen(tester);

      final footer = tester.widget<Text>(
        find.textContaining('آخر تحديث من موبايل والدك'),
      );
      expect(footer.style?.color, F.gold,
          reason: 'الذهبي معناه ده محتاج انتباهك — وأب ساكت يوم هو كده');
      expect(find.textContaining('اطمن عليه'), findsOneWidget);
      // بيولّع قبل ما تغطية السحابة (يومين) تخلص، مش بعدها
      expect(staleAfter, lessThan(const Duration(days: 2)));
      expectNoRedAndMinSize(tester);
    });

    screenTest('على حد الـ٢٤ ساعة بالظبط لسه هادي', (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken')],
        lastUpdated: now.subtract(staleAfter),
      );
      await pumpScreen(tester);

      final footer = tester.widget<Text>(
        find.textContaining('آخر تحديث من موبايل والدك'),
      );
      expect(footer.style?.color, F.mutedDark);
    });
  });

}
