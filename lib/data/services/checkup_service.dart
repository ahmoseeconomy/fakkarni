import 'package:drift/drift.dart';

import '../../core/format/arabic_time.dart';
import '../../domain/health/checkup.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import '../files/attachment_store.dart';
import '../repositories/records_repository.dart';
import '../repositories/routine_repository.dart';
import 'reminder_plan.dart';
import 'reminder_sink.dart';

enum FastingResult { scheduled, inPast, tooMany, badHours }

/// نتيجة ضبط ميعاد مرحلة. التخطّي مش نتيجة — مفيش نداء أصلاً.
enum StageDateResult { scheduled, inPast, tooMany }

/// متابعة التحليل وتذكير الصيام (D3.7).
///
/// **القاعدة ٤:** ولا تذكير هنا بيتجدول من نفسه. الصيام من
/// [setFastingReminder]، وميعاد المرحلة من [setStageDate] — والاتنين ما
/// بيتندهوش غير من دوسة. الرجوع لمرحلة قبلها، أو التقدّم لحد ما التذكير
/// يبقى بلا معنى، أو وقف المتابعة — كلهم بيلغوا. الرجوع من المسح ما
/// بيرجّعش حاجة: إنسان يدوس تاني.
///
/// **وما بنفترضش مرحلة بتاخد قد إيه.** مفيش ميعاد بيتحسب ولا بيتخمّن: كل
/// مرحلة بتسأل سؤالها، والتخطّي عادي وبيتقال بسطر قصير مش بتحذير.
class CheckupService {
  CheckupService(this._db, this._sink);

  final AppDatabase _db;
  final ReminderSink _sink;

  /// ساعة تذكير ميعاد المرحلة في اليوم اللي الإنسان اختاره.
  ///
  /// الإنسان بيدّينا **يوم**، والإشعار محتاج ساعة. بناخدها من صحيان
  /// المريض نفسه — «اليوم بيبدأ من الصحيان» هي قاعدة التطبيق كلها — مش
  /// من رقم مخترع. من غير روتين متحفوظ بنرجع لـ٩ الصبح، وده اختيار
  /// تشغيلي زي الإزاحات الافتراضية، مش كلام طبي.
  static const int _fallbackMinuteOfDay = 9 * 60;

  RecordsRepository get _records => RecordsRepository(_db);

  Future<RecordRow> _row(int id) => (_db.select(_db.records)..where((t) => t.id.equals(id))).getSingle();

