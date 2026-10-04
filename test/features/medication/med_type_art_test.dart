// رسومات نوع الدوا (الخيار ب، المالك ٤ أكتوبر ٢٠٢٦) والأغراض الجديدة.
//
// الرسمة بديل لما مفيش صورة — نضيفة من غير كلام عليها. والأغراض بقت بصيغة
// «لل» و«كلّمني» لسه فاهمها.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/features/medication/med_photo.dart';
import 'package:fakkarni/features/medication/med_type_art.dart';
import 'package:fakkarni/features/voice/command_parser.dart';


Widget _host(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// العرض والارتفاع ونوع اللون من ترويسة PNG (IHDR) — من غير فكّ الصورة.
({int w, int h, int colorType}) _ihdr(Uint8List b) {
  final d = ByteData.sublistView(b);
  return (w: d.getUint32(16), h: d.getUint32(20), colorType: b[25]);
}

void main() {
  group('الرسومات', () {
    test('كل نوع ليه رسمة موجودة، و«تاني» ومن غير نوع = العامة', () {
      for (final f in MedicineForm.values) {
        final path = MedTypeArt.assetFor(f);
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      expect(MedTypeArt.assetFor(null), 'assets/med_types/generic.png');
      expect(MedTypeArt.assetFor(MedicineForm.other), 'assets/med_types/generic.png');
      // كل نوع غير «تاني» ليه رسمته هو، مش العامة
      final own = {for (final f in MedicineForm.values) if (f != MedicineForm.other) MedTypeArt.assetFor(f)};
      expect(own.length, MedicineForm.values.length - 1);
      expect(own, isNot(contains('assets/med_types/generic.png')));
    });

    test('التسعة: مربع ٥١٢ بشفافية وخفاف — والفولدر مفيهوش غيرهم', () {
      final files = Directory('assets/med_types').listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList();
      expect(files, hasLength(9));
      for (final f in files) {
        final bytes = f.readAsBytesSync();
        final h = _ihdr(bytes);
        expect((h.w, h.h), (512, 512), reason: f.path);
        expect(h.colorType, 6, reason: '${f.path}: لازم RGBA (شفافية)');
        expect(bytes.length, lessThan(200 * 1024), reason: f.path);
      }
    });

    test('pubspec بيحزّم الفولدر', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/med_types/'));
    });

    // المالك بعد ما شافها على الموبايل: الرسمة نضيفة زي الأصل في كل مقاس —
    // من غير اسم ولا أي كلام عليها. الاسم مكتوب جنبها.
    for (final size in [56.0, 120.0, 180.0]) {
      testWidgets('رسمة ${size.round()}: نضيفة — ولا نص عليها', (tester) async {
        await tester.pumpWidget(_host(MedTypeArt(form: MedicineForm.tablet, size: size)));
        final art = find.byKey(const ValueKey('med-type-art-tablet'));
        expect(art, findsOneWidget);
        expect(tester.getSize(art), Size(size, size));
        expect(find.descendant(of: art, matching: find.byType(Text)), findsNothing);
        expect(find.descendant(of: art, matching: find.byType(Image)), findsOneWidget);
      });
    }

    testWidgets('MedPhotoThumb كبيرة من غير صورة: الرسمة من غير الاسم', (tester) async {
      await tester.pumpWidget(_host(const MedPhotoThumb(path: null, name: 'Concor 5 mg', form: MedicineForm.syrup, size: 180)));
      expect(find.byKey(const ValueKey('med-type-art-syrup')), findsOneWidget);
      expect(find.text('Concor 5 mg'), findsNothing);
    });

    testWidgets('MedPhotoThumb من غير صورة ومن غير بديل: الرسمة بنوعها', (tester) async {
      await tester.pumpWidget(_host(const MedPhotoThumb(path: null, name: 'Concor 5 mg', form: MedicineForm.capsule, size: 56)));
      expect(find.byKey(const ValueKey('med-type-art-capsule')), findsOneWidget);
    });

    testWidgets('MedPhotoThumb ببديل صريح: البديل زي ما كان (الشاشات الحالية ما اتغيّرتش)', (tester) async {
      await tester.pumpWidget(_host(const MedPhotoThumb(path: null, name: 'Concor', fallback: SizedBox(key: ValueKey('old-fallback')))));
      expect(find.byKey(const ValueKey('old-fallback')), findsOneWidget);
      expect(find.byType(MedTypeArt), findsNothing);
    });
  });

  group('الأغراض', () {
    test('بصيغة «لل»، والتلاتة اللي ما بتركبش عليهم أسامي (قرار المالك)', () {
      expect({for (final p in MedicationPurpose.values) p: p.label}, {
        MedicationPurpose.pressure: 'للضغط',
        MedicationPurpose.sugar: 'للسكر',
        MedicationPurpose.heart: 'للقلب',
        MedicationPurpose.stomach: 'للمعدة والقولون',
        MedicationPurpose.cholesterol: 'للكوليسترول',
        MedicationPurpose.vitamins: 'فيتامينات',
        MedicationPurpose.antibiotic: 'مضاد حيوي',
        MedicationPurpose.eye: 'للعين',
        MedicationPurpose.skin: 'للجلد',
        MedicationPurpose.other: 'حاجة تانية',
      });
    });

    test('الاسم المخزّن ما اتغيّرش، والجديدين بيتقروا', () {
      expect(MedicationPurpose.fromStorage('pressure'), MedicationPurpose.pressure);
      expect(MedicationPurpose.fromStorage('eye'), MedicationPurpose.eye);
      expect(MedicationPurpose.fromStorage('skin'), MedicationPurpose.skin);
    });

    test('«كلّمني» بيفهم الغرض بكلمته من غير «لل»', () {
      const names = ['Systane', 'Fucidin', 'Concor'];
      final purposes = {
        'Systane': MedicationPurpose.eye.word,
        'Fucidin': MedicationPurpose.skin.word,
        'Concor': MedicationPurpose.pressure.word,
      };
      expect(matchMedication('دوا العين', names, purposes: purposes).names, ['Systane']);
      expect(matchMedication('كريم الجلد', names, purposes: purposes).names, ['Fucidin']);
      expect(matchMedication('دوا الضغط', names, purposes: purposes).names, ['Concor']);
    });
  });
}
