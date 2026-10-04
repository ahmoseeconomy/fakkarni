// نوع الدوا (طلب المدير، ٤ أكتوبر ٢٠٢٦): القايمة واحدة في دارت وSQL، والنوع
// هو اللي بيقول وحدة المخزون — والمرهم والبخاخة مالهمش مخزون (قرار المالك).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/domain/medication/stock.dart';

void main() {
  test('القايمة في دارت = قيد medications_form_check في 0038 بالحرف', () {
    final sql = File('supabase/migrations/0038_medicine_form.sql').readAsStringSync();
    final m = RegExp(r"form in\s*\(([^)]*)\)").firstMatch(sql)!;
    final inSql = RegExp(r"'(\w+)'").allMatches(m[1]!).map((x) => x[1]).toSet();
    expect(inSql, MedicineForm.values.map((f) => f.wire).toSet());
  });

  test('الكلمات على الشرايح — اللي المالك وافق عليها', () {
    expect(MedicineForm.values.map((f) => f.label),
        ['قرص', 'كبسولة', 'حقنة', 'مرهم', 'شراب', 'نقط', 'بخاخة', 'لبوس', 'تاني']);
  });

  test('النوع بيكسب كلام الجرعة في وحدة المخزون', () {
    expect(stockUnitOfMedication('قرص واحد', 'capsule'), 'كبسولة');
    expect(stockUnitOfMedication('٢ ملعقة', null), 'ملعقة', reason: 'من غير نوع = زي الأول');
    expect(stockUnitOfMedication('قرص', 'other'), 'قرص', reason: '«تاني» ما بيقولش وحدة');
    expect(resolveStockUnit(null, form: MedicineForm.drops), 'نقط');
    expect(resolveStockUnit(null), isNull, reason: 'لسه هنسأله — مش بنخمّن');
  });

  test('المرهم والبخاخة مالهمش مخزون — والباقي ليه', () {
    expect(formTracksStock('ointment'), isFalse);
    expect(formTracksStock('inhaler'), isFalse);
    expect(formTracksStock('tablet'), isTrue);
    expect(formTracksStock(null), isTrue, reason: 'القديم زي ما هو');
  });

  group('من كلمة العلبة', () {
    final cases = <String, MedicineForm?>{
      'Film-coated tablets': MedicineForm.tablet,
      '20 Capsules': MedicineForm.capsule,
      'أقراص مغلفة': MedicineForm.tablet,
      'Oral suspension': MedicineForm.syrup,
      'Eye drops': MedicineForm.drops,
      'Topical cream': MedicineForm.ointment,
      'Inhaler 200 doses': MedicineForm.inhaler,
      'Ampoules for injection': MedicineForm.injection,
      'Suppositories': MedicineForm.suppository,
      'Sachets': null,
      '': null,
    };
    for (final e in cases.entries) {
      test('«${e.key}» → ${e.value?.label ?? 'مش واضح'}', () {
        expect(MedicineForm.fromPackageText(e.key), e.value);
      });
    }
  });
}
