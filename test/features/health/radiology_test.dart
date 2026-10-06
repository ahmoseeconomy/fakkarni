// تقرير الأشعة (المرحلة ٦ — المالك 2A/3A): الاكتشاف جوّه «صوّر تقرير»،
// والخلاصة **منقولة بالحرف** («copied, not thought») — ومراجعة قبل الحفظ
// (القاعدة ٤)، والورقة عمرها ما بتضيع.
//
// اللقطة الأساسية على شكل تجربة المالك الحقيقية: تقرير رنين — خلاصة نصية،
// ولا رقم واحد.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/lab_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/db/app_database.dart' show RecordRow;
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/features/health/lab_report_screen.dart';
import 'package:fakkarni/features/health/radiology_report_screen.dart';
import 'package:fakkarni/features/health/scan_lab_screen.dart';
import 'package:fakkarni/features/health/usual_words.dart';

import '../scan/scan_test_support.dart';

class FakeLabReader implements LabReportReader {
  FakeLabReader(this.answer);

  final Future<LabReading> Function() answer;

  @override
  Future<LabReading> read(Uint8List image, {String mimeType = 'image/jpeg', List<Uint8List> morePages = const []}) =>
      answer();
}

ReadField<T> sure<T>(T v) => ReadField(value: v, confidence: 0.95);

Map<String, dynamic> field(dynamic value, [double confidence = 0.95]) =>
    {'value': value, 'confidence': confidence};

/// خلاصة بشكل تقرير رنين حقيقي — نص بالإنجليزي، فيه «normal» عمداً:
/// كلام **الورقة** مش كلامنا، وبيتعرض بالحرف (حارس النصايح على جملنا إحنا).
const mriConclusion =
    'Mild lumbar spondylosis with L4-L5 disc bulge.\nNo disc herniation. The spinal cord is normal.';

LabReading mriReading({ReadField<String>? conclusion, ReadField<DateTime>? date}) => LabReading(
      lab: sure('مركز الأشعة التخصصي'),
      date: date ?? sure(DateTime(2026, 9, 12)),
      lines: const [],
      reportKind: sure('imaging'),
      examName: sure('MRI Lumbar Spine'),
      conclusion: conclusion ?? sure(mriConclusion),
    );

