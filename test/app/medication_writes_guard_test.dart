import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **ولا شاشة بتكتب دوا أو مواعيده بنفسها** — كله بيعدّي على
/// `MedicationSaveService` (`services.medicationSaves`)، اللي بيعيد الجدولة
/// بعد كل كتابة. شاشة بتكتب في المستودع أو في الجدول على طول هي بالظبط
/// الشكل اللي ساب دوا محفوظ من غير ولا تذكير.
void main() {
  const mutators = [
    'addDoseSchedule',
    'addMedication',
    'addMedicationWithDoses',
    'addMedicationsWithDoses',
    'removeMedication',
    'resumeMedication',
    'setAlertMode',
    'stopDoseSchedule',
    'stopMedication',
    'updateAmount',
    'updateDetails',
    'updateMealRelation',
    'updateTiming',
  ];

  // المستقبِل `medications` (المستودع) — مش `medicationSaves`
  final viaRepository = RegExp(r'\bmedications\s*\.\s*(' + mutators.join('|') + r')\s*\(');
  // `MedPhotos(...).removeMedication(services.medications, …)` — الشيل من ورا الخدمة
  final viaPhotos = RegExp(r'removeMedication\(\s*[\w.]*medications\s*,');
  // كتابة مباشرة في الجداول
  final direct = RegExp(r'\b(into|update|delete)\(\s*[\w.]*\.(medications|doseSchedules|fixedTimings)\s*\)');
  final newRepository = RegExp(r'\bMedicationRepository\(');

  List<String> offenders(String source) => [
        for (final re in [viaRepository, viaPhotos, direct, newRepository])
          for (final m in re.allMatches(source)) m.group(0)!,
      ];

  String code(File f) =>
      f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('ولا ملف في lib/features بيكتب في الأدوية أو المواعيد من غير الخدمة', () {
    final found = <String>[];
    for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final o in offenders(code(f))) {
        found.add('${f.path}: $o');
      }
    }
    expect(found, isEmpty, reason: 'اكتب من services.medicationSaves');
  });

  test('الحارس بيمسك الأشكال التلاتة فعلاً — مش حارس فاضي', () {
    expect(offenders('await services.medications.updateTiming(1, t);'), isNotEmpty);
    expect(offenders('await services.medications\n    .addMedicationWithDoses(patientId: 1);'), isNotEmpty);
    expect(offenders('MedPhotos(db, store).removeMedication(services.medications, id);'), isNotEmpty);
    expect(offenders('db.update(db.doseSchedules)..where((t) => t.id.equals(1));'), isNotEmpty);
    expect(offenders('_db.into(_db.fixedTimings).insert(x);'), isNotEmpty);
    expect(offenders('final r = MedicationRepository(db);'), isNotEmpty);
    // القراية مسموحة، والخدمة مسموحة
    expect(offenders('services.medications.schedulesFor(1); services.medicationSaves.updateTiming(1, t);'), isEmpty);
    expect(offenders('services.preferences.setAlertMode(mode);'), isEmpty);
  });

  test('الخدمة بتعيد الجدولة بعد كل كتابة', () {
    final src = File('lib/data/services/medication_save_service.dart').readAsStringSync();
    expect(src, contains('scheduler.rescheduleAll()'));
    // كل دالة عامة بتعدّي على `_thenSchedule`
    final publics = RegExp(r'\n  Future<[^>]*>+ (\w+)\(').allMatches(src).map((m) => m.group(1)).toList();
    expect(publics, isNotEmpty);
    for (final name in publics) {
      final body = src.substring(src.indexOf(' $name('));
      final next = body.indexOf('\n  Future<', 1);
      final chunk = next < 0 ? body : body.substring(0, next);
      expect(chunk, contains('_thenSchedule'), reason: '$name بتكتب من غير جدولة');
    }
  });
}
