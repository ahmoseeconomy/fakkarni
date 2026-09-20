import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/features/records/attachment_viewer.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/records/history_screen.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';

import '../scan/scan_test_support.dart';

/// كل سجل بيفضل شايل الصورة اللي جه منها، والدوسة عليه بتفتحها.
///
/// الصورة اللي بتتحفظ هي **اللي المنتقي داه** (٢٥٦٠)، مش النسخة المصغّرة
/// (١٦٠٠) اللي بتروح للموديل: الصغيرة للقراية، والكبيرة للعين البشرية.
void main() {
  final h = Harness();
  late Directory tmp;

  setUp(() async {
    await h.setUp();
    tmp = await Directory.systemTemp.createTemp('fakkarni_attach');
  });
  tearDown(() async {
    await h.tearDown();
    await tmp.delete(recursive: true);
  });

  final sep14 = DateTime(2026, 9, 14);

  /// **صورة حقيقية صالحة** (PNG ١×١) — مش بايتات عشوائية: العارض بيفكّها
  /// فعلاً، وبايتات مش صورة بتوقّف فكّ الترميز وتعلّق الاختبار. وهي كمان
  /// متميّزة كفاية عشان نتأكد إن **دي** اللي اتحفظت مش نسخة تانية.
  final picked = Uint8List.fromList(const [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
    0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
    120, 218, 99, 252, 207, 192, 80, 15, 0, 4, 133, 1, 128, 132, 169, 140, 33,
    0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
  ]);

  AppServices withStore() {
    final s = h.services;
    return h.services = AppServices(
      db: s.db,
      routines: s.routines,
      medications: s.medications,
      events: s.events,
      scheduler: s.scheduler,
      patientId: s.patientId,
      attachments: DirectoryAttachmentStore(root: tmp),
    );
  }

  /// **أي شغل ملفات حقيقي في جسم الاختبار لازم يبقى جوّه `runAsync`.**
  /// `testWidgets` بيشغّل الجسم في منطقة وقت مزيّف، فـ`await` على
  /// `File.writeAsBytes` برّه `runAsync` عمره ما بيرجع — الاختبار بيعلّق
  /// من غير خطأ ولا مهلة. (اتصاد هنا بالظبط.)
  Future<T> io<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// «الملف الصحي» بقى مداخل: الدوسة على المدخل بتفتح قايمة النوع، وهي
  /// اللي فيها صفوف السجلات بكل اللي بتعمله (مسح، صورة، متابعة).
  Future<void> openKind(WidgetTester tester, String kind) async {
    await tester.tap(find.byKey(ValueKey('kind-entry-$kind')));
    await settle(tester);
  }

  /// الحفظ كتابة ملف حقيقية — محتاجة وقت حقيقي برّه الساعة المزيّفة.
  Future<void> letFilesSettle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settle(tester);
  }

  group('الروشتة اللي اتأكدت بتفضل شايلة ورقتها', () {
    screenTest('«تمام، ظبّطهم» بيحفظ الصورة مع السجل — بنفس بايتات المنتقي', (tester) async {
      withStore();
      final records = RecordsRepository(h.db);
      await h.pump(
        tester,
        ReviewPrescriptionScreen(
          reading: PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]),
          routine: normalDay,
          image: picked,
          today: sep14,
          records: records,
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-review')));
      await letFilesSettle(tester);

      final record = (await records.all(h.services.patientId)).single;
      expect(record.kind, RecordKind.prescription);
      expect(record.attachmentPath, isNotNull);

      final file = await io(tester, () => DirectoryAttachmentStore(root: tmp).fileFor(record.attachmentPath!));
      expect(file, isNotNull);
      // **نفس البايتات**: لو حد بعت المصغّرة للحفظ ده بيقع.
      expect(await io(tester, () => file!.readAsBytes()), picked);
    });

    screenTest('من غير صورة (مفيش ورقة) السجل بيتكتب عادي من غير مرفق', (tester) async {
      withStore();
      final records = RecordsRepository(h.db);
      await h.pump(
        tester,
        ReviewPrescriptionScreen(
          reading: PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]),
          routine: normalDay,
          today: sep14,
          records: records,
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-review')));
      await letFilesSettle(tester);

      expect((await records.all(h.services.patientId)).single.attachmentPath, isNull);
      expect(Directory(tmp.path).listSync(), isEmpty, reason: 'ولا ملف اتكتب');
    });
  });

  group('الدوسة على السجل بتفتح ورقته', () {
    Future<int> seedWithPhoto(WidgetTester tester) async {
      withStore();
      final path = await io(tester, () => h.services.attachments.save(picked));
      return RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.lab,
        title: 'تقرير تحليل — CBC',
        happenedAt: sep14,
        attachmentPath: path,
      );
    }

    screenTest('سجل بصورة → عارض ملء الشاشة، بتقريب وبزرار قفل بكلمة', (tester) async {
      final id = await seedWithPhoto(tester);
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      await openKind(tester, 'lab');

      await tester.tap(find.byKey(ValueKey('record-photo-$id')));
      await letFilesSettle(tester);

      expect(find.byType(AttachmentViewerScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('attachment-zoom')), findsOneWidget);
      // زرار بكلمة، مش علامة لوحدها
      expect(find.text('اقفل'), findsOneWidget);
      expect(find.text('تقرير تحليل — CBC'), findsOneWidget, reason: 'اللي فاتح يعرف بيبصّ على إيه');

      await tester.tap(find.byKey(const ValueKey('attachment-close')));
      await settle(tester);
      expect(find.byType(AttachmentViewerScreen), findsNothing);
    });

    screenTest('نفس السلوك في «الحالات السابقة» — قايمتين لنفس السجلات', (tester) async {
      final id = await seedWithPhoto(tester);
      await h.pump(tester, HistoryScreen(today: sep14));
      await settle(tester);

      await tester.tap(find.byKey(ValueKey('history-photo-$id')));
      await letFilesSettle(tester);
      expect(find.byType(AttachmentViewerScreen), findsOneWidget);
    });

    screenTest('إدخال يدوي: مفيش مرفق، مفيش عارض، ومفيش إطار فاضي', (tester) async {
      withStore();
      final id = await RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.visit,
        title: 'باطنة',
        happenedAt: sep14,
      );
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      // المدخل نفسه بيبان بعدده، والدوسة بتفتح قايمته
      expect(find.byKey(const ValueKey('kind-entry-visit')), findsOneWidget);
      await openKind(tester, 'visit');

      expect(find.text('باطنة'), findsOneWidget);
      // ولا مفتاح فتح، ولا صورة، ولا مكان فاضي مستنيها
      expect(find.byKey(ValueKey('record-photo-$id')), findsNothing);
      expect(find.byType(Image), findsNothing);

      // والدوسة على الصف نفسه ما بتفتحش حاجة
      await tester.tap(find.text('باطنة'));
      await letFilesSettle(tester);
      expect(find.byType(AttachmentViewerScreen), findsNothing);
    });

    screenTest('الملف اتشال من برّه → الدوسة ما بتكسرش الشاشة', (tester) async {
      withStore();
      final id = await RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.lab,
        title: 'تقرير قديم',
        happenedAt: sep14,
        attachmentPath: 'attachments/مش-موجود.jpg',
      );
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      await openKind(tester, 'lab');

      await tester.tap(find.byKey(ValueKey('record-photo-$id')));
      await letFilesSettle(tester);
      expect(find.byType(AttachmentViewerScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('المسح بيمسح الصورة كمان', () {
    screenTest('«امسحه» بيسمّي الصورة في التأكيد، وبيشيل الملف من القرص', (tester) async {
      withStore();
      final store = DirectoryAttachmentStore(root: tmp);
      final path = await io(tester, () => store.save(picked));
      final id = await RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.lab,
        title: 'CBC',
        happenedAt: sep14,
        attachmentPath: path,
      );
      expect(await io(tester, () => store.fileFor(path)), isNotNull);

      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      await openKind(tester, 'lab');
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete')));
      await settle(tester);

      // الخسارة بتتقال قبل الدوسة، والصورة بتتسمّى بالاسم
      expect(find.text('هيتشال من الملف خالص، ومعاه الصورة المرفقة. مفيش رجوع.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('record-delete-confirm')));
      await letFilesSettle(tester);

      expect(await io(tester, () => store.fileFor(path)), isNull, reason: 'الملف راح من القرص');
      expect((await RecordsRepository(h.db).all(h.services.patientId)), isEmpty);
    });

    screenTest('تقرير تحليل: المسح بيشيل صورته هو كمان', (tester) async {
      withStore();
      final store = DirectoryAttachmentStore(root: tmp);
      final path = await io(tester, () => store.save(picked));
      final id = await LabResultsRepository(h.db).saveReport(
        patientId: h.services.patientId,
        happenedAt: sep14,
        attachmentPath: path,
        lines: const [ConfirmedLabLine(testName: 'HbA1c', value: 7.6, unit: '%')],
      );
      expect(id, isPositive);

      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      await openKind(tester, 'lab');
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete-confirm')));
      await letFilesSettle(tester);

      expect(await io(tester, () => store.fileFor(path)), isNull);
    });
  });
}
