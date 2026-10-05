import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/supabase_caregiver_remote.dart';

/// شكل صف escalations زي ما PostgREST بيرجّعه بالـembed المتداخل.
Map<String, dynamic> row({String status = 'sent', String? sentAt, String state = 'missed'}) => {
      'uuid': 'esc-1',
      'delivery_status': status,
      'created_at': '2026-08-31T06:00:00+00:00',
      'sent_at': sentAt,
      'dose_events': {
        'scheduled_at': '2026-08-31T05:00:00+00:00',
        'state': state,
        'dose_schedules': {
          'medications': {'name': 'Concor 5mg', 'patient_uuid': 'p1'},
        },
      },
    };

void main() {
  doseRowTests();
  test('صف مبعوت → اسم الدواء من الـembed، الأوقات محلية، delivered', () {
    final a = alertFromRow(row(sentAt: '2026-08-31T06:00:05+00:00'));
    expect(a.medicationName, 'Concor 5mg');
    expect(a.scheduledAt.toUtc(), DateTime.utc(2026, 8, 31, 5));
    expect(a.sentAt!.toUtc(), DateTime.utc(2026, 8, 31, 6, 0, 5));
    expect(a.delivered, isTrue);
    expect(a.open, isTrue, reason: 'missed لسه «ما اتاخدتش»');
  });

  test('الحالة المقفولة مش مفتوحة — خط الدفاع التاني لو صف قديم عدّى', () {
    // الاستعلام بيفلترها في السحابة؛ الجيتر ده بيمسك اللي يعدّي منه.
    for (final closed in ['taken', 'skipped', 'superseded']) {
      expect(alertFromRow(row(state: closed)).open, isFalse, reason: closed);
    }
    expect(alertFromRow(row(state: 'pending')).open, isTrue);
    // واسم مش معروف مش تنبيه — ما بنعرضش حاجة محدش يعرفها
    expect(alertFromRow(row(state: 'حاجة-جديدة')).open, isFalse);
  });

  test('no_token → مش delivered حتى لو الحالة اتقرّرت', () {
    final a = alertFromRow(row(status: 'no_token'));
    expect(a.delivered, isFalse);
    expect(a.sentAt, isNull);
  });

  test('النافذة ٤٨ ساعة', () {
    expect(alertWindow, const Duration(hours: 48));
  });
}

// ================= المرحلة ٤ (٥ أكتوبر ٢٠٢٦): uuid الدوا على صف الجرعة

Map<String, Object?> _doseRow({String? medUuid, String name = 'Concor'}) => {
      'uuid': 'e1',
      'scheduled_at': '2026-08-31T07:00:00Z',
      'state': 'pending',
      'routine_day': '2026-08-31',
      'acted_at': null,
      'dose_schedules': {
        'medications': {'uuid': medUuid, 'name': name, 'amount_label': 'قرص'},
      },
    };

void doseRowTests() {
  test('eventFromRow بيقرا uuid الدوا من الضمّة المتداخلة', () {
    final e = eventFromRow(_doseRow(medUuid: 'm-77'));
    expect(e.medicationUuid, 'm-77');
    expect(e.medicationName, 'Concor');
    expect(e.state, 'pending');
  });

  test('دواءين بنفس الاسم: الربط بالـuuid بيجيب الصح — الاسم كان بيلخبط', () {
    const a = CaregiverMedication(uuid: 'm-a', name: 'Concor 5mg', form: 'tablet');
    const b = CaregiverMedication(uuid: 'm-b', name: 'Concor 5mg', form: 'syrup');
    final dose = eventFromRow(_doseRow(medUuid: 'm-b', name: 'Concor 5mg'));
    expect(medicationForDose([a, b], dose)?.form, 'syrup', reason: 'بالـuuid مش بأول اسم مطابق');
  });

  test('صف قديم من غير uuid: الاسم بديل — والدوا الغايب null مش اختراع', () {
    const a = CaregiverMedication(uuid: 'm-a', name: 'Concor 5mg', form: 'tablet');
    final old = eventFromRow(_doseRow(medUuid: null, name: 'Concor 5mg'));
    expect(old.medicationUuid, isNull);
    expect(medicationForDose([a], old)?.uuid, 'm-a', reason: 'الاسم بديل للصف القديم');
    final stranger = eventFromRow(_doseRow(medUuid: null, name: 'Panadol'));
    expect(medicationForDose([a], stranger), isNull);
  });
}
