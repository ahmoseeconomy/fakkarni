// «ملخص زيارة الطبيب» ما كانش فيه دكتور.
//
// الصف بقى شايل `doctor` و`place` و`happenedAt` بتاع الورقة من يوم ما
// شاشة المراجعة بقت بتقراهم. الشاشة اللي بتتفتح قدام الدكتور نفسه كانت
// بتتجاهل التلاتة: أدوية وقياسات وتحاليل من غير ولا اسم — يعني مش ملخص
// زيارة، ورقة أرقام.
//
// القاعدة اللي مابتتكسرش هنا: أرقام ووقائع وبس (D3.6). الاختبار بيتأكد إن
// اللي اتعرض هو اللي متكتوب، وإن الفاضي بيتقال بالكلام مش بيتخمّن.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/features/doctor/doctor_page_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep14 = DateTime(2026, 9, 14);
  RecordsRepository repo() => RecordsRepository(h.db);

  Future<int> add(
    RecordKind kind,
    String title,
    DateTime at, {
    String? doctor,
    String? place,
  }) =>
      repo().add(
        patientId: h.services.patientId,
        kind: kind,
        title: title,
        happenedAt: at,
        doctor: doctor,
        place: place,
      );

  screenTest('الملخص بيقول مين كتب الروشتة وفين وإمتى', (tester) async {
    await add(RecordKind.prescription, 'روشتة ٣ أدوية', DateTime(2026, 8, 20),
        doctor: 'د. هشام مام', place: 'مستشفى القصر العيني');

    await h.pump(tester, DoctorPageScreen(now: () => sep14));
    await settle(tester);

    expect(find.text('الزيارات والروشتات'), findsOneWidget);
    expect(find.text('د. هشام مام'), findsOneWidget, reason: 'اسم الدكتور هو الترويسة');
    expect(
      find.text('روشتة ٣ أدوية — مستشفى القصر العيني — ٢٠ أغسطس ٢٠٢٦'),
      findsOneWidget,
      reason: 'العيادة وتاريخ الورقة تحت اسمه',
    );
  });

  screenTest('زيارتين لنفس الدكتور بيتجمّعوا تحت اسم واحد', (tester) async {
    await add(RecordKind.visit, 'باطنة', DateTime(2026, 3, 2), doctor: 'د. هشام مام');
    await add(RecordKind.prescription, 'روشتة الضغط', DateTime(2026, 8, 20),
        doctor: ' د. هشام مام ', place: 'عيادة المهندسين');
    await add(RecordKind.visit, 'عظام', DateTime(2026, 7, 1), doctor: 'د. طارق سعيد');

    await h.pump(tester, DoctorPageScreen(now: () => sep14));
    await settle(tester);

    // المسافات الزيادة مش دكتور تاني
    expect(find.text('د. هشام مام'), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-group-د. هشام مام')), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-group-د. طارق سعيد')), findsOneWidget);
    expect(find.textContaining('روشتة الضغط'), findsOneWidget);
    expect(find.textContaining('باطنة'), findsOneWidget);
  });

  screenTest('ورقة من غير دكتور بتتقال بالكلام، وما بتتلزّقش بدكتور تاني', (tester) async {
    await add(RecordKind.visit, 'باطنة', DateTime(2026, 8, 1), doctor: 'د. هشام مام');
    await add(RecordKind.prescription, 'روشتة من الصيدلية', DateTime(2026, 8, 20));

    await h.pump(tester, DoctorPageScreen(now: () => sep14));
    await settle(tester);

    expect(find.text('من غير اسم دكتور على الورقة'), findsOneWidget);
    final unnamed = find.byKey(const ValueKey('doctor-group-مجهول'));
    expect(
      find.descendant(of: unnamed, matching: find.textContaining('روشتة من الصيدلية')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: unnamed, matching: find.textContaining('باطنة')),
      findsNothing,
      reason: 'زيارة دكتور معروف ما تدخلش تحت المجهول',
    );
  });

  screenTest('موبايل جديد → سطر واحد، مش خمس لوحات فاضية — والأسئلة و«اطبع» فاضلين', (tester) async {
    await h.pump(tester, DoctorPageScreen(now: () => sep14));
    await settle(tester);
    expect(find.text('للدكتور'), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-fresh')), findsOneWidget);
    expect(find.text('لما تصوّر روشتة أو تحليل من «ضيف» هيظهر هنا'), findsOneWidget);
    for (final head in ['الأدوية الحالية', 'الزيارات والروشتات', 'التحاليل الأخيرة']) {
      expect(find.text(head), findsNothing, reason: 'قسم فاضي ما بيتعرضش: $head');
    }
    expect(find.text('مفيش زيارات ولا روشتات متسجّلة'), findsNothing);
    expect(find.text('أسئلة العيلة'), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-export')), findsOneWidget);
  });

  screenTest('سجل اتمسح مش بيظهر في ملخص الدكتور', (tester) async {
    final id = await add(RecordKind.prescription, 'روشتة اتلغت', DateTime(2026, 8, 20),
        doctor: 'د. هشام مام');
    await repo().delete(id, now: sep14);

    await h.pump(tester, DoctorPageScreen(now: () => sep14));
    await settle(tester);

    expect(find.text('د. هشام مام'), findsNothing);
    expect(find.text('الزيارات والروشتات'), findsNothing, reason: 'ولا قسم فاضي');
    expect(find.byKey(const ValueKey('doctor-fresh')), findsOneWidget);
  });
}
