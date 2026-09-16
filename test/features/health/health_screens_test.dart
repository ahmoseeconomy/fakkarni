import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/lab_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/widgets/primitives.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/files/attachment_store.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/features/health/glucose_screen.dart';
import 'package:fakkarni/features/health/lab_report_screen.dart';
import 'package:fakkarni/features/health/scan_lab_screen.dart';
import 'package:fakkarni/features/health/usual_words.dart';

import '../scan/scan_test_support.dart';

class FakeLabReader implements LabReportReader {
  FakeLabReader(this.answer);

  final Future<LabReading> Function() answer;
  int calls = 0;

  @override
  Future<LabReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) {
    calls++;
    return answer();
  }
}

ReadField<T> sure<T>(T v) => ReadField(value: v, confidence: 0.95);

LabLine line(String test, double? value, String? unit, {bool unsure = false}) => LabLine(
      test: sure(test),
      value: value == null
          ? const ReadField.missing()
          : ReadField(value: value, confidence: unsure ? 0.4 : 0.95),
      unit: unit == null ? const ReadField.missing() : sure(unit),
    );

/// كل النصوص المرسومة — Text وRichText.
List<String> renderedTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
      for (final r in tester.widgetList<RichText>(find.byType(RichText))) r.text.toPlainText(),
    ];

void expectNoAdvice(WidgetTester tester) {
  for (final text in renderedTexts(tester)) {
    for (final word in adviceWords) {
      final hit = RegExp(r'^[a-z]+$').hasMatch(word)
          ? RegExp('\\b$word\\b', caseSensitive: false).hasMatch(text)
          : text.contains(word);
      expect(hit, isFalse, reason: 'كلمة نصيحة/حكم «$word» في: $text');
    }
  }
}

