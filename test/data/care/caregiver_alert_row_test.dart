import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/supabase_caregiver_remote.dart';

/// شكل صف escalations زي ما PostgREST بيرجّعه بالـembed المتداخل.
Map<String, dynamic> row({String status = 'sent', String? sentAt}) => {
      'uuid': 'esc-1',
      'delivery_status': status,
      'created_at': '2026-08-31T06:00:00+00:00',
      'sent_at': sentAt,
      'dose_events': {
        'scheduled_at': '2026-08-31T05:00:00+00:00',
        'state': 'taken',
        'dose_schedules': {
          'medications': {'name': 'Concor 5mg', 'patient_uuid': 'p1'},
        },
      },
    };

void main() {
  test('صف مبعوت → اسم الدواء من الـembed، الأوقات محلية، delivered', () {
    final a = alertFromRow(row(sentAt: '2026-08-31T06:00:05+00:00'));
    expect(a.medicationName, 'Concor 5mg');
    expect(a.scheduledAt.toUtc(), DateTime.utc(2026, 8, 31, 5));
    expect(a.sentAt!.toUtc(), DateTime.utc(2026, 8, 31, 6, 0, 5));
    expect(a.delivered, isTrue);
    expect(a.takenLater, isTrue);
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
