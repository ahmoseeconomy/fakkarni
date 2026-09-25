import 'package:drift/drift.dart';

import '../../domain/escalation/escalation_ladder.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../db/app_database.dart';
import '../db/converters.dart';
import 'stock_repository.dart';
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
    this.actedBy,
    this.routineDay,
  });

  final int doseScheduleId;

  /// يوم الروتين بتاع الصف (جرعة ١ بالليل تبع امبارح). null في صفوف
  /// اتبنت يدوي في اختبارات قديمة.
  final DateTime? routineDay;

  /// اسم اللي أكّدها بدال المريض (٠٠٢٣) — null = هو بنفسه.
  final String? actedBy;
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
      final activeFrom = await activeFromOf({
        for (final reminder in reminders)
          for (final dose in reminder.doses) int.parse(dose.id),
      });
      for (final reminder in reminders) {
        for (final dose in reminder.doses) {
          final scheduleId = int.parse(dose.id);

          Expression<bool> thisDose($DoseEventsTable t) =>
              t.doseScheduleId.equals(scheduleId) & t.routineDay.equalsValue(day);

          // جرعة معادها قبل ما القاعدة تبقى سارية ما كانتش موجودة — ما
          // يتعملّهاش صف، فمفيش «نسيتها؟» ولا «اتنست» ولا تنبيه لابنه.
          // ولو كان ليها صف «لسه» من قبل تعديل التوقيت، بيتعلّم «اتغيّرت
          // القاعدة» بدل ما يتمسح: السحابة مفيهاش مسح (دين ١).
          if (reminder.at.isBefore(activeFrom[scheduleId] ?? reminder.at)) {
            await (_db.update(_db.doseEvents)
                  ..where((t) => thisDose(t) & t.state.equalsValue(DoseState.pending)))
                .write(const DoseEventsCompanion(state: Value(DoseState.superseded)));
            continue;
          }

          await _db.into(_db.doseEvents).insert(
                DoseEventsCompanion.insert(
                  doseScheduleId: scheduleId,
                  routineDay: day,
                  scheduledAt: reminder.at,
                  state: DoseState.pending,
                ),
                mode: InsertMode.insertOrIgnore,
              );

          // «اتغيّرت القاعدة» اللي ميعادها الجديد لسه ساري بترجع «لسه» —
          // الحالة دي ما بتتكتبش غير من فوق، فالرجوع ما بيلغيش قرار حد.
          await (_db.update(_db.doseEvents)
                ..where(
                  (t) => thisDose(t) & t.state.isInValues([DoseState.pending, DoseState.superseded]),
                ))
              .write(DoseEventsCompanion(scheduledAt: Value(reminder.at), state: const Value(DoseState.pending)));
        }
      }
    });
  }

  /// لحظة سريان كل قاعدة ([DoseSchedules.activeFrom]) — القواعد اللي من
  /// قبل النسخة ١٥ مش في الخريطة (سارية من الأول).
  Future<Map<int, DateTime>> activeFromOf(Set<int> scheduleIds) async {
    if (scheduleIds.isEmpty) return const {};
    final rows = await (_db.select(_db.doseSchedules)..where((t) => t.id.isIn(scheduleIds))).get();
    return {
      for (final row in rows)
        if (row.activeFrom != null) row.id: row.activeFrom!,
    };
  }

  Stream<List<DoseEventView>> watchDay(DateTime routineDay) {
    final day = DateTime(routineDay.year, routineDay.month, routineDay.day);
    return _watch(_db.doseEvents.routineDay.equalsValue(day));
  }

  /// «التقويم» (D3.7): كل الأحداث اللي معادها في [from, to). بيقرا اللي
  /// اتنزّل فعلاً بس — الأيام اللي لسه ما اتنزّلتش مالهاش صفوف، والشاشة
  /// بتقول كده بدل ما تحسبها بالمحرك.
  Stream<List<DoseEventView>> watchBetween(DateTime from, DateTime to) => _watch(
        _db.doseEvents.scheduledAt.isBiggerOrEqualValue(from) & _db.doseEvents.scheduledAt.isSmallerThanValue(to),
      );

  /// «إنت ماشي إزاي»: كل الأحداث من يوم روتين [from] لحد [to] (الاتنين
  /// داخلين). قراية بس — نفس فلاتر «يومك» (من غير `superseded` ومن غير
  /// الدوا المتشال).
  Stream<List<DoseEventView>> watchRoutineDays(DateTime from, DateTime to) => _watch(
        // العمود نص «YYYY-MM-DD» — بيترتّب زي التاريخ بالظبط
        _db.doseEvents.routineDay.isBiggerOrEqualValue(const DateOnlyConverter().toSql(from)) &
            _db.doseEvents.routineDay.isSmallerOrEqualValue(const DateOnlyConverter().toSql(to)),
      );

  Stream<List<DoseEventView>> _watch(Expression<bool> where) {
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
      // «اتغيّرت القاعدة» مش جرعة — ما بتتعرضش في أي شاشة. والدوا المتشال
      // مالوش وجود: لا في «يومك» ولا في التقويم. الموقوف بيفضل تاريخه
      // ظاهر — أحداثه الجاية اتعلّمت `superseded` وقت الإيقاف.
      ..where(
        where &
            _db.doseEvents.state.equalsValue(DoseState.superseded).not() &
            _db.medications.removedAt.isNull(),
      )
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
              actedBy: event.actedBy,
              routineDay: event.routineDay,
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

  Future<void> markTaken(int doseScheduleId, DateTime routineDay) async {
    await _setState(doseScheduleId, routineDay, DoseState.taken);
    await _flushStock();
  }

  Future<void> markSkipped(int doseScheduleId, DateTime routineDay) async {
    await _setState(doseScheduleId, routineDay, DoseState.skipped);
    await _flushStock();
  }

  /// **إلغاء «اتاخدت»** — الجرعة بترجع مستنية، والمخزون بيرجع. مفيش زرار
  /// ليها في الواجهة لسه؛ الانتقال محسوب هنا عشان أي باب يتفتح بعدين ياخده.
  Future<void> undoTaken(int doseScheduleId, DateTime routineDay) async {
    final day = DateTime(routineDay.year, routineDay.month, routineDay.day);
    final before = await (_db.select(_db.doseEvents)
          ..where((t) => t.doseScheduleId.equals(doseScheduleId) & t.routineDay.equalsValue(day)))
        .getSingleOrNull();
    if (before?.state != DoseState.taken) return;
    await (_db.update(_db.doseEvents)..where((t) => t.id.equals(before!.id)))
        .write(const DoseEventsCompanion(state: Value(DoseState.pending), actedAt: Value(null), actedBy: Value(null)));
    await StockRepository(_db).onDoseStateChanged(doseScheduleId, DoseState.taken, DoseState.pending);
  }

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
    // **المخزون مش هنا**: ده باب شاشة القفل، والإلغاءات (القاعدة ٥) لازم
    // تيجي على طول بعد الصف. المعالج بينده [flushStock] كمجاملة بعدها.
  }

  /// تعديلات المخزون المستنية من [confirmDose] — مجاملة، بعد الإلغاءات.
  Future<void> flushStock() => _flushStock();

  /// تأكيد وصل من السيرفر باسم ممرض (٠٠٢٣). بيكتب `taken` على الحدث
  /// **لو لسه مش مؤكَّد** وبيرجّع ميعاده عشان المُنادي يلغي سلّمه وإعاداته؛
  /// null = الحدث مش هنا، أو اتأكّد قبل كده (المريض بنفسه سبق) — مفيش
  /// كتابة فوق قرار اتاخد.
  Future<DateTime?> confirmByProxy({
    required String doseEventUuid,
    required String? actorName,
    required DateTime confirmedAt,
  }) async {
    final row = await (_db.select(_db.doseEvents)..where((t) => t.uuid.equals(doseEventUuid))).getSingleOrNull();
    if (row == null) return null;
    if (row.state != DoseState.pending && row.state != DoseState.missed) return null;
    await (_db.update(_db.doseEvents)..where((t) => t.id.equals(row.id))).write(
      DoseEventsCompanion(
        state: const Value(DoseState.taken),
        actedAt: Value(confirmedAt),
        actedBy: Value(actorName),
      ),
    );
    // تأكيد الممرض = «اتاخدت» — المخزون بينقص زي تأكيد المريض بالظبط
    await StockRepository(_db).onDoseStateChanged(row.doseScheduleId, row.state, DoseState.taken);
    return row.scheduledAt;
  }

  Future<void> _setState(
    int doseScheduleId,
    DateTime routineDay,
    DoseState state,
  ) async {
    final day = DateTime(routineDay.year, routineDay.month, routineDay.day);
    final before = await (_db.select(_db.doseEvents)
          ..where((t) => t.doseScheduleId.equals(doseScheduleId) & t.routineDay.equalsValue(day)))
        .getSingleOrNull();
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
    _pendingStock.add((doseScheduleId, before?.state, state));
  }

  /// تعديلات المخزون اللي مستنية لحد ما كتابة الجرعة تخلص — **بعد**
  /// المعاملة، مش جوّاها: المخزون مجاملة والتأكيد هو الوعد.
  final _pendingStock = <(int, DoseState?, DoseState)>[];

  Future<void> _flushStock() async {
    final pending = List.of(_pendingStock);
    _pendingStock.clear();
    for (final (schedule, before, after) in pending) {
      await StockRepository(_db).onDoseStateChanged(schedule, before, after);
    }
  }
}