void main() {
  final h = Harness();
  late Directory tmp;
  setUp(() async {
    await h.setUp();
    tmp = await Directory.systemTemp.createTemp('radiology');
  });
  tearDown(() async {
    await h.tearDown();
    await tmp.delete(recursive: true);
  });

  final sep15 = DateTime(2026, 9, 15, 8);

  AppServices withAttachments() {
    final s = h.services;
    return h.services = AppServices(
      db: s.db,
      patients: s.patients,
      medications: s.medications,
      events: s.events,
      scheduler: s.scheduler,
      patientId: s.patientId,
      attachments: DirectoryAttachmentStore(root: tmp),
    );
  }

  Future<List<RecordRow>> records() => h.db.select(h.db.records).get();

  Future<void> drainIo(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  group('القارئ النقي — الاكتشاف والنقل بالحرف', () {
    test('ورقة أشعة: النوع والفحص والخلاصة بالحرف — سطر بسطر وبحروفه الكبيرة', () {
      final reading = LabReading.fromJson({
        'reportKind': field('imaging'),
        'examName': field('MRI Lumbar Spine'),
        'conclusion': field(mriConclusion),
        'results': const [],
      }, now: sep15);
      expect(reading.isImaging, isTrue);
      expect(reading.conclusionText, mriConclusion, reason: 'نقل، مش تفكير — ولا حرف اتغيّر');
      expect(reading.lines, isEmpty);
    });

    test('نوع برّه القايمة المقفولة أو مش واثق = مش أشعة — سكّة المعمل زي ما هي', () {
      for (final kind in [field('scan'), field('imaging', 0.4), null]) {
        final reading = LabReading.fromJson({
          'reportKind': ?kind,
          'conclusion': field('X'),
          'results': const [],
        }, now: sep15);
        expect(reading.isImaging, isFalse, reason: '$kind');
      }
    });

    test('خلاصة مش واضحة = null — مفيش تخمين، والورقة بتتحفظ بصورتها (3A)', () {
      final unsure = LabReading.fromJson({
        'reportKind': field('imaging'),
        'conclusion': field('Mild lumbar spond?', 0.4),
        'results': const [],
      }, now: sep15);
      expect(unsure.conclusionText, isNull);
      final absent = LabReading.fromJson({
        'reportKind': field('imaging'),
        'conclusion': field(null),
        'results': const [],
      }, now: sep15);
      expect(absent.conclusionText, isNull);
    });

    test('عقد الأمانة مكتوب للموديل نفسه — الجمل بالحرف، زي تثبيتات النطاق', () {
      final instruction = GeminiLabReader.systemInstruction;
      for (final phrase in [
        'COPIED CHARACTER FOR CHARACTER',
        'transcription, never thought',
        'never rephrase it, never summarize it in your own words, never translate it, never add to it',
        'a missing conclusion is a correct answer; a reworded one is a wrong answer',
        "'imaging' for a radiology report",
      ]) {
        expect(instruction, contains(phrase), reason: phrase);
      }
      // والـschema فيه الحقول التلاتة مطلوبة — الغياب null مكتوبة مش حقل ساقط
      expect(labSchema['required'], containsAll(['reportKind', 'examName', 'conclusion']));
    });
  });

  group('السكّة — الاكتشاف جوّه «صوّر تقرير» (2A)', () {
    screenTest('قراية أشعة بتروح لمراجعة الأشعة — مش شاشة المعمل', (tester) async {
      withAttachments();
      final reader = FakeLabReader(() async => mriReading());
      await h.pump(tester, ScanLabScreen(reader: reader, pickImage: (_) async => Uint8List.fromList([1, 2, 3]), today: sep15));
      await settle(tester);
      await tester.tap(find.text('صوّر التقرير'));
      await tester.pump();
      await tester.tap(find.text('اقرا التقرير'));
      await settle(tester);
      expect(find.byType(RadiologyReportScreen), findsOneWidget);
      expect(find.byType(LabReportScreen), findsNothing);
      expect(await records(), isEmpty, reason: 'القاعدة ٤ — مراجعة قبل أي حفظ');
    });

    screenTest('قراية معمل عادية لسه بتروح لشاشة المعمل', (tester) async {
      withAttachments();
      final reader = FakeLabReader(() async => LabReading(
            lab: const ReadField.missing(),
            date: sure(DateTime(2026, 9, 12)),
            lines: const [],
            reportKind: sure('lab'),
          ));
      await h.pump(tester, ScanLabScreen(reader: reader, pickImage: (_) async => Uint8List.fromList([1, 2, 3]), today: sep15));
      await settle(tester);
      await tester.tap(find.text('صوّر التقرير'));
      await tester.pump();
      await tester.tap(find.text('اقرا التقرير'));
      await settle(tester);
      expect(find.byType(LabReportScreen), findsOneWidget);
      expect(find.byType(RadiologyReportScreen), findsNothing);
    });
  });

  group('مراجعة الأشعة — رنين بخلاصة نصية ولا رقم واحد', () {
    screenTest('الخلاصة بالحرف، والحفظ بعد «تمام» بس: kind أشعة + الصورة + الخلاصة في notes', (tester) async {
      withAttachments();
      await h.pump(
        tester,
        RadiologyReportScreen(reading: mriReading(), image: Uint8List.fromList([9, 9, 9]), today: sep15),
      );
      await settle(tester);

      expect(find.text('MRI Lumbar Spine'), findsOneWidget);
      final shown = tester.widget<Text>(find.byKey(const ValueKey('radiology-conclusion')));
      expect(shown.data, mriConclusion, reason: 'معروضة بالحرف — «normal» كلمة الورقة مش كلامنا');
      expect(find.byKey(const ValueKey('date-fallback')), findsNothing, reason: 'الورقة كاتبة تاريخ');
      // حارس النصايح على **جملنا إحنا** — الخلاصة المنقولة مستثناة زي
      // نص كارت المعلومة: كلام الورقة مش كلامنا.
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final text = t.data ?? '';
        if (text == mriConclusion) continue;
        for (final word in adviceWords) {
          final hit = RegExp(r'^[a-z]+$').hasMatch(word)
              ? RegExp('\\b$word\\b', caseSensitive: false).hasMatch(text)
              : text.contains(word);
          expect(hit, isFalse, reason: '«$word» في «$text»');
        }
      }
      expect(await records(), isEmpty, reason: 'القاعدة ٤ — ولا صف قبل «تمام»');

      await tester.ensureVisible(find.text('تمام، احفظه'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'تمام، احفظه'));
      await drainIo(tester);

      final record = (await records()).single;
      expect(record.kind, RecordKind.imaging);
      expect(record.title, 'MRI Lumbar Spine');
      expect(record.notes, mriConclusion, reason: 'اتحفظت بالحرف — ولا كلمة اتلمست');
      expect(record.place, 'مركز الأشعة التخصصي');
      expect(record.happenedAt, DateTime(2026, 9, 12), reason: 'تاريخ الورقة مش النهارده');
      expect(record.attachmentPath, isNotNull, reason: 'الورقة بصورتها');
      expect(await h.db.select(h.db.labResults).get(), isEmpty, reason: 'أشعة — مفيش سطور تحاليل');
    });

    screenTest('«صوّر تاني» بنفس الوزن وما بيكتبش حاجة', (tester) async {
      withAttachments();
      await h.pump(
        tester,
        RadiologyReportScreen(reading: mriReading(), image: Uint8List.fromList([9]), today: sep15),
      );
      await settle(tester);
      await tester.ensureVisible(find.text('صوّر تاني'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'صوّر تاني'));
      await drainIo(tester);
      expect(await records(), isEmpty);
    });

    screenTest('خلاصة مش واضحة: الورقة ما بتضيعش — «تمام» شغّالة وبتحفظ الصورة من غير خلاصة مخترعة', (tester) async {
      withAttachments();
      await h.pump(
        tester,
        RadiologyReportScreen(
          reading: mriReading(
            conclusion: const ReadField(value: 'Mild lum?', confidence: 0.4),
            date: const ReadField.missing(),
          ),
          image: Uint8List.fromList([7, 7]),
          today: sep15,
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('radiology-no-conclusion')), findsOneWidget);
      expect(find.textContaining('Mild lum'), findsNothing, reason: 'مش واضحة = مفيش — مش تخمين');
      expect(find.byKey(const ValueKey('date-fallback')), findsOneWidget,
          reason: 'من غير تاريخ واضح بنقولها بالذهبي قبل الدوسة');

      await tester.ensureVisible(find.text('تمام، احفظه'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'تمام، احفظه'));
      await drainIo(tester);
      final record = (await records()).single;
      expect(record.notes, isNull);
      expect(record.attachmentPath, isNotNull, reason: 'الصورة هي اللي اتوعدنا بيها');
      expect(record.happenedAt, DateTime(2026, 9, 15), reason: 'وقعت على النهارده زي شاشة المعمل');
    });

    screenTest('«عدّل» بياخد اللي الإنسان كتبه — وكلامه بيتحفظ زي ما هو', (tester) async {
      withAttachments();
      await h.pump(
        tester,
        RadiologyReportScreen(
          reading: mriReading(conclusion: const ReadField.missing()),
          image: Uint8List.fromList([7]),
          today: sep15,
        ),
      );
      await settle(tester);
      await tester.ensureVisible(find.text('عدّل'));
      await settle(tester);
      await tester.tap(find.text('عدّل'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('edit-conclusion')), 'الخلاصة زي ما كاتبها الدكتور');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      await settle(tester);
      expect(find.text('الخلاصة زي ما كاتبها الدكتور'), findsOneWidget);

      await tester.ensureVisible(find.text('تمام، احفظه'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'تمام، احفظه'));
      await drainIo(tester);
      expect((await records()).single.notes, 'الخلاصة زي ما كاتبها الدكتور');
    });
  });

  group('الورقة عمرها ما بتضيع — من شاشة المعمل الفاضية', () {
    screenTest('مفيش سطور ومش أشعة بثقة: «احفظها كورقة أشعة» موجودة وبتحفظ الصورة', (tester) async {
      withAttachments();
      await h.pump(
        tester,
        LabReportScreen(
          reading: LabReading(
            lab: const ReadField.missing(),
            date: const ReadField.missing(),
            lines: const [],
          ),
          image: Uint8List.fromList([5, 5]),
          today: sep15,
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('save-as-imaging')));
      await settle(tester);
      expect(find.byType(RadiologyReportScreen), findsOneWidget);

      await tester.ensureVisible(find.text('تمام، احفظه'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'تمام، احفظه'));
      await drainIo(tester);
      final record = (await records()).single;
      expect(record.kind, RecordKind.imaging);
      expect(record.title, 'تقرير أشعة', reason: 'من غير اسم فحص — مفيش اسم مخترع');
      expect(record.attachmentPath, isNotNull);
    });
  });
}
