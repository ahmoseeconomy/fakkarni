import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/features/care/caregiver_screen.dart';

import '../scan/scan_test_support.dart' show settle, screenTest, expectCaregiverDensity;

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
    // **قسم بكرة اتشال خالص** (طلب المالك): الشاشة بقت عن النهارده وبس.
    // اللي فاضل هو الجملة اللي فوق — بتقول «ليه الشاشة فاضية» وبتسمّي
    // أول جرعة جاية، من غير ما تعرض جدول بكرة.
    expect(find.text('٧:٠٠ ص'), findsNothing, reason: 'صف بكرة اتشال');
    expect(find.text('٩:٠٠ م'), findsNothing);
    expect(find.text('جاية'), findsNothing, reason: 'مفيش جرعات النهارده');
    expect(find.text('لسه ما اتأكدتش'), findsNothing, reason: 'بكرة مش متأخرة');

    expect(find.text('—'), findsNothing);

    // قراية بس
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('عدّل'), findsNothing);
    expectCaregiverDensity(tester);
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
    expect(find.textContaining('Glucophage'), findsNothing);
    expect(find.textContaining('Telfast'), findsNothing);
  });

  screenTest('النهارده فاضي وبكرة فيها → الجملة اللي بتقول اللي جاي', (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 29, 8), 'taken', actedAt: DateTime(2026, 8, 29, 8, 2)),
      event('Concor 5mg', DateTime(2026, 9, 1, 8), 'pending'),
    ]);
    await pumpScreen(tester);

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
    expectCaregiverDensity(tester);
  });

  screenTest('جرعة عدّى وقتها من غير تأكيد → «لسه ما اتأكدتش» بالذهبي — مش «فاتت» ومفيش أحمر',
      (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 31, 8), 'pending'), // فاتت الساعة ٨
      event('Telfast', DateTime(2026, 8, 31, 20), 'pending'), // لسه جاية
    ]);
    await pumpScreen(tester);

    // **الذهبي على العلامة، مش على النص** (جولة إعادة تصميم شاشة الابن):
    // ذهبي على كارت نهاري ٢٫٠٦:١، فأهم سطر كان أصعب واحد يتقرا. الكلمة
    // بقت بلون المتن، والذهبي على أيقونة ⚠ وعلى حد الصف الجانبي.
    final flag = find.text('لسه ما اتأكدتش');
    expect(tester.widget<Text>(flag).style?.color, F.ink);
    final mark = find.ancestor(of: flag, matching: find.byType(Row)).first;
    final icon = tester.widget<Icon>(
        find.descendant(of: mark, matching: find.byIcon(Icons.error_outline)));
    expect(icon.color, F.gold);
    expect(find.textContaining('فاتت'), findsNothing, reason: 'بنبلّغ مش بنحكم');
    expect(find.textContaining('جاي'), findsOneWidget);
    expectCaregiverDensity(tester);
  });


  screenTest('جهاز الأب كتب «اتنست» → بنعرضها بالحرف بالذهبي، ومفيش أحمر',
      (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed'),
    ]);
    await pumpScreen(tester);

    // **الذهبي على العلامة، مش على النص** (جولة إعادة تصميم شاشة الابن):
    // ذهبي على كارت نهاري ٢٫٠٦:١، فأهم سطر كان أصعب واحد يتقرا. الكلمة
    // بقت بلون المتن، والذهبي على أيقونة ⚠ وعلى حد الصف الجانبي.
    final flag = find.text('اتنست — لسه ما اتأكدتش');
    expect(tester.widget<Text>(flag).style?.color, F.ink);
    final mark = find.ancestor(of: flag, matching: find.byType(Row)).first;
    final icon = tester.widget<Icon>(
        find.descendant(of: mark, matching: find.byIcon(Icons.error_outline)));
    expect(icon.color, F.gold);
    expectCaregiverDensity(tester);
  });

  screenTest('مفيش جرعات خالص → رسالة هادية والشاشة شغّالة', (tester) async {
    remote.next = snapshot(const []);
    await pumpScreen(tester);

    expect(find.textContaining('مفيش جرعات متسجّلة النهارده'), findsOneWidget,
        reason: 'مفيش حاجة النهارده ولا بكرة — الجملة القديمة هي الحقيقة');
    expect(find.text('—'), findsNothing);
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
    expectCaregiverDensity(tester);
  });

  group('تنبيهات السيرفر — سجل اللي حصل، فوق الشاشة', () {
    screenTest('تنبيه واحد → بطاقة ذهبية فوق شريط الأسبوع بالسطرين', (tester) async {
      remote.next = snapshot(
        [event('Concor 5mg', DateTime(2026, 8, 31, 8), 'missed')],
        alerts: [alert()],
      );
      await pumpScreen(tester);

      final header = find.text('والدك ما أكّدش جرعة Concor 5mg الساعة ٨:٠٠ ص');
      expect(header, findsOneWidget);
      // **الانتباه في العلامة والحد، مش في لون النص** (جولة إعادة تصميم
      // شاشة الابن). العنوان كان `F.gold` — ٢٫٠٦:١ على كارت نهاري، يعني
      // أهم سطر على الشاشة كان أصعب واحد يتقرا. دلوقتي نص بلون النص،
      // والذهبي على أيقونة ⚠ وحد الكارت الجانبي وعنوان القسم — تلاتة
      // بتوصل كمان لحد مش بيفرّق الألوان.
      expect(tester.widget<Text>(header).style?.color, F.ink);
      expect(
        find.descendant(
          of: find.ancestor(of: header, matching: find.byType(Row)).first,
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
      );
      expect(find.text('السيرفر بلّغك النهارده ٩:٠٠ ص'), findsOneWidget);
      expect(find.textContaining('أكّدها بعدين'), findsNothing);

      // فوق لوحة الأسبوع — الأحدث الأول يعني أوّل حاجة في الصفحة
      expect(
        tester.getTopLeft(header).dy,
        lessThan(tester.getTopLeft(find.text('ما اتأكدتش')).dy),
      );
      expectCaregiverDensity(tester);
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
        expectCaregiverDensity(tester);
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
        // الانتباه في العلامة والحد مش في لون النص — شوف الاختبار اللي فوق
        expect(tester.widget<Text>(header).style?.color, F.ink);
        expect(
          find.descendant(
            of: find.ancestor(of: header, matching: find.byType(Row)).first,
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );
        expect(find.text('تنبيهات'), findsOneWidget);
        expectCaregiverDensity(tester);
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
      expectCaregiverDensity(tester);
    });

    screenTest('الأقسام بترتيبها: تنبيهات ← ما اتأكدتش ← الجديد (والأدوية بقت تبويب)',
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
      // التنبيه المفتوح فوق: جرعة محدش أكّدها دلوقتي أعجل من أي حاجة تانية.
      expect(y('تنبيهات'), lessThan(y('ما اتأكدتش')));
      // وجرعات اليوم قبل «الجديد» — ده اللي الابن فاتح الشاشة عشانه.
      expect(y('ما اتأكدتش'), lessThan(y('الجديد')));
      // **والأدوية مابقتش قسم هنا خالص** — بقت تبويب في الدوك (جولة ٢٩).
      // باب واحد للأوضة: القسم اتشال، ما اتنسخش.
      expect(find.text('أدويته'), findsNothing);
      expectCaregiverDensity(tester);
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
      expectCaregiverDensity(tester);
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
      expectCaregiverDensity(tester);
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
      expectCaregiverDensity(tester);
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
      expectCaregiverDensity(tester);
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
