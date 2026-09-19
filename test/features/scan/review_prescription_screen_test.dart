import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_editor.dart';
import 'package:fakkarni/features/scan/debug_panel.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/records/deleted_row.dart' show RecordsEmpty;
import 'package:fakkarni/features/scan/review_prescription_screen.dart';

import 'scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<Future<ReviewResult?> Function()> pumpReview(
    WidgetTester tester,
    List<ReadLine> lines, {
    ReadField<String> doctor = const ReadField(value: null, confidence: 1),
    ReadField<String> clinic = const ReadField(value: null, confidence: 1),
    ReadField<DateTime?> issuedAt = const ReadField(value: null, confidence: 1),
  }) async {
    ReviewResult? result;
    final screen = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ReviewResult>(
                MaterialPageRoute(
                  builder: (_) => ReviewPrescriptionScreen(
                    reading: PrescriptionReading(
                      doctor: doctor,
                      clinic: clinic,
                      issuedAt: issuedAt,
                      lines: lines,
                    ),
                    routine: normalDay,
                    today: aug31,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await h.pump(tester, screen);
    return () async => result;
  }

  /// زرار التأكيد — بمفتاحه، فالعدد اللي على كلمته ما يكسرش الاختبارات.
  Finder confirmFinder() =>
      find.descendant(of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton));

  FilledButton confirmButton(WidgetTester tester) => tester.widget<FilledButton>(confirmFinder());

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(confirmFinder());
    await settle(tester);
  }

  Future<void> open(WidgetTester tester) async {
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  screenTest('صف الثقة القليلة: حافة ذهبية + «مش متأكد من دي — راجعها» + الحقل وملاحظته',
      (tester) async {
    await pumpReview(tester, [unclearLine]);
    await open(tester);

    expect(find.text('الذكاء يقترح، وأنت تؤكّد'), findsOneWidget);
    expect(find.text('مش متأكد من دي — راجعها'), findsOneWidget);
    expect(find.byKey(const ValueKey('unsure-edge')), findsOneWidget);
    final edge = tester.widget<Container>(find.byKey(const ValueKey('unsure-edge')));
    expect(edge.color, F.gold);
    // الحقل بالاسم وملاحظته «اسأل الصيدلي» — مقروءة، مش ذهبي باهت
    expect(find.textContaining(unclearTimingNote, findRichText: true), findsOneWidget);
    expect(find.textContaining('التوقيت: ', findRichText: true), findsOneWidget);
    // الاسم نفسه واضح ومش ذهبي
    final name = tester.widget<Text>(find.text('Cataflam'));
    expect(name.style?.color, F.ink);
    expectNoRedAndMinSize(tester);
  });

  screenTest('صف لكل دوا: الاسم mono ٢٤+، الوقت المحسوب بأرقام عربي، والشريحة بالقاعدة', (tester) async {
    final line = ReadLine(
      name: ok('Antodine 40 mg'),
      amount: ok('قرص واحد'),
      timings: ok([const AnchorTiming(DayAnchor.breakfast, -30)]),
      duration: const ReadField(value: null, confidence: 1),
    );
    await pumpReview(tester, [line]);
    await open(tester);

    final name = tester.widget<Text>(find.text('Antodine 40 mg'));
    expect(name.style?.fontSize, greaterThanOrEqualTo(F.medicationNameSize));
    expect(name.style?.fontFamily, F.monoFamily);
    expect(name.textDirection, TextDirection.ltr);
    // الفطار ٧:٣٠ − ٣٠ = ٧:٠٠ ص — للعرض بس
    expect(find.text('٧:٠٠ ص'), findsOneWidget);
    expect(find.text('الفطار − ٣٠ د'), findsOneWidget, reason: 'القاعدة، مش الساعة');
    // «عدّل» على الكارت + تلاتة على الترويسة (الدكتور، العيادة، التاريخ)
    expect(find.widgetWithText(OutlinedButton, 'عدّل'), findsNWidgets(4));
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(4), reason: 'أيقونة وكلمة — الكارت وترويسة الورقة');
    // الصف الواضح مفيهوش حافة شك
    expect(find.byKey(const ValueKey('unsure-edge')), findsNothing);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«أضف دوا ما اتعرفش عليه» بتفتح المحرر فاضي', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    await tester.tap(find.text('أضف دوا ما اتعرفش عليه'));
    await settle(tester);
    expect(find.byType(AddMedicationScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Concor 5mg'), findsNothing);
  });

  screenTest('ولا حاجة بتتحفظ قبل الدوسة', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
    expect(h.sink.scheduled, isEmpty);
  });

  screenTest('«تمام» مقفولة لما في سطر محتاج تحديد، ومفتوحة لما كله واضح',
      (tester) async {
    await pumpReview(tester, [clearLine, unclearLine]);
    await open(tester);

    FilledButton confirm() => tester.widget<FilledButton>(
          find.descendant(of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)),
        );
    expect(confirm().onPressed, isNull);
    expect(find.textContaining('مش واضح — دوس'), findsOneWidget);
  });

  screenTest('«أعدّل» وزرار التأكيد بنفس الوزن بالظبط — نفس المقاس، مليانين، نفس الخط', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    final edit = tester.getSize(
      find.ancestor(of: find.text('أعدّل'), matching: find.byType(FilledButton)),
    );
    final confirm = tester.getSize(
      find.descendant(of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)),
    );
    expect(edit, confirm);
    expect(edit.height, F.primaryButtonHeight);

    // مش لينك باهت: الاتنين FilledButton بتعبئة غامقة ونفس الخط
    FilledButton button(String label) => tester.widget<FilledButton>(
          find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
        );
    final e = button('أعدّل').style!, c = confirmButton(tester).style!;
    Color bg(ButtonStyle st) => st.backgroundColor!.resolve({})!;
    expect(bg(e).computeLuminance(), lessThan(0.2), reason: '«أعدّل» مليان وغامق');
    expect(bg(c).computeLuminance(), lessThan(0.2));
    expect(e.textStyle!.resolve({}), c.textStyle!.resolve({}));
    expect(e.foregroundColor!.resolve({}), c.foregroundColor!.resolve({}));
  });

  screenTest('«تمام» بتحفظ السطور الواضحة — كل توقيت جدول — وبتعيد الجدولة',
      (tester) async {
    final thrice = ReadLine(
      name: ok('Augmentin'),
      amount: ok('قرص'),
      timings: ok([
        const AnchorTiming(DayAnchor.breakfast, 0),
        const AnchorTiming(DayAnchor.lunch, 0),
        const AnchorTiming(DayAnchor.dinner, 0),
      ]),
      duration: ok<int?>(7),
    );
    final result = await pumpReview(tester, [clearLine, thrice]);
    await open(tester);

    await confirm(tester);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.length, 4);
    final concor = saved.singleWhere((s) => s.medicationName == 'Concor 5mg');
    expect(concor.timing, const AnchorTiming(DayAnchor.breakfast, 0));
    expect(concor.durationDays, isNull, reason: 'مفتوحة زي ما الورقة سابتها');
    expect(concor.amountLabel, 'قرص واحد');
    final augmentin = saved.where((s) => s.medicationName == 'Augmentin');
    expect(augmentin.length, 3);
    expect(augmentin.every((s) => s.durationDays == 7), isTrue);

    expect(h.sink.scheduled, isNotEmpty, reason: 'اتجدولت بعد التأكيد');
    expect(await result(), ReviewResult.confirmed);
  });

  screenTest('«عدّل» بتعدّل السطر في الذاكرة وبترجع — **ولا بايت بيتكتب** قبل التأكيد',
      (tester) async {
    await pumpReview(tester, [unclearLine]);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('edit-line-0')));
    await settle(tester);

    expect(find.byType(AddMedicationScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cataflam'), findsOneWidget);

    // الحقول ثم محرّر الجرعة — التوقيت اللي كان مش واضح بيتحدد بإيده هنا
    await tester.tap(find.text('كمّل — إمتى؟'));
    await settle(tester);
    expect(find.byType(DoseEditor), findsOneWidget);
    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);

    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
    expect(find.text('اتعدّل'), findsOneWidget, reason: 'اتعدّل — مش اتحفظ');
    // **دي بيت القصيد**: الشاشة مسوّدة، فالقاعدة لسه فاضية
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
    expect(h.sink.scheduled, isEmpty, reason: 'ولا تذكير اتجدول قبل التأكيد');

    // ودلوقتي بس، بعد «تمام»
    expect(confirmButton(tester).onPressed, isNotNull);
    await confirm(tester);
    expect((await h.meds.activeSchedules(h.services.patientId)).single.medicationName, 'Cataflam');
  });

  screenTest('«شيله» بيطلع السطر من المسوّدة — فعمره ما يتحفظ، و«رجّعه» بترجّعه', (tester) async {
    final second = ReadLine(
      name: ok('Antodine 40 mg'),
      amount: ok('قرص واحد'),
      timings: ok([const AnchorTiming(DayAnchor.dinner, 0)]),
      duration: const ReadField(value: null, confidence: 1),
    );
    await pumpReview(tester, [clearLine, second]);
    await open(tester);
    expect(find.text('تمام — دواءين'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remove-line-0')));
    await settle(tester);

    expect(find.text('Concor 5mg'), findsNothing, reason: 'طلع من المسوّدة');
    expect(find.text('Antodine 40 mg'), findsOneWidget);
    expect(find.text('تمام — دوا واحد'), findsOneWidget, reason: 'العدد على الزرار بيعدّ اللي فاضل');
    // التراجع باسم السطر
    expect(find.textContaining('اتشال Concor 5mg'), findsOneWidget);

    await confirm(tester);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.map((s) => s.medicationName).toSet(), {'Antodine 40 mg'},
        reason: 'اللي اتشال عمره ما وصل القاعدة');
  });

  screenTest('«رجّعه» بترجّع السطر للمسوّدة وبيتحفظ معاهم', (tester) async {
    final second = ReadLine(
      name: ok('Antodine 40 mg'),
      amount: ok('قرص واحد'),
      timings: ok([const AnchorTiming(DayAnchor.dinner, 0)]),
      duration: const ReadField(value: null, confidence: 1),
    );
    await pumpReview(tester, [clearLine, second]);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('remove-line-0')));
    await settle(tester);
    await tester.tap(find.text('رجّعه'));
    await settle(tester);

    expect(find.text('Concor 5mg'), findsOneWidget);
    expect(find.text('تمام — دواءين'), findsOneWidget);

    await confirm(tester);
    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.map((s) => s.medicationName).toSet(), {'Concor 5mg', 'Antodine 40 mg'});
  });

  screenTest('شيل كل السطور → الزرار بيتقفل ومفيش حاجة تتأكّد', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('remove-line-0')));
    await settle(tester);

    expect(confirmButton(tester).onPressed, isNull);
    expect(find.text('تمام — مفيش أدوية'), findsOneWidget);
    expect(find.byKey(const ValueKey('all-removed')), findsOneWidget);
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
  });

  group('الملف الصحي (D3.5)', () {
    screenTest('فشل تسجيل الروشتة بيتقال — والأدوية بتفضل محفوظة', (tester) async {
      // مستودع على قاعدة مقفولة: `add` بترمي فعلاً — مش fake بيمثّل
      final dead = AppDatabase(NativeDatabase.memory());
      await dead.close();

      ReviewResult? result;
      await h.pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ReviewResult>(
                    MaterialPageRoute(
                      builder: (_) => ReviewPrescriptionScreen(
                        reading: PrescriptionReading(
                          doctor: const ReadField(value: null, confidence: 1),
                          lines: [clearLine],
                        ),
                        routine: normalDay,
                        today: aug31,
                        records: RecordsRepository(dead),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await open(tester);
      await confirm(tester);

      // الوعد اتنفّذ: الدوا محفوظ وهيرنّ
      expect((await h.meds.activeSchedules(h.services.patientId)), hasLength(1));
      expect(h.sink.scheduled, isNotEmpty);
      // والحقيقة متقالة — مش صمت
      expect(find.byKey(const ValueKey('file-failed')), findsOneWidget);
      expect(find.textContaining('ما اتسجّلتش في الملف الصحي'), findsOneWidget);
      expect(await RecordsRepository(h.db).all(h.services.patientId), isEmpty);
      expect(result, isNull, reason: 'الشاشة لسه مفتوحة — المستخدم بيقفلها بنفسه');

      await tester.tap(find.byKey(const ValueKey('close-review')));
      await settle(tester);
      expect(result, ReviewResult.confirmed);
    });

    screenTest('من الطرف للطرف: بعد التأكيد، الكارت بيبان في شاشة «الملف الصحي» نفسها',
        (tester) async {
      await pumpReview(tester, [clearLine]);
      await open(tester);
      await confirm(tester);

      // نفس الشاشة اللي المستخدم بيفتحها — مش القراية بس
      await tester.pumpWidget(const SizedBox.shrink());
      await h.pump(tester, const HealthFileScreen());
      await settle(tester);

      // الكارت بيعرض العنوان والسطر التعريفي — أسامي الأدوية في `notes`
      expect(find.text('روشتة — دوا واحد'), findsOneWidget);
      expect(find.byType(RecordsEmpty), findsNothing, reason: 'الملف مش فاضي');
      expect(
        (await RecordsRepository(h.db).all(h.services.patientId)).single.notes,
        'Concor 5mg',
      );
    });

    screenTest('تشخيص: بعد التأكيد، الروشتة موجودة في watchAll بنفس patientId اللي الشاشة بتقرا بيه',
        (tester) async {
      await pumpReview(tester, [clearLine]);
      await open(tester);
      await confirm(tester);

      // نفس القراية اللي «الملف الصحي» بيستعملها بالظبط
      // قراية مباشرة بنفس شرط `watchAll` — بث drift جوّه اختبار ودجت بيعلّق
      final rows = await RecordsRepository(h.db).all(h.services.patientId);
      expect(rows, hasLength(1), reason: 'الكتابة وصلت — لو وقع هنا فالمشكلة في الكتابة');
      expect(rows.single.kind, RecordKind.prescription);
      expect(rows.single.patientId, h.services.patientId);
    });

    Future<List<dynamic>> records() => RecordsRepository(h.db).all(h.services.patientId);

    screenTest('التأكيد بيكتب صف روشتة واحد بالتاريخ والأدوية — والدكتور الواثق منه بس', (tester) async {
      final second = ReadLine(
        name: ok('Antodine 40 mg'),
        amount: ok('قرص واحد'),
        timings: ok([const AnchorTiming(DayAnchor.dinner, 0)]),
        duration: const ReadField(value: null, confidence: 1),
      );
      await pumpReview(tester, [clearLine, second], doctor: ok('د. هشام مام'));
      await open(tester);
      await confirm(tester);

      final rows = await RecordsRepository(h.db).all(h.services.patientId);
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.kind, RecordKind.prescription);
      expect(r.title, 'روشتة — دواءين');
      expect(r.notes, 'Concor 5mg — Antodine 40 mg');
      expect(r.doctor, 'د. هشام مام');
      expect(r.happenedAt, DateTime(2026, 8, 31));
    });

    screenTest('دكتور القراءة مش واضح → العمود فاضي، مش تخمين', (tester) async {
      await pumpReview(tester, [clearLine], doctor: low('د. هشـ؟', 'الخط مش واضح'));
      await open(tester);
      await confirm(tester);

      final r = (await RecordsRepository(h.db).all(h.services.patientId)).single;
      expect(r.doctor, isNull);
      expect(r.title, 'روشتة — دوا واحد');
    });

    screenTest('ترويسة الورقة كاملة → بتتحفظ مع السجل (مين، فين، وإمتى)', (tester) async {
      await pumpReview(
        tester,
        [clearLine],
        doctor: ok('د. هشام مام'),
        clinic: ok('مستشفى القصر العيني'),
        issuedAt: ReadField(value: DateTime(2026, 8, 20), confidence: 0.95),
      );
      await open(tester);

      expect(find.text('د. هشام مام'), findsOneWidget);
      expect(find.text('مستشفى القصر العيني'), findsOneWidget);
      expect(find.byKey(const ValueKey('date-fallback')), findsNothing,
          reason: 'الورقة كاتبة تاريخها — مفيش رجوع للنهاردة');

      await confirm(tester);

      final r = (await RecordsRepository(h.db).all(h.services.patientId)).single;
      expect(r.doctor, 'د. هشام مام');
      expect(r.place, 'مستشفى القصر العيني');
      expect(r.happenedAt, DateTime(2026, 8, 20), reason: 'تاريخ الورقة، مش النهاردة');
    });

    screenTest('مفيش ترويسة → السجل بتاريخ النهاردة، والجملة بتقول كده **قبل** الدوسة',
        (tester) async {
      await pumpReview(tester, [clearLine]);
      await open(tester);

      // التحذير ظاهر قبل التأكيد — تاريخ غلط في ملف طبي أوحش من ناقص
      expect(find.byKey(const ValueKey('date-fallback')), findsOneWidget);
      expect(find.textContaining('هتتسجّل بتاريخ النهاردة'), findsOneWidget);
      // والفاضي بيتقال بالكلام، من غير علامة ذهبية (مش مكتوب ≠ مش متأكد)
      expect(find.text('مش مكتوب على الورقة'), findsNWidgets(2),
          reason: 'الدكتور والتاريخ');
      expect(find.text('مش مكتوبة على الورقة'), findsOneWidget, reason: 'العيادة');
      expect(find.text('مش متأكد من دي — راجعها'), findsNothing,
          reason: 'مفيش ذهبي على حاجة مش مكتوبة');

      await confirm(tester);

      final r = (await RecordsRepository(h.db).all(h.services.patientId)).single;
      expect(r.happenedAt, DateTime(aug31.year, aug31.month, aug31.day));
      expect(r.doctor, isNull);
      expect(r.place, isNull);
    });

    screenTest('عيادة بثقة قليلة → علامة ذهبية، وبتتصحّح قبل الحفظ', (tester) async {
      await pumpReview(
        tester,
        [clearLine],
        clinic: low('مستشفى القصـ؟', 'الترويسة مش واضحة'),
      );
      await open(tester);

      final card = find.byKey(const ValueKey('header-العيادة أو المستشفى'));
      expect(card, findsOneWidget);
      expect(
        tester.widget<Container>(card).decoration,
        isA<BoxDecoration>().having((d) => (d.border! as Border).top.color, 'حافة', F.gold),
      );
      expect(find.text('الترويسة مش واضحة'), findsOneWidget);

      // بيتصحّح بإيده قبل التأكيد
      await tester.tap(find.descendant(of: card, matching: find.text('عدّل')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'مستشفى القصر العيني');
      await tester.tap(find.text('احفظ'));
      await settle(tester);

      expect(find.text('مستشفى القصر العيني'), findsOneWidget);
      await confirm(tester);

      final r = (await RecordsRepository(h.db).all(h.services.patientId)).single;
      expect(r.place, 'مستشفى القصر العيني', reason: 'اللي الإنسان كتبه بيتحفظ');
    });

    screenTest('عيادة بثقة قليلة ما اتصححتش → العمود يفضل فاضي، مش تخمين', (tester) async {
      await pumpReview(tester, [clearLine], clinic: low('مستشفى القصـ؟', 'الترويسة مش واضحة'));
      await open(tester);
      await confirm(tester);

      final r = (await RecordsRepository(h.db).all(h.services.patientId)).single;
      expect(r.place, isNull);
    });

    screenTest('«صوّر تاني» ما بيكتبش أي سجل', (tester) async {
      await pumpReview(tester, [clearLine]);
      await open(tester);
      await tester.tap(find.text('صوّر تاني'));
      await settle(tester);
      expect(await records(), isEmpty);
    });

    test('عنوان الروشتة بالعدد', () {
      expect(prescriptionRecordTitle(1), 'روشتة — دوا واحد');
      expect(prescriptionRecordTitle(2), 'روشتة — دواءين');
      expect(prescriptionRecordTitle(4), 'روشتة — ٤ أدوية');
    });
  });

  screenTest('«صوّر تاني» موجودة وبترجّع retake', (tester) async {
    final result = await pumpReview(tester, [unclearLine]);
    await open(tester);

    await tester.tap(find.text('صوّر تاني'));
    await settle(tester);

    expect(await result(), ReviewResult.retake);
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
  });

  group('مجهول بيقفل ومجهول ما بيقفلش', () {
    final unknownAmount = ReadLine(
      name: ok('Telfast 180 mg'),
      amount: const ReadField.missing('الورقة مش كاتبة الجرعة'),
      timings: ok([const AnchorTiming(DayAnchor.dinner, 0)]),
      duration: const ReadField(value: null, confidence: 1),
    );

    screenTest('جرعة مش معروفة بس → «تمام» مفتوحة والسطر الهادي تحتها', (tester) async {
      await pumpReview(tester, [unknownAmount]);
      await open(tester);

      final confirm = tester.widget<FilledButton>(
        find.descendant(of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)),
      );
      expect(confirm.onPressed, isNotNull);
      expect(find.text('هتتحفظ من غير الجرعة — تقدر تضيفها بعدين'), findsOneWidget);
      expect(find.textContaining('مش واضح — دوس'), findsNothing);
      // لسه معلّمة بملاحظتها — ما اتنستش في صمت
      expect(find.text('مش متأكد من دي — راجعها'), findsOneWidget);
      expect(find.textContaining('الجرعة: الورقة مش كاتبة الجرعة', findRichText: true), findsOneWidget);
    });

    screenTest('«تمام» بتحفظها من غير جرعة ومعلّمة «مش معروفة» — مفيش قيمة مخترعة', (tester) async {
      await pumpReview(tester, [unknownAmount]);
      await open(tester);

      await confirm(tester);

      final saved = (await h.meds.activeSchedules(h.services.patientId)).single;
      expect(saved.medicationName, 'Telfast 180 mg');
      expect(saved.amountLabel, isNull);
      final row = (await h.db.select(h.db.medications).get()).single;
      expect(row.amountUnknown, isTrue);
    });

    screenTest('توقيت مش واضح → لسه بيقفل، والسطر الهادي مش بيظهر', (tester) async {
      await pumpReview(tester, [unclearLine, unknownAmount]);
      await open(tester);

      final confirm = tester.widget<FilledButton>(
        find.descendant(of: find.byKey(const ValueKey('confirm-review')), matching: find.byType(FilledButton)),
      );
      expect(confirm.onPressed, isNull);
      expect(find.text('هتتحفظ من غير الجرعة — تقدر تضيفها بعدين'), findsNothing);
      expect(find.textContaining('مش واضح — دوس'), findsOneWidget);
    });
  });

  screenTest('تحذير تقاعد الموديل بيظهر في نسخة التطوير فوق', (tester) async {
    ReviewResult? result;
    await h.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ReviewResult>(
                MaterialPageRoute(
                  builder: (_) => ReviewPrescriptionScreen(
                    reading: PrescriptionReading(
                      doctor: const ReadField(value: null, confidence: 1),
                      lines: [clearLine],
                      modelWarning: 'pinned gemini-3.6-flash retired',
                    ),
                    routine: normalDay,
                    today: aug31,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await open(tester);

    expect(find.byType(DebugPanel), findsOneWidget);
    expect(find.text('pinned gemini-3.6-flash retired'), findsOneWidget);
    expect(result, isNull);
  });
}
