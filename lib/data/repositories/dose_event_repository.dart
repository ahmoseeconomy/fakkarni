import 'package:drift/drift.dart';

import '../../domain/scheduling/schedule_engine.dart';
import '../db/app_database.dart';
import '../dose_state.dart';

/// سطر جاهز للعرض في شاشة «يومك».
class DoseEventView {
  const DoseEventView({
    required this.doseScheduleId,
    required this.medicationName,
    required this.scheduledAt,
    required this.state,
    this.amountLabel,
    this.actedAt,
  });

  final int doseScheduleId;
  final String medicationName;
  final String? amountLabel;
  final DateTime scheduledAt;
  final DoseState state;
  final DateTime? actedAt;

  bool get isDone => state == DoseState.taken || state == DoseState.skipped;
}

/// أحداث الجرعات — إيه اللي اتاخد وإيه اللي لسه.
class DoseEventRepository {
  DoseEventRepository(this._db);

  final AppDatabase _db;

  /// بينزّل تذكيرات اليوم كأحداث «لسه» لو مكنتش موجودة.
  ///
  /// بيضيف الناقص بس. صف اتقال عليه «اتاخد» عمره ما بيتكتب فوقه، فلو المريض
  /// فتح الشاشة تاني أو غيّر روتينه، تاريخه بيفضل مكانه. اللي بيتحدّث هو
  /// ساعة الاستحقاق للصفوف اللي لسه معلّقة — عشان تمشي ورا الروتين الجديد.
  Future<void> materializeDay(
    DateTime routineDay,
    List<Reminder> reminders,
  ) async {
    final day = DateTime(routineDay.year, routineDay.month, routineDay.day);

    await _db.transaction(() async {
      for (final reminder in reminders) {
        for (final dose in reminder.doses) {
          final scheduleId = int.parse(dose.id);

          await _db.into(_db.doseEvents).insert(
                DoseEventsCompanion.insert(
                  doseScheduleId: scheduleId,
                  routineDay: day,
                  scheduledAt: reminder.at,
                  state: DoseState.pending,
                ),
                mode: InsertMode.insertOrIgnore,
              );

          await (_db.update(_db.doseEvents)
                ..where(
                  (t) =>
                      t.doseScheduleId.equals(scheduleId) &
                      t.routineDay.equalsValue(day) &
                      t.state.equalsValue(DoseState.pending),
                ))
              .write(DoseEventsCompanion(scheduledAt: Value(reminder.at)));
        }
      }
    });
  }

  Stream<List<DoseEventView>> watchDay(DateTime routineDay) {
    final day = DateTime(routineDay.year, routineDay.month, routineDay.day);

    final query = _db.select(_db.doseEvents).join([
      innerJoin(
        _db.doseSchedules,
        _db.doseSchedules.id.equalsExp(_db.doseEvents.doseScheduleId),
      ),
      innerJoin(
        _db.medications,
        _db.medications.id.equalsExp(_db.doseSchedules.medicationId),
      ),
    ])
      ..where(_db.doseEvents.routineDay.equalsValue(day))
      ..orderBy([OrderingTerm.asc(_db.doseEvents.scheduledAt)]);

    return query.watch().map((rows) {
      return [
        for (final row in rows)
          () {
            final event = row.readTable(_db.doseEvents);
            final med = row.readTable(_db.medications);
            return DoseEventView(
              doseScheduleId: event.doseScheduleId,
              medicationName: med.name,
              amountLabel: med.amountLabel,
              scheduledAt: event.scheduledAt,
              state: event.state,
              actedAt: event.actedAt,
            );
          }(),
      ];
    });
  }

  Future<void> markTaken(int doseScheduleId, DateTime routineDay) =>
      _setState(doseScheduleId, routineDay, DoseState.taken);

  Future<void> markSkipped(int doseScheduleId, DateTime routineDay) =>
      _setState(doseScheduleId, routineDay, DoseState.skipped);

  Future<void> _setState(
    int doseScheduleId,
    DateTime routineDay,
    DoseState state,
  ) async {
    final day = DateTime(routineDay.year, routineDay.month, routineDay.day);
    await (_db.update(_db.doseEvents)
          ..where(
            (t) =>
                t.doseScheduleId.equals(doseScheduleId) &
                t.routineDay.equalsValue(day),
          ))
        .write(
      DoseEventsCompanion(
        state: Value(state),
        actedAt: Value(DateTime.now()),
      ),
    );
  }
}
