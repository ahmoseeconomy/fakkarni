// «ضيف» و«ملفّي» (٢٩ سبتمبر ٢٠٢٦، طلب المالك):
// - «ضيف» مابقاش فيه «سجّل زيارة أو تحليل أو أشعة»؛ فيه «صوّر تقرير تحليل»
//   (بيتقري زي ما هو) و«صوّر تقرير أشعة» (بيتحفظ وبس).
// - التسجيل بالإيد جوّه «ملفّي»، والاستمارة فيها صورة الروشتة أو التقرير.
// - على زيارة / تحليل / أشعة موجودة: «ضيف صورة …» من الكاميرا أو من الصور،
//   صورة واحدة، والتانية بتاخد مكانها بعد سؤال.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/files/paper_share.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/features/medication/add_sheet.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/records/manual_entry_screen.dart';
import 'package:fakkarni/features/records/record_photo.dart';

import '../scan/scan_test_support.dart';

/// مخزن في الذاكرة — بيعدّ الحفظ والمسح.
class _MemoryStore implements AttachmentStore {
  final files = <String, Uint8List>{};
  final deleted = <String>[];
  var _n = 0;

  @override
  Future<String> save(Uint8List bytes, {String extension = 'jpg'}) async {
    final path = 'attachments/p${_n++}.$extension';
    files[path] = bytes;
    return path;
  }

  @override
  Future<File?> fileFor(String relativePath) async => null;

  @override
  Future<void> delete(String relativePath) async {
    files.remove(relativePath);
    deleted.add(relativePath);
  }
}

final _png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
final _png2 = Uint8List.fromList(img.encodePng(img.Image(width: 6, height: 6)));

