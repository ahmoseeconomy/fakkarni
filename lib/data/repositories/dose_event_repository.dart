import 'package:drift/drift.dart';

import '../../domain/escalation/escalation_ladder.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../db/app_database.dart';
import '../dose_state.dart';
import '../services/reminder_plan.dart' show doneKey;

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

  /// مفاتيح الجرعات اللي اتقفلت (اتاخدت أو اتخطّت) من يوم [from] وامبارحه.
  ///
  /// الجدولة بتستخدمها عشان ما تعيدش تذكير على جرعة اتأكدت بدري. الجدول
  /// صغير (بيت واحد)، فبنقرا الأحداث المقفولة ونصفّي في دارت.
  Future<Set<String>> doneKeys({required DateTime from}) async {
    final since = DateTime(from.year, from.month, from.day - 1);
    final rows = await (_db.select(_db.doseEvents)
          ..where(
            (t) => t.state.isInValues([DoseState.taken, DoseState.skipped]),
          ))
        .get();
    return {
      for (final row in rows)
        if (!row.routineDay.isBefore(since))
          doneKey(row.doseScheduleId.toString(), row.routineDay),
    };
  }

  /// قرار المهلة: أي جرعة «لسه» عدّى على معادها [graceWindow] بتتكتب «اتنست».
  ///
  /// بترجع عدد اللي اتكتب. `actedAt` بتفضل null — محدش عمل حاجة، وده
  /// بالظبط اللي الصف بيسجّله. الحالة مش نهائية: «أخدته» بعدها بتكتب فوقها
  /// عادي، هو نسي وبعدين افتكر، ما فشلش.
  Future<int> sweepMissed({required DateTime now}) {
    // «اتنست» ⇔ scheduledAt + المهلة ≤ الآن ⇔ scheduledAt ≤ الآن − المهلة
    final cutoff = DateTime(now.year, now.month, now.day, now.hour,
        now.minute - graceWindow.inMinutes, now.second);
    return (_db.update(_db.doseEvents)
          ..where(
            (t) =>
                t.state.equalsValue(DoseState.pending) &
                t.scheduledAt.isSmallerOrEqualValue(cutoff),
          ))
        .write(const DoseEventsCompanion(state: Value(DoseState.missed)));
  }

  Future<void> markTaken(int doseScheduleId, DateTime routineDay) =>
      _setState(doseScheduleId, routineDay, DoseState.taken);

  Future<void> markSkipped(int doseScheduleId, DateTime routineDay) =>
      _setState(doseScheduleId, routineDay, DoseState.skipped);

  /// بيسجّل تأكيد جرعة واحدة، حتى لو صف اليوم لسه ما اتنزّلش.
  ///
  /// ده **الوعد** بتاع ضغطة «أخدته» على شاشة القفل، معزول في أصغر كتابة
  /// ممكنة: صف واحد يتزرع لو ناقص، وحالته تتكتب — معاملة من جملتين.
  ///
  /// ليه مش `materializeDay` وبعدها `markTaken` زي الأول: تنزيل اليوم
  /// بيكتب صفوف اليوم كله في معاملة واحدة، وهي أكبر بكتير وأكتر عرضة
  /// لتعارض القفل مع الـisolate التاني. ولمّا كانت بتقع، `markTaken` ما
  /// كانتش بتوصل أصلاً — يعني التأكيد نفسه بيضيع عشان كتابة **مش** هي
  /// الوعد. باقي اليوم بيتنزّل في `rescheduleAll` بعد كده، وهي مجاملة
  /// مسموح لها تفشل.
  Future<void> confirmDose({
    required int doseScheduleId,
    required DateTime routineDay,
    required DateTime scheduledAt,
    required DoseState state,
  }) async {
    final day = DateTime(routineDay.year, routineDay.month, routineDay.day);
    await _db.transaction(() async {
      await _db.into(_db.doseEvents).insert(
            DoseEventsCompanion.insert(
              doseScheduleId: doseScheduleId,
              routineDay: day,
              scheduledAt: scheduledAt,
              state: DoseState.pending,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await _setState(doseScheduleId, day, state);
    });
  }

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