void main() {
  final h = Harness();
  late Directory tmp;
  setUp(() async {
    await h.setUp();
    tmp = await Directory.systemTemp.createTemp('fakkarni_lab');
  });
  tearDown(() async {
    await h.tearDown();
    await tmp.delete(recursive: true);
  });

  final sep15 = DateTime(2026, 9, 15, 8);

  AppServices withLab({LabReportReader? reader}) {
    final s = h.services;
    return h.services = AppServices(
      db: s.db,
      routines: s.routines,
      medications: s.medications,
      events: s.events,
      scheduler: s.scheduler,
      patientId: s.patientId,
      labReader: reader,
      attachments: DirectoryAttachmentStore(root: tmp),
    );
  }

  Future<void> seedFasting(List<int> values) async {
    final repo = ReadingsRepository(h.db);
    for (final (i, v) in values.indexed) {
      await repo.add(
        patientId: h.services.patientId,
        valueMgDl: v,
        context: GlucoseContext.fasting,
        measuredAt: DateTime(2026, 9, 1 + i, 7),
      );
    }
  }

  group('قياس السكر (المخطط ١٤)', () {
    screenTest('أول قياس: الرقم من غير أي تعليم، و«لسه ما عندناش قياسات كفاية نعرف المعتاد ليك»', (tester) async {
      await h.pump(tester, GlucoseScreen(now: () => sep15));
      await settle(tester);
      expect(find.textContaining('لسه مفيش قياسات'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('glucose-value')), '152');
      await settle(tester);
      final save = find.widgetWithText(FilledButton, 'احفظ القراءة');
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'لسه ما اختارش صايم ولا بعد الأكل');

      await tester.tap(find.byKey(const ValueKey('glucose-fasting')));
      await settle(tester);
      await tester.tap(save);
      await settle(tester);

      expect(tester.widget<Text>(find.byKey(const ValueKey('glucose-latest'))).data, '١٥٢');
      expect(tester.widget<Text>(find.byKey(const ValueKey('glucose-usual'))).data, notEnoughForUsual);
      final card = tester.widget<FCard>(find.ancestor(of: find.byKey(const ValueKey('glucose-latest')), matching: find.byType(FCard)));
      expect(card.tone, FCardTone.plain, reason: 'مفيش حاجة نقارن بيها — مفيش تعليم');
      expectNoAdvice(tester);
      expectNoRedAndMinSize(tester);
    });

    screenTest('بعد ٥ قياسات صايم: المقارنة بقياساته هو، رقم وفرق، والكارت ذهبي من غير أحمر', (tester) async {
      await seedFasting([118, 110, 131, 122, 125]);
      await h.pump(tester, GlucoseScreen(now: () => sep15));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('glucose-value')), '152');
      await tester.tap(find.byKey(const ValueKey('glucose-fasting')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'احفظ القراءة'));
      await settle(tester);

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('glucose-usual'))).data,
        'أعلى من أعلى قياس معتاد ليك (١٣١) بـ ٢١',
      );
      final card = tester.widget<FCard>(find.ancestor(of: find.byKey(const ValueKey('glucose-latest')), matching: find.byType(FCard)));
      expect(card.tone, FCardTone.attention);
      expectNoAdvice(tester);
      expectNoRedAndMinSize(tester);
    });

    screenTest('قياسات «بعد الأكل» ما بتحسبش في المعتاد بتاع الصايم', (tester) async {
      await seedFasting([118, 110, 131, 122]);
      final repo = ReadingsRepository(h.db);
      for (final d in [5, 6, 7]) {
        await repo.add(
          patientId: h.services.patientId,
          valueMgDl: 190,
          context: GlucoseContext.afterMeal,
          measuredAt: DateTime(2026, 9, d, 14),
        );
      }
      await repo.add(patientId: h.services.patientId, valueMgDl: 140, context: GlucoseContext.fasting, measuredAt: sep15);
      await h.pump(tester, GlucoseScreen(now: () => sep15));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('glucose-usual'))).data, notEnoughForUsual);
    });

    screenTest('رقم برّه ٢٠–٦٠٠ → جملة هادية والحفظ مقفول', (tester) async {
      await h.pump(tester, GlucoseScreen(now: () => sep15));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('glucose-value')), '1520');
      await tester.tap(find.byKey(const ValueKey('glucose-fasting')));
      await settle(tester);
      expect(find.textContaining('برّه اللي أجهزة القياس بتقراه'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'احفظ القراءة')).onPressed, isNull);
      expectNoRedAndMinSize(tester);
    });
  });

  group('تصوير التقرير (المخطط ٧) — أمانة الكشف', () {
    screenTest('وإحنا مستنيين الرد مفيش ولا سطر — بس «بيقرا التقرير…»، والكشف على اللي رجع فعلاً', (tester) async {
      final pending = Completer<LabReading>();
      final reader = FakeLabReader(() => pending.future);
      withLab(reader: reader);
      await h.pump(tester, ScanLabScreen(reader: reader, pickImage: (_) async => Uint8List.fromList([1, 2, 3]), today: sep15));
      await settle(tester);

      await tester.tap(find.text('صوّر التقرير'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(reader.calls, 1);
      expect(find.text('بيقرا التقرير…'), findsOneWidget);
      expect(find.textContaining('سطور'), findsNothing);
      expect(find.textContaining('HbA1c'), findsNothing, reason: 'ولا سطر قبل الرد');
      expect(find.byType(LabReportScreen), findsNothing);

      pending.complete(LabReading(
        lab: const ReadField.missing(),
        date: const ReadField.missing(),
        lines: [line('HbA1c', 7.6, '%'), line('Creatinine', 1.2, 'mg/dL')],
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('بيقرا — ٠/٢ سطور'), findsOneWidget);
      expect(find.text('HbA1c — ٧.٦ %'), findsOneWidget);

      await tester.pump(ScanLabScreen.revealPerLine);
      await tester.pump(ScanLabScreen.revealPerLine);
      expect(find.text('بيقرا — ٢/٢ سطور'), findsOneWidget);
      await tester.pump(ScanLabScreen.revealHold);
      await settle(tester);
      expect(find.byType(LabReportScreen), findsOneWidget);
      expect(await h.db.select(h.db.labResults).get(), isEmpty, reason: 'القاعدة ٤ — مفيش حفظ قبل «تمام»');
    });
  });

  group('قراءة التقرير (المخطط ٨)', () {
    Future<void> pumpReport(WidgetTester tester, LabReading reading) async {
      withLab();
      await h.pump(tester, LabReportScreen(reading: reading, image: Uint8List.fromList([9, 9, 9]), today: sep15));
      await settle(tester);
    }

    screenTest('أول تقرير: كل سطر «لسه ما عندناش…» والرقم من غير تعليم — ومفيش نطاق مرجعي ولا «أعلى»', (tester) async {
      await pumpReport(
        tester,
        LabReading(
          lab: sure('معمل البرج'),
          date: sure(DateTime(2026, 9, 12)),
          lines: [line('HbA1c', 7.6, '%'), line('Creatinine', 1.4, 'mg/dL')],
        ),
      );
      expect(find.byKey(const ValueKey('lab-not-enough')), findsNWidgets(2));
      expect(find.text('٧.٦'), findsOneWidget);
      expect(find.textContaining('أعلى'), findsNothing);
      for (final card in tester.widgetList<FCard>(find.byType(FCard))) {
        expect(card.tone, FCardTone.plain, reason: 'مفيش حكم على الرقم');
      }
      expect(find.text('معمل البرج — ١٢ سبتمبر ٢٠٢٦'), findsOneWidget);
      expectNoAdvice(tester);
      expectNoRedAndMinSize(tester);
    });

    screenTest('فيه تاريخ ليه: المقارنة بتحاليله هو بالرقم والفرق وآخر مرة', (tester) async {
      final repo = LabResultsRepository(h.db);
      await repo.saveReport(
        patientId: h.services.patientId,
        happenedAt: DateTime(2026, 3, 1),
        lines: const [ConfirmedLabLine(testName: 'HbA1c', value: 7.1, unit: '%')],
      );
      await repo.saveReport(
        patientId: h.services.patientId,
        happenedAt: DateTime(2026, 6, 1),
        lines: const [ConfirmedLabLine(testName: 'HbA1c', value: 7.4, unit: '%')],
      );
      await pumpReport(
        tester,
        LabReading(lab: const ReadField.missing(), date: const ReadField.missing(), lines: [line('HbA1c', 7.6, '%')]),
      );
      expect(find.text('أعلى من أعلى قياس معتاد ليك (٧.٤) بـ ٠.٢'), findsOneWidget);
      expect(find.text('آخر مرة كان ٧.٤ في ١ يونيو ٢٠٢٦'), findsOneWidget);
      expectNoAdvice(tester);
    });

    screenTest('وحدة مختلفة عن اللي فات → «مش هنقارن»', (tester) async {
      final repo = LabResultsRepository(h.db);
      for (final m in [3, 6]) {
        await repo.saveReport(
          patientId: h.services.patientId,
          happenedAt: DateTime(2026, m, 1),
          lines: const [ConfirmedLabLine(testName: 'Glucose', value: 110, unit: 'mg/dL')],
        );
      }
      await pumpReport(
        tester,
        LabReading(lab: const ReadField.missing(), date: const ReadField.missing(), lines: [line('Glucose', 6.1, 'mmol/L')]),
      );
      expect(find.text('الوحدة مختلفة عن المرات اللي فاتت — مش هنقارن'), findsOneWidget);
    });

    screenTest('رقم مش واضح: ذهبي «راجعها» و«تمام» مقفولة؛ «عدّل» بيفتحها، و«تمام» بيحفظ السجل والنتايج والصورة', (tester) async {
      await pumpReport(
        tester,
        LabReading(
          lab: sure('معمل البرج'),
          date: sure(DateTime(2026, 9, 12)),
          lines: [line('HbA1c', 7.6, '%', unsure: true), line('Creatinine', 1.2, 'mg/dL')],
        ),
      );
      expect(find.text('مش متأكد من دي — راجعها'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'تمام، احفظه');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      // نفس الوزن
      final retake = find.widgetWithText(FilledButton, 'صوّر تاني');
      expect(tester.getSize(retake), tester.getSize(confirm));

      await tester.tap(find.text('عدّل').first);
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('edit-value')), '7.8');
      await tester.tap(find.byKey(const ValueKey('edit-save')));
      await settle(tester);
      expect(find.text('مش متأكد من دي — راجعها'), findsNothing);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      // حفظ الصورة كتابة ملف حقيقية — بتحتاج وقت حقيقي برّه الساعة المزيّفة
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settle(tester);

      final results = await h.db.select(h.db.labResults).get();
      expect([for (final r in results) (r.testName, r.value, r.unit)], [('HbA1c', 7.8, '%'), ('Creatinine', 1.2, 'mg/dL')]);
      final record = (await RecordsRepository(h.db).all(h.services.patientId)).single;
      expect(record.kind, RecordKind.lab);
      expect(record.place, 'معمل البرج');
      expect(record.happenedAt, DateTime(2026, 9, 12));
      expect(record.attachmentPath, isNotNull);
      expect(await tester.runAsync(() => DirectoryAttachmentStore(root: tmp).fileFor(record.attachmentPath!)), isNotNull);
    });

    screenTest('«شيل السطر» بيشيل اللي مش واضح ويفتح «تمام»', (tester) async {
      await pumpReport(
        tester,
        LabReading(lab: const ReadField.missing(), date: const ReadField.missing(), lines: [line('Urea', null, 'mg/dL'), line('HbA1c', 7.6, '%')]),
      );
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'تمام، احفظه')).onPressed, isNull);
      await tester.tap(find.text('شيل السطر').first);
      await settle(tester);
      expect(find.text('Urea'), findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'تمام، احفظه')).onPressed, isNotNull);
    });
  });

  test('كود شاشات السكر والتحاليل: ولا كلمة نصيحة أو حكم في أي نص للمستخدم', () {
    final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final offenders = <String>[];
    // D5.2: الابن بيشوف نفس الأرقام — نفس القاعدة على شاشاته
    for (final entity in [...Directory('lib/features/health').listSync(), ...Directory('lib/features/care').listSync()]) {
      if (entity is! File || entity.path.endsWith('usual_words.dart')) continue;
      for (final raw in entity.readAsLinesSync()) {
        final line = raw.trimLeft();
        if (line.startsWith('//')) continue;
        for (final m in literal.allMatches(line)) {
          final text = m.group(1)!;
          for (final word in adviceWords) {
            final hit = RegExp(r'^[a-z]+$').hasMatch(word)
                ? RegExp('\\b$word\\b', caseSensitive: false).hasMatch(text)
                : text.contains(word);
            if (hit) offenders.add('${entity.path}: «$word» في «$text»');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
