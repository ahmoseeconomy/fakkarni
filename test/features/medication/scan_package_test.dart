// **«صوّر العلبة أو الشريط» — صورة بتملا فورم، مش بتعمل تذكير.**
//
// القاعدة ٤ هنا حرفياً: القراية مسوّدة، والحفظ محتاج دوسة إنسان. والقاعدة
// اللي الميزة دي معمولة حواليها: **العلبة ما بتقولش مواعيد** — الجرعة
// والمواعيد من الدكتور، والحقول دي بتفضل فاضية زي الإدخال اليدوي.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fakkarni/ai/package_reader.dart';
import 'package:fakkarni/ai/package_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;
import 'package:fakkarni/core/widgets/primitives.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/scan_package_screen.dart';

import '../scan/scan_test_support.dart';

class _FakeReader implements MedicinePackageReader {
  _FakeReader(this.result);
  final PackageReading result;
  int calls = 0;

  @override
  Future<PackageReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    calls++;
    return result;
  }
}

ReadField<String> _sure(String v) => ReadField(value: v, confidence: 0.95);
ReadField<String> _unsure(String? v) => ReadField(value: v, confidence: 0.4);

PackageReading _reading({
  ReadField<String>? brand,
  ReadField<String>? ingredient,
  ReadField<String>? strength,
}) =>
    PackageReading(
      brand: brand ?? _sure('Concor'),
      activeIngredient: ingredient ?? _sure('Bisoprolol fumarate'),
      strength: strength ?? _sure('5 mg'),
      form: _sure('tablets'),
      packSize: _sure('30 tablets'),
    );