void main() {
  final h = Harness();
  late _MemoryStore store;
  final picked = <ImageSource>[];
  var nextBytes = _png;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await h.setUp();
    store = _MemoryStore();
    final s = h.services;
    h.services = AppServices(
      db: s.db,
      patients: s.patients,
      medications: s.medications,
      events: s.events,
      scheduler: s.scheduler,
      patientId: s.patientId,
      attachments: store,
    );
    picked.clear();
    nextBytes = _png;
    pickRecordPhotoBytes = (source) async {
      picked.add(source);
      return nextBytes;
    };
  });
  tearDown(() async {
    pickRecordPhotoBytes = (_) async => null;
    await h.tearDown();
  });

  Future<List<RecordRow>> rows() => h.db.select(h.db.records).get();

  Future<int> addRecord(RecordKind kind, {String title = 'زيارة د. حسام'}) =>
      RecordsRepository(h.db).add(patientId: h.services.patientId, kind: kind, title: title, happenedAt: DateTime(2026, 9, 20));

  group('«ضيف»', () {
    test('القايمة: مفيش «سجّل زيارة أو تحليل أو أشعة»، وفيه تقرير التحليل والأشعة', () {
      expect(addSheetLabels, isNot(contains('سجّل زيارة أو تحليل أو أشعة')));
      expect(addSheetLabels, containsAll(['صوّر تقرير تحليل', 'صوّر تقرير أشعة']));
    });

    screenTest('«صوّر تقرير أشعة» ← «اختار من الصور» ← استمارة أشعة بالصورة ← سجل أشعة عليه الصورة', (tester) async {
      await h.pump(tester, AppShell(now: DateTime(2026, 9, 29, 10)));
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(find.text('سجّل زيارة أو تحليل أو أشعة'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('add-imaging-report')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-photo-gallery')));
      await settle(tester);
      expect(picked, [ImageSource.gallery]);
      expect(find.byType(ManualEntryScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('record-photo-picked')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('record-title')), 'أشعة صدر');
      await settle(tester);
      await tester.tap(find.textContaining('احفظ في'));
      await settle(tester);

      final saved = (await tester.runAsync(rows))!;
      expect(saved, hasLength(1));
      expect(saved.single.kind, RecordKind.imaging);
      expect(saved.single.attachmentPath, isNotNull);
      expect(store.files[saved.single.attachmentPath], _png);
    });

    screenTest('رجوع من غير صورة = مفيش استمارة ومفيش سجل', (tester) async {
      nextBytes = Uint8List(0);
      pickRecordPhotoBytes = (_) async => null;
      await h.pump(tester, AppShell(now: DateTime(2026, 9, 29, 10)));
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('add-imaging-report')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-photo-camera')));
      await settle(tester);
      expect(find.byType(ManualEntryScreen), findsNothing);
      expect((await tester.runAsync(rows))!, isEmpty);
    });
  });

  group('«ملفّي»', () {
    screenTest('«سجّل زيارة أو تحليل أو أشعة» بيفتح الاستمارة، والصورة من الكاميرا بتتحفظ على الزيارة', (tester) async {
      await h.pump(tester, HealthFileScreen(today: DateTime(2026, 9, 29)));
      await tester.tap(find.byKey(const ValueKey('papers-new')));
      await settle(tester);
      expect(find.byType(ManualEntryScreen), findsOneWidget);
      expect(find.text('صورة الروشتة (لو حابب)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-photo-add')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-photo-camera')));
      await settle(tester);
      expect(picked, [ImageSource.camera]);
      await tester.enterText(find.byKey(const ValueKey('record-title')), 'باطنة');
      await settle(tester);
      await tester.tap(find.textContaining('احفظ في'));
      await settle(tester);

      final saved = (await tester.runAsync(rows))!.single;
      expect(saved.kind, RecordKind.visit);
      expect(store.files[saved.attachmentPath], _png);
    });

    screenTest('الروشتة المكتوبة بالإيد مالهاش صورة من هنا — والصورة ما بتتحفظش لو النوع اتغيّر', (tester) async {
      await h.pump(tester, const ManualEntryScreen(kind: RecordKind.lab));
      expect(find.text('صورة التقرير (لو حابب)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-photo-add')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-photo-gallery')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('kind-prescription')));
      await settle(tester);
      expect(find.byKey(const ValueKey('record-photo-picked')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('record-title')), 'روشتة');
      await settle(tester);
      await tester.tap(find.textContaining('احفظ في'));
      await settle(tester);
      final saved = (await tester.runAsync(rows))!.single;
      expect(saved.kind, RecordKind.prescription);
      expect(saved.attachmentPath, isNull);
      expect(store.files, isEmpty, reason: 'مفيش ملف يتيم');
    });

    screenTest('«شيلها» بتشيل الصورة قبل الحفظ', (tester) async {
      await h.pump(tester, ManualEntryScreen(kind: RecordKind.imaging, initialPhoto: _png));
      expect(find.byKey(const ValueKey('record-photo-picked')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-photo-remove')));
      await settle(tester);
      expect(find.byKey(const ValueKey('record-photo-add')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('record-title')), 'أشعة');
      await settle(tester);
      await tester.tap(find.textContaining('احفظ في'));
      await settle(tester);
      expect((await tester.runAsync(rows))!.single.attachmentPath, isNull);
    });
  });

  group('صورة على سجل موجود', () {
    screenTest('زيارة: «ضيف صورة الروشتة»، والتانية بتسأل وبتمسح القديمة', (tester) async {
      final id = (await tester.runAsync(() => addRecord(RecordKind.visit)))!;
      await h.pump(tester, HealthFileScreen(today: DateTime(2026, 9, 29)));

      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      expect(find.text('ضيف صورة الروشتة'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-attach-photo')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-photo-gallery')));
      await settle(tester);
      final first = (await tester.runAsync(rows))!.single.attachmentPath;
      expect(store.files[first], _png);

      nextBytes = _png2;
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      expect(find.text('غيّر صورة الروشتة'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-attach-photo')));
      await settle(tester);
      expect(find.text('تغيّر صورة الروشتة؟'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-photo-replace')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-photo-camera')));
      await settle(tester);

      final second = (await tester.runAsync(rows))!.single.attachmentPath;
      expect(second, isNot(first));
      expect(store.files[second], _png2);
      expect(store.deleted, [first], reason: 'صورة واحدة لكل سجل — القديمة بتتمسح');
    });

    screenTest('«لأ، سيبها» ما بيغيّرش حاجة', (tester) async {
      final id = (await tester.runAsync(() async {
        final id = await addRecord(RecordKind.imaging, title: 'أشعة ركبة');
        await RecordsRepository(h.db).setAttachment(id, 'attachments/old.jpg');
        return id;
      }))!;
      await h.pump(tester, HealthFileScreen(today: DateTime(2026, 9, 29)));
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      expect(find.text('غيّر صورة التقرير'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-attach-photo')));
      await settle(tester);
      await tester.tap(find.text('لأ، سيبها'));
      await settle(tester);
      expect(picked, isEmpty);
      expect((await tester.runAsync(rows))!.single.attachmentPath, 'attachments/old.jpg');
      expect(store.deleted, isEmpty);
    });

    screenTest('تحليل: «ضيف صورة التقرير»؛ روشتة: مفيش مدخل صورة', (tester) async {
      final lab = (await tester.runAsync(() => addRecord(RecordKind.lab, title: 'صورة دم')))!;
      final rx = (await tester.runAsync(() => addRecord(RecordKind.prescription, title: 'روشتة')))!;
      await h.pump(tester, HealthFileScreen(today: DateTime(2026, 9, 29)));
      await tester.tap(find.byKey(ValueKey('record-options-$lab')));
      await settle(tester);
      expect(find.text('ضيف صورة التقرير'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('record-options-$rx')));
      await settle(tester);
      expect(find.byKey(const ValueKey('record-attach-photo')), findsNothing);
    });
  });

  group('المستودع', () {
    test('setAttachment بيكتب المسار وبيمسح القديم بعد الصف، وسجل ممسوح مالوش صورة', () async {
      final repo = RecordsRepository(h.db);
      final id = await addRecord(RecordKind.visit);
      final uuid = await repo.setAttachment(id, 'a/1.jpg', attachments: store);
      expect(uuid, isNotNull);
      await repo.setAttachment(id, 'a/2.jpg', attachments: store);
      expect(store.deleted, ['a/1.jpg']);
      expect((await rows()).single.attachmentPath, 'a/2.jpg');

      await repo.delete(id, attachments: store);
      expect(await repo.setAttachment(id, 'a/3.jpg', attachments: store), isNull);
      expect(() => repo.setAttachment(id, '  '), throwsArgumentError);
    });

    test('forgetUpload: الصورة اللي اتغيّرت بتترفع تاني للممرض', () async {
      SharedPreferences.setMockInitialValues({
        PaperShareService.uploadedKey: ['r1', 'r2'],
      });
      await PaperShareService.forgetUpload('r1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(PaperShareService.uploadedKey), ['r2']);
    });
  });

  test('الممرض: «ضيف» مافيهوش تسجيل ورقة — «ورقة جديدة» في «ملفّي» عنده', () {
    final src = File('lib/features/nurse/nurse_add_sheet.dart').readAsStringSync();
    expect(src, isNot(contains('nurse-add-record')));
    expect(File('lib/features/nurse/nurse_records_screen.dart').readAsStringSync(), contains('nurse-new-record'));
  });

  // الطبقة: اسم الصورة على كل نوع
  test('recordPhotoWord', () {
    expect(recordPhotoWord(RecordKind.visit), 'صورة الروشتة');
    expect(recordPhotoWord(RecordKind.lab), 'صورة التقرير');
    expect(recordPhotoWord(RecordKind.imaging), 'صورة التقرير');
    expect(recordPhotoWord(RecordKind.prescription), isNull);
    expect(recordPhotoWord(RecordKind.booking), isNull);
  });
}
