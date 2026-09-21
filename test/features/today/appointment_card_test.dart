import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/db/tables.dart' show RecordKind;
import 'package:fakkarni/data/services/appointment_card.dart';
import 'package:fakkarni/domain/health/follow_display.dart';

/// **الكارت الثابت — شبكة الأمان بتاعة نافذة iOS.**
///
/// الإشعارات ممكن تكون لسه برّه النافذة؛ الكارت بيعرض الميعاد على أي
/// حال. دوال نقية هنا، فالترتيب والعدّ التنازلي بيتختبروا بالأرقام.
RecordRow _row({
  required int id,
  required String title,
  int stage = 2,
  String? followKind,
  DateTime? labBookingAt,
  DateTime? doctorVisitAt,
  DateTime? deletedAt,
}) =>
    RecordRow(
      id: id,
      uuid: 'u$id',
      patientId: 1,
      kind: followKind == 'visit' ? RecordKind.visit : RecordKind.lab,
      title: title,
      happenedAt: DateTime(2026, 9, 1),
      checkupStage: stage,
      followKind: followKind,
      labBookingAt: labBookingAt,
      doctorVisitAt: doctorVisitAt,
      deletedAt: deletedAt,
      updatedAtMs: 0,
    );

final _now = DateTime(2026, 9, 15, 10);

void main() {
  group('العدّ التنازلي', () {
    test('النهارده، بكرة، بعد بكرة، وبعد كذا يوم', () {
      expect(countdownWord(_now, DateTime(2026, 9, 15, 7)), 'النهارده');
      expect(countdownWord(_now, DateTime(2026, 9, 16, 7)), 'بكرة');
      expect(countdownWord(_now, DateTime(2026, 9, 17, 7)), 'بعد بكرة');
      expect(countdownWord(_now, DateTime(2026, 9, 18, 7)), 'بعد ٣ أيام');
    });

    test('بأيام تقويمية — ميعاد بعد ٢٠ ساعة بكرة، مش «النهارده»', () {
      expect(countdownWord(DateTime(2026, 9, 15, 23), DateTime(2026, 9, 16, 7)), 'بكرة');
    });
  });

  group('اللي بيتعرض', () {
    test('الأقرب الأول', () {
      final list = upcomingAppointments(
        [
          _row(id: 2, title: 'الأبعد', labBookingAt: DateTime(2026, 9, 25, 7)),
          _row(id: 1, title: 'الأقرب', labBookingAt: DateTime(2026, 9, 18, 7)),
        ],
        now: _now,
      );
      expect([for (final a in list) a.title], ['الأقرب', 'الأبعد']);
    });

    test('يوم الميعاد نفسه بيفضل معروض لحد آخره — هو رايح النهارده', () {
      final list = upcomingAppointments(
        [_row(id: 1, title: 'النهارده', labBookingAt: DateTime(2026, 9, 15, 7))],
        now: DateTime(2026, 9, 15, 18),
      );
      expect(list, hasLength(1));
      expect(countdownWord(DateTime(2026, 9, 15, 18), list.single.at), 'النهارده');
    });

    test('ميعاد عدّى يومه بيختفي', () {
      final list = upcomingAppointments(
        [_row(id: 1, title: 'قديم', labBookingAt: DateTime(2026, 9, 14, 7))],
        now: _now,
      );
      expect(list, isEmpty);
    });

    test('المرحلة لما تعدّي بيختفي — نفس قاعدة الإشعار', () {
      // المرحلة ٥ = «انتظار النتيجة»: ميعاد المعمل بقى بلا معنى
      final list = upcomingAppointments(
        [_row(id: 1, title: 'صورة دم', stage: 5, labBookingAt: DateTime(2026, 9, 20, 7))],
        now: _now,
      );
      expect(list, isEmpty);
    });

    test('الممسوح ما بيظهرش', () {
      final list = upcomingAppointments(
        [
          _row(
            id: 1,
            title: 'ممسوح',
            labBookingAt: DateTime(2026, 9, 20, 7),
            deletedAt: DateTime(2026, 9, 14),
          ),
        ],
        now: _now,
      );
      expect(list, isEmpty);
    });

    test('الكلمة بتقول ده إيه', () {
      final lab = upcomingAppointments(
        [_row(id: 1, title: 'صورة دم', labBookingAt: DateTime(2026, 9, 20, 7))],
        now: _now,
      );
      expect(lab.single.headline, 'ميعاد المعمل');

      final visit = upcomingAppointments(
        [
          _row(
            id: 2,
            title: 'الضغط',
            stage: 1,
            followKind: 'visit',
            doctorVisitAt: DateTime(2026, 9, 21, 10),
          ),
        ],
        now: _now,
      );
      expect(visit.single.headline, 'زيارة الدكتور');
    });
  });
}