  /// المتابعات المفتوحة للمريض ده — اللي ليها مرحلة ومش ممسوحة.
  ///
  /// «يومك» بتقراها: متابعة محدش شايفها متابعة محدش بيعملها.
  Stream<List<RecordRow>> watchOpen(int patientId) => (_db.select(_db.records)
        ..where((t) => t.patientId.equals(patientId) & t.deletedAt.isNull() & t.checkupStage.isNotNull())
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch();

  /// الميعاد المتحفوظ للمرحلة دي على الصف ده.
  static DateTime? stageDateOf(RecordRow row, CheckupStage stage) => switch (stage) {
        CheckupStage.labBooking => row.labBookingAt,
        CheckupStage.waitingResult => row.resultReadyAt,
        CheckupStage.resultArrived => row.doctorVisitAt,
        _ => null,
      };

  static RecordsCompanion _stageDateCompanion(CheckupStage stage, DateTime? at) => switch (stage) {
        CheckupStage.labBooking => RecordsCompanion(labBookingAt: Value(at)),
        CheckupStage.waitingResult => RecordsCompanion(resultReadyAt: Value(at)),
        CheckupStage.resultArrived => RecordsCompanion(doctorVisitAt: Value(at)),
        _ => const RecordsCompanion(),
      };

  /// خانة المرحلة في نطاق الإشعارات — ترتيبها بين اللي بتسأل عن تاريخ.
  static int _slotOf(CheckupStage stage) {
    final slot = CheckupStage.dated.indexOf(stage);
    if (slot < 0) throw ArgumentError.value(stage, 'stage', 'المرحلة دي ما بتسألش عن تاريخ');
    return slot;
  }

  /// ساعة الصحيان بتاعت المريض، وإلا ٩ الصبح.
  Future<int> _reminderMinute(int patientId) async {
    final routine = await RoutineRepository(_db).getRoutine(patientId);
    return routine?.wake.minutes ?? _fallbackMinuteOfDay;
  }

  Stream<RecordRow?> watch(int id) => (_db.select(_db.records)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> start({required int patientId, required String title, String? doctor, required DateTime today}) async {
    final id = await _records.add(
      patientId: patientId,
      kind: RecordKind.lab,
      title: title,
      happenedAt: DateTime(today.year, today.month, today.day),
      doctor: doctor,
    );
    await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(RecordsCompanion(
          checkupStage: Value(CheckupStage.doctorOrder.number),
          checkupStageSince: Value(today),
        ));
    return id;
  }

  Future<void> advance(int id, {DateTime? now}) async {
    final row = await _row(id);
    final next = CheckupStage.fromNumber(row.checkupStage)?.next;
    if (next == null) return;
    await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(RecordsCompanion(
          checkupStage: Value(next.number),
          checkupStageSince: Value(now ?? DateTime.now()),
        ));
    if (!fastingReminderStillUseful(next)) await cancelFasting(id);
    // تذكير بقى بلا معنى بيتشال — مش هنزنّ على حاجة اتعملت
    for (final stage in CheckupStage.dated) {
      if (!stageReminderStillUseful(stage, next)) await clearStageDate(id, stage);
    }
  }

  /// الرجوع مرحلة **دايماً** بيلغي تذكير الصيام — الخطة اتغيّرت.
  ///
  /// وبيلغي كمان ميعاد المرحلة اللي كان واقف عليها: هو رجع عشان الخطة
  /// اتغيّرت، فالميعاد اللي قاله لها مابقاش صحيح. لما يرجع لها تاني
  /// هيتسأل من جديد — نفس سلوك تذكير الصيام بالظبط.
  Future<void> back(int id, {DateTime? now}) async {
    final row = await _row(id);
    final was = CheckupStage.fromNumber(row.checkupStage);
    final previous = was?.previous;
    if (previous == null) return;
    await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(RecordsCompanion(
          checkupStage: Value(previous.number),
          checkupStageSince: Value(now ?? DateTime.now()),
        ));
    await cancelFasting(id);
    if (was != null && was.asksForDate) await clearStageDate(id, was);
  }

  /// مواعيد مراحل لسه جاية، في كل المتابعات غير الممسوحة.
  Future<int> activeStageDateCount({required DateTime now, int? exceptRecord}) async {
    final rows = await (_db.select(_db.records)
          ..where((t) =>
              t.deletedAt.isNull() &
              (exceptRecord == null ? const Constant(true) : t.id.equals(exceptRecord).not())))
        .get();
    var n = 0;
    for (final row in rows) {
      for (final stage in CheckupStage.dated) {
        final at = stageDateOf(row, stage);
        if (at != null && at.isAfter(now)) n++;
      }
    }
    return n;
  }

  /// ميعاد المرحلة اللي **الإنسان** قاله → تذكير في نفس اليوم.
  ///
  /// [day] يوم بس؛ الساعة بتيجي من صحيان المريض. إعادة الضبط بتستبدل
  /// التذكير لأن الرقم مشتق من (الصف، المرحلة) — مش بتزوّد واحد.
  Future<StageDateResult> setStageDate(
    int id,
    CheckupStage stage, {
    required DateTime day,
    required DateTime now,
  }) async {
    final slot = _slotOf(stage);
    final row = await _row(id);
    final minute = await _reminderMinute(row.patientId);
    final at = DateTime(day.year, day.month, day.day, 0, minute);
    if (!at.isAfter(now)) return StageDateResult.inPast;
    if (stageDateOf(row, stage) == null &&
        await activeStageDateCount(now: now, exceptRecord: id) >= checkupPendingSlack) {
      return StageDateResult.tooMany;
    }

    await _sink.schedule(PlannedNotification(
      id: checkupIdFor(id, slot),
      at: at,
      title: 'متابعة ${row.title}',
      body: switch (stage) {
        CheckupStage.labBooking => 'النهارده ميعادك في المعمل.',
        CheckupStage.waitingResult => 'النتيجة المفروض تبقى جاهزة النهارده.',
        _ => 'النهارده معادك مع الدكتور.',
      },
      payload: '',
      kind: NotificationKind.fasting,
    ));
    await (_db.update(_db.records)..where((t) => t.id.equals(id)))
        .write(_stageDateCompanion(stage, at));
    return StageDateResult.scheduled;
  }

  /// بيلغي بالرقم المشتق — آمن حتى لو مفيش ميعاد متحطّ.
  Future<void> clearStageDate(int id, CheckupStage stage) async {
    await _sink.cancel(checkupIdFor(id, _slotOf(stage)));
    await (_db.update(_db.records)..where((t) => t.id.equals(id)))
        .write(_stageDateCompanion(stage, null));
  }

  /// تذكيرات صيام لسه جاية، في كل المتابعات غير الممسوحة.
  Future<int> activeFastingCount({required DateTime now, int? except}) async {
    final rows = await (_db.select(_db.records)
          ..where((t) =>
              t.fastingReminderAt.isBiggerThanValue(now) &
              t.deletedAt.isNull() &
              (except == null ? const Constant(true) : t.id.equals(except).not())))
        .get();
    return rows.length;
  }

  /// بيجدول التذكير عند [draw] ناقص [hours] **اللي المستخدم كتبها**. مفيش
  /// ساعات افتراضية.
  Future<FastingResult> setFastingReminder(
    int id, {
    required DateTime draw,
    required int hours,
    required DateTime now,
  }) async {
    if (!isTypedFastingHours(hours)) return FastingResult.badHours;
    final at = fastingReminderTime(draw, hours);
    if (!at.isAfter(now)) return FastingResult.inPast;
    if (await activeFastingCount(now: now, except: id) >= fastingPendingSlack) return FastingResult.tooMany;

    final row = await _row(id);
    final day = DateTime(draw.year, draw.month, draw.day);
    final today = DateTime(now.year, now.month, now.day);
    final when = day == today
        ? 'النهارده'
        : day == DateTime(today.year, today.month, today.day + 1)
            ? 'بكرة'
            : arabicDate(draw);
    await _sink.schedule(PlannedNotification(
      id: fastingIdFor(id),
      at: at,
      title: 'صيام قبل ${row.title}',
      body: 'سحب العينة $when الساعة ${arabicTime(draw)} — المعمل قال صيام ${arabicNumber(hours)} ساعة، تبدأ دلوقتي.',
      payload: '',
      kind: NotificationKind.fasting,
    ));
    await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(RecordsCompanion(
          fastingReminderAt: Value(at),
          happenedAt: Value(draw),
        ));
    return FastingResult.scheduled;
  }

  /// بيلغي بالرقم المشتق — آمن حتى لو مفيش تذكير. **مش** cancelAll.
  Future<void> cancelFasting(int id) async {
    await _sink.cancel(fastingIdFor(id));
    await (_db.update(_db.records)..where((t) => t.id.equals(id)))
        .write(const RecordsCompanion(fastingReminderAt: Value(null)));
  }

  /// مسح (D3.5) + إلغاء التذكير لو فيه. **مفيش رجوع.**
  ///
  /// التذكير بيتلغي **قبل** المسح: رقمه مشتق من `id` الصف، والمسح بيصفّر
  /// `fastingReminderAt`، فلو اتأخّرنا هنبقى بنلغي حاجة الصف مابقاش فاكرها.
  Future<void> delete(int id, {DateTime? now, AttachmentStore? attachments}) async {
    final row = await _row(id);
    if (row.fastingReminderAt != null) await cancelFasting(id);
    for (final stage in CheckupStage.dated) {
      if (stageDateOf(row, stage) != null) await clearStageDate(id, stage);
    }
    await _records.delete(id, now: now, attachments: attachments);
  }
}
