import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/records/history_screen.dart';
import 'package:fakkarni/features/records/manual_entry_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep14 = DateTime(2026, 9, 14);
  RecordsRepository repo() => RecordsRepository(h.db);

  Future<int> add(RecordKind kind, String title, DateTime at, {String? doctor, String? notes}) => repo().add(
        patientId: h.services.patientId,
        kind: kind,
        title: title,
        happenedAt: at,
        doctor: doctor,
        notes: notes,
      );

  Future<void> seed() async {
    await add(RecordKind.imaging, 'أشعة صدر', DateTime(2026, 9, 10), doctor: 'د. هشام مام', notes: 'طبيعية');
    await add(RecordKind.lab, 'HbA1c', DateTime(2026, 8, 28), doctor: 'د. طارق سعيد');
    await add(RecordKind.visit, 'باطنة', DateTime(2026, 3, 2), doctor: 'د. هشام مام');
  }

  group('الإدخال اليدوي (المخطط ٢٨)', () {
    screenTest('خمس استمارات، كل واحدة بحقولها — والتحليل بيتحفظ بالحرف', (tester) async {
      await h.pump(tester, ManualEntryScreen(today: sep14));
      await settle(tester);

      // الأشعة: نوع + مركز + دكتور + نتيجة
      expect(find.text('نوع الأشعة'), findsOneWidget);
      expect(find.text('المركز'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kind-visit')));
      await settle(tester);
      expect(find.text('التخصص أو سبب الزيارة'), findsOneWidget);
      expect(find.text('العيادة أو المستشفى'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kind-prescription')));
      await settle(tester);
      expect(find.textContaining('ده للتسجيل بس'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-place')), findsNothing, reason: 'الروشتة مالهاش مكان');

      await tester.tap(find.byKey(const ValueKey('kind-booking')));
      await settle(tester);
      expect(find.textContaining('مش هيفكّرك بيه'), findsOneWidget);
      expect(find.text('بكرة'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kind-lab')));
      await settle(tester);
      final save = find.widgetWithText(FilledButton, 'احفظ في الملف');
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'من غير اسم');

      await tester.enterText(find.byKey(const ValueKey('record-title')), 'HbA1c');
      await tester.enterText(find.byKey(const ValueKey('record-place')), 'معمل البرج');
      await tester.enterText(find.byKey(const ValueKey('record-notes')), '٧.٦٪');
      await tester.tap(find.text('امبارح'));
      await settle(tester);
      await tester.tap(save);
      await settle(tester);

      final r = (await repo().all(h.services.patientId)).single;
      expect(r.kind, RecordKind.lab);
      expect(r.title, 'HbA1c');
      expect(r.place, 'معمل البرج');
      expect(r.doctor, isNull, reason: 'ما اتكتبش');
      expect(r.notes, '٧.٦٪');
      expect(r.happenedAt, DateTime(2026, 9, 13));
      expectNoRedAndMinSize(tester);
    });
  });

  group('الملف الصحي (المخطط ١٣)', () {
    screenTest('فاضي → «لسه مفيش حاجة هنا» بهدوء وبيقول إزاي تضيف', (tester) async {
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      expect(find.text('لسه مفيش حاجة هنا'), findsOneWidget);
      expect(find.textContaining('+ ضيف'), findsWidgets);
      expectNoRedAndMinSize(tester);
    });

    screenTest('البحث بالاسم والدكتور والتاريخ (عربي أو إنجليزي)', (tester) async {
      await seed();
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);
      final search = find.byKey(const ValueKey('records-search'));

      Future<void> expectShown(String q, List<String> titles) async {
        await tester.enterText(search, q);
        await settle(tester);
        for (final t in ['أشعة صدر', 'HbA1c', 'باطنة']) {
          expect(find.text(t), titles.contains(t) ? findsOneWidget : findsNothing, reason: '$q → $t');
        }
      }

      await expectShown('هشام', ['أشعة صدر', 'باطنة']);
      await expectShown('hba1c', ['HbA1c']);
      await expectShown('أغسطس', ['HbA1c']);
      await expectShown('٢٨', ['HbA1c']);
      await expectShown('3/2026', ['باطنة']);
      await tester.enterText(search, 'مفيش حاجة كده');
      await settle(tester);
      expect(find.text('مفيش حاجة بالكلام ده'), findsOneWidget);
    });

    screenTest('«⋯ خيارات» → «امسحه» بتأكيد → الصف بيختفي، مش بيفضل شهر', (tester) async {
      final id = await add(RecordKind.lab, 'HbA1c', DateTime(2026, 8, 28));
      await add(RecordKind.visit, 'باطنة', DateTime(2026, 8, 20));
      await h.pump(tester, HealthFileScreen(today: sep14));
      await settle(tester);

      expect(find.text('⋯ خيارات'), findsNWidgets(2), reason: 'مش أيقونة لوحدها');

      // «لأ، سيبه» ما بيمسحش
      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete')));
      await settle(tester);
      expect(find.text('تمسح «HbA1c»؟'), findsOneWidget);
      expect(find.text('هيتشال من الملف خالص، ومفيش رجوع.'), findsOneWidget);
      // الجملة القديمة كانت بتوعد بشهر رجوع — ومحدش كان بيقدر يرجّع بيها حاجة
      expect(find.textContaining('٣٠ يوم'), findsNothing);
      await tester.tap(find.text('لأ، سيبه'));
      await settle(tester);
      expect((await repo().all(h.services.patientId)), hasLength(2));

      await tester.tap(find.byKey(ValueKey('record-options-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-delete-confirm')));
      await settle(tester);

      expect(find.text('HbA1c'), findsNothing, reason: 'اتمسح يعني راح');
      expect(find.text('باطنة'), findsOneWidget, reason: 'والباقي مكانه');
      expect(find.text('رجّعه'), findsNothing);
      expect(find.byType(Opacity), findsNothing, reason: 'مفيش صف باهت مشطوب');
      for (final msa in ['حُذف', 'يُنقل', 'المحذوفات']) {
        expect(find.textContaining(msa), findsNothing, reason: msa);
      }

      expectNoRedAndMinSize(tester);
    });
  });

  group('الحالات السابقة (المخطط ٢٩)', () {
    screenTest('بالترتيب، الأحدث فوق، والفلتر بالنوع وبالفترة', (tester) async {
      await seed();
      await h.pump(tester, HistoryScreen(today: sep14));
      await settle(tester);

      final y1 = tester.getTopLeft(find.text('أشعة صدر')).dy;
      final y2 = tester.getTopLeft(find.text('HbA1c')).dy;
      final y3 = tester.getTopLeft(find.text('باطنة')).dy;
      expect(y1 < y2 && y2 < y3, isTrue);
      expect(find.text('١٠ سبتمبر ٢٠٢٦'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('filter-lab')));
      await settle(tester);
      expect(find.text('HbA1c'), findsOneWidget);
      expect(find.text('أشعة صدر'), findsNothing);

      await tester.tap(find.text('الكل').first);
      await tester.tap(find.byKey(const ValueKey('period-threeMonths')));
      await settle(tester);
      expect(find.text('أشعة صدر'), findsOneWidget);
      expect(find.text('باطنة'), findsNothing, reason: 'مارس برّه آخر ٣ شهور');

      await tester.tap(find.byKey(const ValueKey('filter-visit')));
      await settle(tester);
      expect(find.text('مفيش حاجة في الفلتر ده'), findsOneWidget);
      expectNoRedAndMinSize(tester);
    });

    screenTest('الممسوح مش على الخط خالص — ولا مشطوب ولا «رجّعه»', (tester) async {
      final id = await add(RecordKind.imaging, 'أشعة صدر', DateTime(2026, 9, 10));
      await add(RecordKind.lab, 'صورة دم', DateTime(2026, 9, 11));
      await repo().delete(id, now: sep14);
      await h.pump(tester, HistoryScreen(today: sep14));
      await settle(tester);
      expect(find.text('صورة دم'), findsOneWidget, reason: 'الباقي مكانه');
      expect(find.text('أشعة صدر'), findsNothing);
      expect(find.text('رجّعه'), findsNothing);
      expect(find.textContaining('٣٠ يوم'), findsNothing);
    });

    screenTest('فاضي → بيقول إزاي تضيف', (tester) async {
      await h.pump(tester, HistoryScreen(today: sep14));
      await settle(tester);
      expect(find.text('لسه مفيش حاجة هنا'), findsOneWidget);
      expect(find.text('+ ضيف'), findsOneWidget);
    });
  });

  group('الوصول', () {
    screenTest('تبويب «الملف» في الدوك، و«ضيف» → «سجّل زيارة أو تحليل أو أشعة»', (tester) async {
      await h.pump(tester, AppShell(routine: normalDay, now: DateTime(2026, 8, 31, 8)));
      await settle(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.tap(find.text('سجّل زيارة أو تحليل أو أشعة'));
      await settle(tester);
      expect(find.byType(ManualEntryScreen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      // الباب الوحيد للملف الصحي: تبويب الدوك. صف الإعدادات اتشال —
      // بابين لأوضة واحدة بيخلّي المستخدم يشك إنهم حاجتين.
      await tester.tap(find.text('الملف').last);
      await settle(tester);
      expect(find.byType(HealthFileScreen), findsOneWidget);
    });
  });
}
