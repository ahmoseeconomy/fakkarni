import 'package:fakkarni_admin/data/admin_models.dart';
import 'package:fakkarni_admin/data/admin_service.dart';
import 'package:fakkarni_admin/screens/dashboard_screen.dart';
import 'package:fakkarni_admin/screens/widgets/accounts_table.dart';
import 'package:fakkarni_admin/screens/widgets/status_cues.dart';
import 'package:fakkarni_admin/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

final now = DateTime(2026, 9, 23, 12);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> open(WidgetTester tester, FakeAdminService service) async {
  tester.view.physicalSize = const Size(1600, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: F.light,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: DashboardScreen(service: service, onSignedOut: () {}, now: now),
    ),
  ));
  await settle(tester);
}

void main() {
  group('حالة الصف — دالة نقية', () {
    test('مفيش نبضة خالص = ساكت', () {
      expect(rowTone(account(), now), RowTone.silent);
    });

    test('نبضة من ٣ أيام = ساكت — الغياب أخطر من أي كود', () {
      expect(rowTone(account(seenAt: now.subtract(const Duration(days: 3))), now),
          RowTone.silent);
    });

    test('**والساكت قبل التنبيه**: تنبيه مفتوح على موبايل ساكت = ساكت', () {
      // اللي بيتقري الأول هو اللي يفسّر التاني: التنبيه ما اتقفلش لأن الموبايل
      // مش بيبعت، مش العكس.
      expect(rowTone(account(pending: 3), now), RowTone.silent);
    });

    test('تنبيه مفتوح = تنبيه، والنبضة دلوقتي', () {
      expect(rowTone(account(seenAt: now, pending: 1), now), RowTone.alarm);
    });

    test('بطارية مقيّدة = ملاحظة، مش إنذار', () {
      expect(rowTone(account(seenAt: now, battery: 'restricted'), now), RowTone.warn);
    });

    test('مدى التذكير خلص = ملاحظة', () {
      expect(rowTone(account(seenAt: now, horizonOk: false), now), RowTone.warn);
    });

    test('كله تمام = هادي', () {
      expect(rowTone(account(seenAt: now), now), RowTone.quiet);
    });
  });

  group('الترتيب والبحث — دوال نقية', () {
    final rows = [
      account(uuid: 'a', name: 'أحمد', pending: 0, missed: 5),
      account(uuid: 'b', name: 'باسم', pending: 3, missed: 1),
      account(uuid: 'c', name: 'أحمد التاني', pending: 1, missed: 0),
    ];

    test('التنبيهات المفتوحة — الأكتر الأول', () {
      final sorted = sortAccounts(rows, AccountSort.pendingEscalations, ascending: false);
      expect(sorted.map((a) => a.patientUuid), ['b', 'c', 'a']);
    });

    test('الجرعات اللي ما اتأكدتش', () {
      final sorted = sortAccounts(rows, AccountSort.missedDoses, ascending: false);
      expect(sorted.first.patientUuid, 'a');
    });

    test('**الساكت الأول** في ترتيب آخر مزامنة — null مش آخر القايمة', () {
      final list = [
        account(uuid: 'x', lastSyncAt: now),
        account(uuid: 'y'),
        account(uuid: 'z', lastSyncAt: now.subtract(const Duration(days: 2))),
      ];
      final sorted = sortAccounts(list, AccountSort.lastSync, ascending: true);
      expect(sorted.map((a) => a.patientUuid), ['y', 'z', 'x']);
    });

    test('**كل عمود بيبدأ من طرفه الوحش** — مش كلهم تنازلي', () {
      // «آخر مزامنة» تنازلي معناه الأحدث الأول: أهدى صف في الأسطول فوق.
      expect(defaultAscendingFor(AccountSort.lastSync), isTrue);
      expect(defaultAscendingFor(AccountSort.missedDoses), isFalse);
      expect(defaultAscendingFor(AccountSort.pendingEscalations), isFalse);
    });

    test('أسامي الأعمدة هي نفسها كلام ترويسات الجدول', () {
      expect(sortFieldLabel(AccountSort.lastSync), 'آخر مزامنة');
      expect(sortFieldLabel(AccountSort.missedDoses), 'ما اتأكدتش ٢٤ س');
      expect(sortFieldLabel(AccountSort.pendingEscalations), 'تنبيهات مفتوحة');
    });

    test('ووصف الاتجاه بيمشي مع نوع العمود', () {
      expect(sortDirectionLabel(AccountSort.lastSync, ascending: true),
          'الأقدم الأول');
      expect(sortDirectionLabel(AccountSort.lastSync, ascending: false),
          'الأحدث الأول');
      expect(sortDirectionLabel(AccountSort.missedDoses, ascending: false),
          'الأكتر الأول');
      expect(sortDirectionLabel(AccountSort.pendingEscalations, ascending: true),
          'الأقل الأول');
    });

    test('البحث بالاسم', () {
      expect(searchAccounts(rows, 'أحمد').map((a) => a.patientUuid), ['a', 'c']);
      expect(searchAccounts(rows, '  ').length, 3);
    });
  });

  testWidgets('الشريط بأرقام عربية والجدول بصفوفه', (tester) async {
    final service = FakeAdminService(
      counts_: const AdminCounts(
          totalPatients: 12, totalFollowers: 7, active7d: 9, batteryRestricted: 2),
      accounts_: [account(seenAt: now), account(uuid: 'p2', name: 'سعاد')],
    );

    await open(tester, service);

    expect(find.text('١٢'), findsOneWidget);
    expect(find.text('٧'), findsOneWidget);
    expect(find.text('٩'), findsOneWidget);
    expect(find.text('الحاج عاشور'), findsOneWidget);
    expect(find.text('سعاد'), findsOneWidget);
  });

  testWidgets('البحث بيصفّي الجدول', (tester) async {
    final service = FakeAdminService(
      accounts_: [account(seenAt: now), account(uuid: 'p2', name: 'سعاد')],
    );
    await open(tester, service);

    await tester.enterText(find.byType(TextField).first, 'سعاد');
    await settle(tester);

    // الجدول بس — حقل البحث نفسه فيه نفس الكلمة
    Finder inTable(String text) =>
        find.descendant(of: find.byType(DataTable), matching: find.text(text));
    expect(inTable('سعاد'), findsOneWidget);
    expect(inTable('الحاج عاشور'), findsNothing);
  });

  testWidgets('دوسة على صف بتفتح اللوحة الجانبية', (tester) async {
    final service = FakeAdminService(
      accounts_: [account(seenAt: now, followers: 1)],
      followers_: [
        AdminFollower(
            displayName: 'محمد',
            relation: 'son',
            status: 'accepted',
            linkedAt: DateTime(2026, 9, 1)),
      ],
      escalations_: [
        AdminEscalation(
          scheduledAt: DateTime(2026, 9, 22, 8),
          rung: 'caregiver',
          deliveryStatus: 'no_token',
          createdAt: DateTime(2026, 9, 22, 9),
        ),
      ],
    );
    await open(tester, service);

    await tester.tap(find.text('الحاج عاشور'));
    await settle(tester);

    expect(service.opened, ['p1']);
    expect(find.text('مين بيتابعه'), findsOneWidget);
    expect(find.text('محمد'), findsOneWidget);
    expect(find.textContaining('ابن'), findsWidgets);
    expect(find.text('مفيش توكن للجهاز'), findsOneWidget);
  });

  testWidgets('فشل الجلب بيقول جملة واحدة ومعاها «حاول تاني»', (tester) async {
    final service = FakeAdminService()
      ..countsFailure = const AdminException(AdminFailure.offline, 'boom');
    await open(tester, service);

    expect(find.text('مفيش نت. جرّب تاني لما يرجع.'), findsOneWidget);
    expect(find.text('حاول تاني'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('**مفيش اسم دوا في أي مكان** — الدوال ما بترجّعوش أصلاً',
      (tester) async {
    final service = FakeAdminService(accounts_: [account(seenAt: now)]);
    await open(tester, service);
    await tester.tap(find.text('الحاج عاشور'));
    await settle(tester);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data ?? '';
      expect(data.contains('Concor'), isFalse);
      expect(data.contains('mg'), isFalse);
    }
  });
}
