// «ميعاد جديد» بقى فيه تخصص الدكتور (طلب المالك، ٢٩ سبتمبر ٢٠٢٦): اختياري،
// من الشخص أو من «كلّمني» أو من «القريب مني» لو المصدر قال واحد بس —
// وبيتحفظ في اسم الزيارة (قرار المالك: مفيش عمود ومفيش هجرة).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/domain/places/specialty.dart';
import 'package:fakkarni/features/nearby/nearby_screen.dart';
import 'package:fakkarni/features/records/book_appointment.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final today = DateTime(2026, 9, 29);

  Future<List<RecordRow>> rows(WidgetTester tester) async =>
      (await tester.runAsync(() => h.db.select(h.db.records).get()))!;

  Future<void> openNew(WidgetTester tester) async {
    await h.pump(tester, HealthFileScreen(today: today));
    await tester.ensureVisible(find.byKey(const ValueKey('new-appointment')));
    await tester.tap(find.byKey(const ValueKey('new-appointment')));
    await settle(tester);
  }

  Future<void> pickSpecialty(WidgetTester tester, Specialty sp) async {
    await tester.ensureVisible(find.byKey(const ValueKey('new-appt-specialty')));
    await tester.tap(find.byKey(const ValueKey('new-appt-specialty')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('specialty-${sp.name}')));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('new-appt-save')));
    await tester.tap(find.byKey(const ValueKey('new-appt-save')));
    await settle(tester);
  }

  screenTest('تخصص من غير اسم ← «دكتور باطنة»', (tester) async {
    await openNew(tester);
    expect(find.text('التخصص (لو حابب)'), findsOneWidget);
    await pickSpecialty(tester, Specialty.internal);
    expect(find.text('التخصص: باطنة'), findsOneWidget);
    await save(tester);
    expect((await rows(tester)).single.title, 'دكتور باطنة');
  });

  screenTest('اسم + تخصص ← «د. حسن — باطنة»', (tester) async {
    await openNew(tester);
    await tester.enterText(find.byKey(const ValueKey('new-appt-name')), 'د. حسن');
    await settle(tester);
    await pickSpecialty(tester, Specialty.internal);
    await save(tester);
    expect((await rows(tester)).single.title, 'د. حسن — باطنة');
  });

  screenTest('«من غير تخصص» بيشيله، والمعمل مالوش تخصص', (tester) async {
    await openNew(tester);
    await pickSpecialty(tester, Specialty.eyes);
    await tester.tap(find.byKey(const ValueKey('new-appt-specialty')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('specialty-none')));
    await settle(tester);
    expect(find.text('التخصص (لو حابب)'), findsOneWidget);

    await pickSpecialty(tester, Specialty.eyes);
    await tester.tap(find.byKey(const ValueKey('new-appt-lab')));
    await settle(tester);
    expect(find.byKey(const ValueKey('new-appt-specialty')), findsNothing);
    await save(tester);
    expect((await rows(tester)).single.title, 'تحليل', reason: 'تخصص الدكتور ما بيدخلش على المعمل');
  });

  screenTest('من غير اختيار = مفيش تخصص (مش بنخمّن)', (tester) async {
    await openNew(tester);
    await save(tester);
    expect((await rows(tester)).single.title, 'زيارة دكتور');
  });

  group('متعبّي من برّه', () {
    Future<void> pumpOpener(WidgetTester tester, Future<Object?> Function(BuildContext) open) async {
      await h.pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(key: const ValueKey('open'), onPressed: () => open(c), child: const Text('افتح')),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await settle(tester);
    }

    screenTest('«كلّمني» (دكتور بطنه): الخانة متعبّية باطنة، والدكتور الحقيقي بيتسجّل جنبها', (tester) async {
      await pumpOpener(
        tester,
        (c) => openBookAppointment(c, today: today, name: 'د. حسن', doctor: 'د. حسن', specialty: Specialty.internal),
      );
      expect(find.text('التخصص: باطنة'), findsOneWidget);
      await save(tester);
      final r = (await rows(tester)).single;
      expect(r.title, 'د. حسن — باطنة');
      expect(r.doctor, 'د. حسن', reason: 'التخصص جنب الاسم ما بيلغيش إن ده دكتوره');
    });

    Place doctor(String name, {String? speciality}) =>
        Place(id: 'd1', kind: PlaceKind.doctor, lat: 30, lon: 31, name: name, speciality: speciality);

    screenTest('«القريب مني»: تخصص واحد من المصدر ← متعبّي', (tester) async {
      await pumpOpener(tester, (c) => bookFromPlace(c, doctor('عيادة د. سامي', speciality: 'ophthalmology'), today));
      expect(find.text('التخصص: عيون'), findsOneWidget);
    });

    screenTest('«القريب مني»: أكتر من تخصص أو مفيش ← فاضي', (tester) async {
      await pumpOpener(tester, (c) => bookFromPlace(c, doctor('عيادة د. سامي', speciality: 'ophthalmology;dentistry'), today));
      expect(find.text('التخصص (لو حابب)'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      await pumpOpener(tester, (c) => bookFromPlace(c, doctor('عيادة د. سامي'), today));
      expect(find.text('التخصص (لو حابب)'), findsOneWidget);
    });
  });
}
