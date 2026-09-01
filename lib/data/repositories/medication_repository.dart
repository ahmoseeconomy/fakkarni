import 'package:drift/drift.dart';

import '../../domain/scheduling/dose_schedule.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import '../mappers.dart';

/// الأدوية وجرعاتها.
class MedicationRepository {
  MedicationRepository(this._db);

  final AppDatabase _db;

  JoinedSelectStatement<HasResultSet, dynamic> _activeQuery(int patientId) =>
      _db.select(_db.doseSchedules).join([
        innerJoin(
          _db.medications,
          _db.medications.id.equalsExp(_db.doseSchedules.medicationId),
        ),
        // الساعة الثابتة في جدولها لوحدها — بتيجي null لجرعات المراسي.
        leftOuterJoin(
          _db.fixedTimings,
          _db.fixedTimings.doseScheduleId.equalsExp(_db.doseSchedules.id),
        ),
      ])
        ..where(
          _db.medications.patientId.equals(patientId) &
              _db.medications.stoppedAt.isNull(),
        );

  List<DoseSchedule> _map(List<TypedResult> rows) => [
        for (final row in rows)
          doseScheduleFromRow(
            row.readTable(_db.doseSchedules),
            row.readTable(_db.medications),
            fixed: row.readTableOrNull(_db.fixedTimings),
          ),
      ];

  Stream<List<DoseSchedule>> watchActiveSchedules(int patientId) =>
      _activeQuery(patientId).watch().map(_map);

  Future<List<DoseSchedule>> activeSchedules(int patientId) async =>
      _map(await _activeQuery(patientId).get());

  /// بيضيف دوا بجرعة واحدة. الجدول بيسمح بأكتر من جرعة للدوا الواحد،
  /// وشاشة الإضافة في المرحلة دي بتعمل واحدة.
  Future<int> addMedication({
    required int patientId,
    required String name,
    required DoseTiming timing,
    required DateTime startDate,
    String? amountLabel,
    DoseRepeat repeat = DoseRepeat.daily,
    int? durationDays,
  }) =>
      _db.transaction(() async {
        final medicationId = await _db.into(_db.medications).insert(
              MedicationsCompanion.insert(
                patientId: patientId,
                name: name,
                amountLabel: Value(amountLabel),
              ),
            );
        await _insertSchedule(
          medicationId,
          timing: timing,
          startDate: startDate,
          repeat: repeat,
          durationDays: durationDays,
        );
        return medicationId;
      });

  /// بيضيف جرعة تانية لدوا موجود.
  ///
  /// الدوا اللي بيتاخد ٣ مرات في اليوم هو الحالة العادية مش الاستثناء —
  /// الجدول بيسمح بيها من الأول، ودي الطريقة اللي بتتكتب بيها.
  Future<int> addDoseSchedule(
    int medicationId, {
    required DoseTiming timing,
    required DateTime startDate,
    DoseRepeat repeat = DoseRepeat.daily,
    int? durationDays,
  }) =>
      _db.transaction(
        () => _insertSchedule(
          medicationId,
          timing: timing,
          startDate: startDate,
          repeat: repeat,
          durationDays: durationDays,
        ),
      );

  /// الكتابة الوحيدة لصف جرعة: النوع بيتكتب مع الصف، والساعة الثابتة في
  /// جدولها — في نفس المعاملة، فمفيش صف `fixed` من غير ساعة ولا العكس.
  Future<int> _insertSchedule(
    int medicationId, {
    required DoseTiming timing,
    required DateTime startDate,
    required DoseRepeat repeat,
    required int? durationDays,
  }) async {
    final day = DateTime(startDate.year, startDate.month, startDate.day);

    final id = await _db.into(_db.doseSchedules).insert(
          switch (timing) {
            AnchorTiming(:final anchor, :final offsetMinutes) =>
              DoseSchedulesCompanion.insert(
                medicationId: medicationId,
                timingKind: const Value(DoseTimingKind.anchor),
                anchor: Value(anchor),
                offsetMinutes: Value(offsetMinutes),
                repeat: repeat,
                startDate: day,
                // null = مدة مفتوحة. ما بنخمّنش مدة أبداً.
                durationDays: Value(durationDays),
              ),
            FixedTiming() => DoseSchedulesCompanion.insert(
                medicationId: medicationId,
                timingKind: const Value(DoseTimingKind.fixed),
                repeat: repeat,
                startDate: day,
                durationDays: Value(durationDays),
              ),
          },
        );

    if (timing case FixedTiming(:final minuteOfDay)) {
      await _db.into(_db.fixedTimings).insert(
            FixedTimingsCompanion.insert(
              doseScheduleId: Value(id),
              minuteOfDay: minuteOfDay.minutes,
            ),
          );
    }
    return id;
  }

  /// بيوقف دوا — **بإيد إنسان وبس**.
  ///
  /// مفيش أي مسار تاني في التطبيق بيكتب في `stoppedAt`. مدة مفتوحة معناها
  /// التذكير يفضل شغال لحد ما حد يقرر يوقفه.
  Future<void> stopMedication(int medicationId) =>
      (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
          .write(MedicationsCompanion(stoppedAt: Value(DateTime.now())));

  Stream<List<MedicationRow>> watchMedications(int patientId) =>
      (_db.select(_db.medications)
            ..where((t) => t.patientId.equals(patientId)))
          .watch();
}
