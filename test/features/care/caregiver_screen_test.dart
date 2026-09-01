import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
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

CaregiverSnapshot snapshot(List<CaregiverDoseEvent> events) => CaregiverSnapshot(
      patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
      medications: const [
        CaregiverMedication(uuid: 'm1', name: 'Concor 5mg', amountLabel: 'قرص واحد'),
      ],
      events: events,
      lastUpdated: DateTime(2026, 8, 31, 13, 30),
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

  screenTest('أسبوع فاضي → رسالة هادية والشاشة شغّالة', (tester) async {
    remote.next = snapshot(const []);
    await pumpScreen(tester);

    expect(find.textContaining('مفيش جرعات متسجّلة النهارده'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(7), reason: 'شريط الأسبوع من غير عدّ');
  });

  screenTest('أوفلاين وفيه بيانات محمّلة → الجملة فوق والبيانات القديمة لسه ظاهرة',
      (tester) async {
    remote.next = snapshot([
      event('Concor 5mg', DateTime(2026, 8, 31, 8), 'taken'),
    ]);
    await pumpScreen(tester);
    expect(find.textContaining('Concor'), findsOneWidget);

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
    expect(find.textContaining('Concor'), findsOneWidget, reason: 'القديم بيفضل');
  });

  screenTest('أوفلاين من غير أي بيانات → الجملة والشاشة مش بتقع', (tester) async {
    remote.failure = const CareCircleException(CareCircleFailure.offline);
    await pumpScreen(tester);

    expect(find.textContaining('مفيش نت'), findsOneWidget);
    expect(find.byType(CaregiverScreen), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('شريط الأسبوع: يوم فيه غير مؤكّد فايت بيتلوّن ذهبي', (tester) async {
    remote.next = snapshot([
      event('A', DateTime(2026, 8, 30, 8), 'taken'),
      event('B', DateTime(2026, 8, 30, 20), 'pending'), // امبارح، ما اتأكدتش
      event('C', DateTime(2026, 8, 29, 8), 'taken'),
    ]);
    await pumpScreen(tester);

    // امبارح: ١/٢ بالذهبي — أول امبارح: ١/١ أخضر
    final yesterday = tester.widget<Text>(find.text('١/٢'));
    expect(yesterday.style?.color, F.gold);
    final dayBefore = tester.widget<Text>(find.text('١/١'));
    expect(dayBefore.style?.color, F.greenDeep);
  });
}
