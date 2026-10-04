// ٠٠٣٨: نوع الدوا بيطلع مع الدوا، وبيرجع للدائرة، والوحدة عندهم من النوع.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/care/supabase_caregiver_remote.dart' show medicationFromRow;
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';

import '../../support/seeded_clock.dart';
import 'sync_service_test.dart' show FakeSyncRemote;

void main() {
  test('بيطلع مع الدوا وبيرجع للدائرة — والوحدة والمخزون عندهم من النوع', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final patientId = await PatientRepository(db).ensurePatient(name: 'أحمد');
    final meds = MedicationRepository(db, clock: seededLongAgo);
    await meds.addMedicationWithDoses(
        patientId: patientId,
        name: 'Omeprazole',
        amountLabel: 'واحدة',
        timings: [FixedTiming(MinuteOfDay.hm(8))],
        startDate: DateTime(2026, 9, 1),
        form: MedicineForm.capsule);
    await meds.addMedicationWithDoses(
        patientId: patientId,
        name: 'Fucidin',
        timings: [FixedTiming(MinuteOfDay.hm(20))],
        startDate: DateTime(2026, 9, 1),
        form: MedicineForm.ointment);

    final cloud = FakeSyncRemote();
    final sync = SyncService(
        db: db, remote: cloud, hasSession: () => true, localWrites: const Stream.empty(), blockStore: MemorySyncBlockStore());
    await sync.confirmLinked();
    await sync.push();
    final rows = cloud.tables['medications']!.values.toList();
    final omep = rows.firstWhere((r) => r['name'] == 'Omeprazole');
    final fuci = rows.firstWhere((r) => r['name'] == 'Fucidin');
    expect(omep['form'], 'capsule');

    final m = medicationFromRow({...omep, 'dose_schedules': const [], 'medication_stock': {'quantity': 10, 'warn_days': 5}});
    expect(m.form, 'capsule');
    expect(m.stockUnit, 'كبسولة');
    final f = medicationFromRow({...fuci, 'dose_schedules': const [], 'medication_stock': {'quantity': 1, 'warn_days': 5}});
    expect(f.tracksStock, isFalse);
    expect(f.stockLine, isNull, reason: 'مرهم — مفيش سطر مخزون');
    expect(f.stockLow, isFalse);
    await sync.dispose();
  });

  test('«form» عمود اختياري — مشروع قبل ٠٠٣٨ بياخد الصف من غيره', () {
    final src = File('lib/data/sync/sync_service.dart').readAsStringSync();
    expect(src, contains("'medications': {'purpose', 'instructions', 'alert_mode', 'not_bought_at', 'form'}"));
  });

  test('طلب «ضيف» من الممرض بيشيل النوع في الـJSON — مفيش هجرة لده', () {
    const p = MedicationChangePayload(name: 'Omeprazole', form: 'capsule');
    expect(p.toJson()['form'], 'capsule');
    expect(MedicationChangePayload.fromJson(p.toJson()).form, 'capsule');
  });
}
