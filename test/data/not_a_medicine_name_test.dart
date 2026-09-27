// آخر حاجز: القاعدة نفسها ما بتكتبش «لا» اسم دوا — من «كلّمني» أو الممرض أو أي باب.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';

void main() {
  test('«لا» و«أيوه» و«مش عارف» بيترفضوا قبل أي صف', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final patientId = await PatientRepository(db).ensurePatient();
    final meds = MedicationRepository(db);
    for (final name in ['لا', 'أيوه', 'مش عارف', 'آه']) {
      expect(
        () => meds.addMedication(
          patientId: patientId,
          name: name,
          timing: FixedTiming(MinuteOfDay.hm(9)),
          startDate: DateTime(2026, 9, 27),
        ),
        throwsArgumentError,
        reason: name,
      );
    }
    expect(await db.select(db.medications).get(), isEmpty);
    await meds.addMedication(
      patientId: patientId,
      name: 'Concor 5mg',
      timing: FixedTiming(MinuteOfDay.hm(9)),
      startDate: DateTime(2026, 9, 27),
    );
    expect(await db.select(db.medications).get(), hasLength(1));
  });
}