Future<Uint8List?> _picker(ImageSource source) async => Uint8List.fromList([1, 2, 3]);

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<void> openScan(WidgetTester tester, MedicinePackageReader? reader) async {
    await h.pump(
      tester,
      ScanPackageScreen(
        routine: normalDay,
        reader: reader,
        pickImage: _picker,
        today: aug31,
      ),
    );
  }

  Future<void> shoot(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('package-capture')));
    await settle(tester);
  }

  group('القراية بتملا الفورم، وبس', () {
    screenTest('الاسم والتركيز في خانة واحدة، والمادة معروضة للمراجعة', (tester) async {
      await openScan(tester, _FakeReader(_reading()));
      await shoot(tester);

      expect(find.byType(AddMedicationScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('from-photo')), findsOneWidget);
      expect(find.text('من صورة العلبة'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Concor 5 mg'), findsOneWidget);
      expect(find.textContaining('Bisoprolol fumarate'), findsOneWidget);
      expect(find.textContaining('30 tablets'), findsOneWidget);
    });

    screenTest('**والمواعيد والجرعة فاضية — والشاشة بتقول ليه**', (tester) async {
      await openScan(tester, _FakeReader(_reading()));
      await shoot(tester);

      // خانة «الجرعة في المرة» فاضية: العلبة ما بتقولش الراجل بياخد كام.
      final amount = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(amount[1].controller!.text, isEmpty, reason: 'جرعة من علبة = اختراع');
      expect(
        find.textContaining('العلبة ما بتقولش الجرعة ولا المواعيد'),
        findsOneWidget,
      );
      // والمشي للمحرّر لسه قدامه — مفيش موعد اتحطّ من الصورة
      expect(find.text('كمّل — إمتى؟'), findsOneWidget);
    });

    screenTest('**ولا دوا بيتكتب من غير ما يدوس** (القاعدة ٤)', (tester) async {
      await openScan(tester, _FakeReader(_reading()));
      await shoot(tester);

      expect(await MedicationRepository(h.db).currentMedicines(h.services.patientId), isEmpty);
      expect(h.sink.scheduled, isEmpty, reason: 'ولا إشعار اتجدول من صورة');
    });
  });

  group('الثقة الواطية = صوّر تاني، مش تخمين', () {
    screenTest('اسم مش واضح → الشاشة بتقول اللي في المواصفة بالحرف', (tester) async {
      await openScan(tester, _FakeReader(_reading(brand: _unsure('Conc…'))));
      await shoot(tester);

      expect(find.byType(AddMedicationScreen), findsNothing, reason: 'مفيش فورم بنص اسم');
      expect(find.byKey(const ValueKey('package-retake')), findsOneWidget);
      expect(find.text(unreadablePackage), findsOneWidget);
    });

    screenTest('وحقل واحد مش واضح: الفورم بيفتح، والحقل فاضي ومتسمّى', (tester) async {
      await openScan(tester, _FakeReader(_reading(ingredient: _unsure('Bisopr…'))));
      await shoot(tester);

      expect(find.byType(AddMedicationScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Concor 5 mg'), findsOneWidget);
      expect(find.textContaining('Bisopr…'), findsNothing, reason: 'تخمين اتعرض');
      final note = tester.widget<Text>(find.byKey(const ValueKey('unclear-fields')));
      expect(note.data, contains(unreadablePackage));
      expect(note.data, contains('المادة الفعّالة'));
    });
  });

  group('«الدوا ده عندك خلاص؟»', () {
    Future<void> seed(String name, {String? ingredient}) =>
        h.meds.addMedicationWithDoses(
          patientId: h.services.patientId,
          name: name,
          timings: const [AnchorTiming(DayAnchor.breakfast, -30)],
          startDate: aug31,
          activeIngredient: ingredient,
        );

    screenTest('نفس الاسم بتركيز تاني → تحذير بالاسم، والحفظ لسه ممكن', (tester) async {
      await seed('Concor 10 mg');
      await openScan(tester, _FakeReader(_reading()));
      await shoot(tester);

      final note = find.byKey(const ValueKey('duplicate-warning'));
      expect(note, findsOneWidget);
      expect(
        tester.widget<Text>(find.descendant(of: note, matching: find.byType(Text))).data,
        contains('الدوا ده عندك في القايمة باسم «Concor 10 mg»'),
      );
      // **بنقول، مش بنمنع** — الزرار شغّال زي ما هو، والقرار قراره
      expect(
        tester.widget<FPrimaryButton>(find.byType(FPrimaryButton)).onPressed,
        isNotNull,
        reason: 'التحذير بيعرض، والمنع قرار مش بتاعنا',
      );
    });

    screenTest('واسم مختلف بنفس المادة → تحذير بالمادة', (tester) async {
      await seed('Panadol', ingredient: 'Paracetamol');
      await openScan(
        tester,
        _FakeReader(_reading(
          brand: _sure('Paramol'),
          ingredient: _sure('Paracetamol'),
          strength: _sure('500 mg'),
        )),
      );
      await shoot(tester);

      expect(
        find.textContaining('نفس المادة الفعّالة (Paracetamol) عندك في «Panadol»'),
        findsOneWidget,
      );
    });

    screenTest('ودوا جديد خالص → مفيش تحذير', (tester) async {
      await seed('Augmentin 1g', ingredient: 'Amoxicillin');
      await openScan(tester, _FakeReader(_reading()));
      await shoot(tester);

      expect(find.byKey(const ValueKey('duplicate-warning')), findsNothing);
    });
  });

  group('الدايرة بتقفل: الحفظ بيسجّل المادة، فالعلبة الجاية بتتمسك', () {
    screenTest('«احفظ» بيكتب الدوا ومعاه مادته الفعّالة', (tester) async {
      await openScan(tester, _FakeReader(_reading()));
      await shoot(tester);

      // المشي الكامل: «كمّل» → محرّر الجرعة → «احفظ الجرعة».
      await tester.tap(find.text('كمّل — إمتى؟'));
      await settle(tester);
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      final saved = await MedicationRepository(h.db).currentMedicines(h.services.patientId);
      expect(saved, hasLength(1));
      expect(saved.single.name, 'Concor 5 mg');
      // **دي اللي بتخلّي الفحص حقيقي** — من غيرها علبة تانية بمادة واحدة
      // واسم تاني كانت هتعدّي.
      expect(saved.single.activeIngredient, 'Bisoprolol fumarate');
    });

    screenTest('وبالإيد من غير صورة: مفيش مادة مخترعة', (tester) async {
      await h.pump(tester, AddMedicationScreen(routine: normalDay, today: aug31));
      await tester.enterText(find.byType(TextField).first, 'Telfast 180 mg');
      await settle(tester);
      await tester.tap(find.text('كمّل — إمتى؟'));
      await settle(tester);
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      final saved = await MedicationRepository(h.db).currentMedicines(h.services.patientId);
      expect(saved.single.name, 'Telfast 180 mg');
      expect(saved.single.activeIngredient, isNull, reason: 'ماحدش قالنا مادته');
      // ولا لوحة قراية على شاشة مالهاش صورة
      expect(find.byKey(const ValueKey('from-photo')), findsNothing);
    });
  });

  group('من غير مفتاح', () {
    screenTest('الشاشة بتقول إن القراية مش متظبطة، و«أكتبه بإيدي» شغّال', (tester) async {
      await openScan(tester, null);
      expect(find.byKey(const ValueKey('package-capture')), findsNothing);
      expect(find.text('أكتبه بإيدي'), findsOneWidget);
    });
  });
}
