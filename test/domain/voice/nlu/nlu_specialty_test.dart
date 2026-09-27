import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/places/specialty.dart';
import 'package:fakkarni/domain/voice/nlu/nlu.dart';

void main() {
  final now = DateTime(2026, 9, 27, 10);
  NluResult u(String s) => understandUtterance(s, now: now);

  group('«أقرب دكتور …» → find_nearby {place: doctor, specialty}', () {
    for (final (said, sp) in [
      ('أقرب دكتور عيون', Specialty.eyes),
      ('عايز دكتور أسنان', Specialty.dental),
      ('فين أقرب دكتور أطفال', Specialty.children),
      ('دورلي على دكتور عظام قريب', Specialty.bones),
      ('محتاج دكتور جلدية', Specialty.skin),
      ('أقرب دكتور باطنة', Specialty.internal),
      ('عايزة دكتورة نسا قريبة', Specialty.women),
      ('أقرب دكتور قلب', Specialty.heart),
      ('عايز دكتور أنف وأذن', Specialty.ent),
      ('أقرب دكتور مخ وأعصاب', Specialty.neuro),
      ('أقرب دكتور مسالك', Specialty.urology),
      ('أقرب عيادة أسنان', Specialty.dental),
      ('أقرب دكتور رمد', Specialty.eyes),
    ]) {
      test(said, () {
        final r = u(said);
        expect(r.intent, NluIntent.findNearby, reason: '$r');
        expect(r.place, NearbyPlace.doctor);
        expect(r.specialtyKind, sp);
      });
    }

    test('من غير تخصص = دكتور وبس', () {
      final r = u('أقرب دكتور');
      expect(r.intent, NluIntent.findNearby);
      expect(r.specialtyKind, isNull);
    });

    test('صيدلية ما بتاخدش تخصص', () {
      final r = u('أقرب صيدلية');
      expect(r.place, NearbyPlace.pharmacy);
      expect(r.specialtyKind, isNull);
    });

    test('«احجزلي عند دكتور عيون» حجز، مش «القريب مني»', () {
      final r = u('احجزلي ميعاد عند دكتور عيون بكرة');
      expect(r.intent, NluIntent.bookAppointment);
      expect(r.specialty, 'عيون');
      expect(r.doctorName, isNull, reason: '«عيون» تخصص مش اسم');
    });
  });
}
