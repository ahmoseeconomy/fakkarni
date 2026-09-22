// **«الدوا ده عندك خلاص؟»** — علبة تانية من نفس الدوا بتتضاف كدوا جديد
// معناها تذكيرين في اليوم لنفس المادة، والراجل بياخد الاتنين.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/medication/duplicate_check.dart';

void main() {
  const list = [
    ExistingMedicine(name: 'Concor 5mg', activeIngredient: 'Bisoprolol fumarate'),
    ExistingMedicine(name: 'Panadol', activeIngredient: 'Paracetamol'),
    // دوا اتضاف بالإيد — ماحدش قال مادته
    ExistingMedicine(name: 'Telfast 180 mg'),
  ];

  group('نفس الاسم', () {
    test('نفس الاسم بالحرف بيتمسك', () {
      final match = findDuplicate(name: 'Concor 5mg', existing: list);
      expect(match?.kind, DuplicateKind.name);
      expect(match!.message, 'الدوا ده عندك في القايمة باسم «Concor 5mg».');
    });

    test('**وتركيز مختلف برضه نفس الدوا** — ده اللي بيحصل فعلاً', () {
      // بيشتري علبة ١٠ وعنده ٥ — نفس الدوا، ولو اتضاف بيبقى جرعتين.
      final match = findDuplicate(name: 'Concor 10 mg', existing: list);
      expect(match?.kind, DuplicateKind.name);
      expect(match!.existing, 'Concor 5mg');
    });

    test('وحروف كبيرة وصغيرة ومسافات زيادة مش فرق', () {
      expect(findDuplicate(name: '  concor   5 MG ', existing: list)?.kind,
          DuplicateKind.name);
    });

    test('ودوا تاني خالص مش بيتمسك', () {
      expect(findDuplicate(name: 'Augmentin 1g', existing: list), isNull);
    });
  });

  group('نفس المادة الفعّالة', () {
    test('اسمين مختلفين ونفس المادة — الحالة الخطرة', () {
      final match = findDuplicate(
        name: 'Paramol 500',
        activeIngredient: 'Paracetamol',
        existing: list,
      );
      expect(match?.kind, DuplicateKind.ingredient);
      expect(match!.message, 'نفس المادة الفعّالة (Paracetamol) عندك في «Panadol».');
    });

    test('**ومادة مش متسجّلة مش «مادة مختلفة»** — بنعدّي عليها بدل ما ندّعي', () {
      // Telfast مالوش مادة متسجّلة؛ علبة fexofenadine ما بتتمسكش، وده
      // حد الفحص المكتوب مش عيب مخبّي.
      expect(
        findDuplicate(
          name: 'Fexo 180',
          activeIngredient: 'Fexofenadine',
          existing: list,
        ),
        isNull,
      );
    });

    test('ومن غير مادة في اللي داخل مفيش مقارنة مادة', () {
      expect(findDuplicate(name: 'Paramol 500', existing: list), isNull);
    });

    test('والاسم بيسبق المادة — هو اللي بيعرف يربطه', () {
      final match = findDuplicate(
        name: 'Panadol',
        activeIngredient: 'Paracetamol',
        existing: list,
      );
      expect(match?.kind, DuplicateKind.name, reason: 'الاسم أول حاجة بيقراها');
    });

    test('و«Panadol Extra» منتج تاني — بس المادة بتمسكه', () {
      // **مش نفس الاسم عن قصد**: «إكسترا» تركيبة تانية، ومعاملتها كنفس
      // الدوا بالاسم كانت هتبقى تخمين عن منتج. المادة المشتركة هي
      // الحقيقة اللي عندنا، وهي اللي بتتقال.
      final match = findDuplicate(
        name: 'Panadol Extra',
        activeIngredient: 'Paracetamol',
        existing: list,
      );
      expect(match?.kind, DuplicateKind.ingredient);
      expect(match!.existing, 'Panadol');
    });
  });

  group('التطبيع', () {
    test('بيشيل التركيز ووحدته ويسيب الاسم', () {
      expect(normaliseMedicineName('Concor 5mg'), 'concor');
      expect(normaliseMedicineName('Telfast 180 mg'), 'telfast');
      expect(normaliseMedicineName('Augmentin 1g'), 'augmentin');
    });

    test('وبيشيل التشكيل والتطويل العربي', () {
      expect(normaliseMedicineName('كونــكور ٥ مجم'), normaliseMedicineName('كونكور'));
    });

    test('واسم كله تركيز بيرجع فاضي — ومفيش تطابق على فراغ', () {
      expect(normaliseMedicineName('500 mg'), '');
      expect(
        findDuplicate(
          name: '500 mg',
          existing: const [ExistingMedicine(name: '5 mg')],
        ),
        isNull,
        reason: 'اسمين فاضيين بعد التطبيع مش نفس الدوا',
      );
    });
  });
}
