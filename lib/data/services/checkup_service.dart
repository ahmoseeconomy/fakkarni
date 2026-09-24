import 'package:drift/drift.dart';

import '../../core/format/arabic_time.dart';
import '../../domain/health/checkup.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import '../files/attachment_store.dart';
import '../repositories/records_repository.dart';
import '../repositories/routine_repository.dart';
import 'reminder_plan.dart';
import 'reminder_sink.dart';

enum FastingResult { scheduled, inPast, tooMany, badHours }

/// نتيجة ضبط ميعاد مرحلة. التخطّي مش نتيجة — مفيش نداء أصلاً.
/// **مفيش `tooMany`**: الحجز عمره ما يترفض عشان خانات الإشعارات.
enum StageDateResult { scheduled, inPast }

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

  /// نوع المتابعة بتاعة الصف ده — null في العمود = تحليل (شوف [FollowKind]).
  static FollowKind kindOf(RecordRow row) => FollowKind.fromStored(row.followKind);

  /// المرحلة الحالية، مفسّرة **بنوعها**: الرقم ٢ في تحليل «حجز المعمل»،
  /// وفي زيارة «الزيارة تمت».
  static FollowStage? stageOf(RecordRow row) => kindOf(row).stageFromNumber(row.checkupStage);

  Future<RecordRow> _row(int id) => (_db.select(_db.records)..where((t) => t.id.equals(id))).getSingle();

  /// المتابعات المفتوحة للمريض ده — اللي ليها مرحلة ومش ممسوحة.
  ///
  /// «يومك» بتقراها: متابعة محدش شايفها متابعة محدش بيعملها.
  Stream<List<RecordRow>> watchOpen(int patientId) => (_db.select(_db.records)
        ..where((t) => t.patientId.equals(patientId) & t.deletedAt.isNull() & t.checkupStage.isNotNull())
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch();

  /// الميعاد المتحفوظ للمرحلة دي على الصف ده.
  ///
  /// **ميعاد الزيارة بيقعد في نفس عمود «معاد الدكتور»** — المعنى واحد،
  /// والصف نوعه واحد بس، فمستحيل الاتنين يتلاقوا على صف واحد.
  static DateTime? stageDateOf(RecordRow row, FollowStage stage) => followStageDate(
        stage,
        labBookingAt: row.labBookingAt,
        resultReadyAt: row.resultReadyAt,
        doctorVisitAt: row.doctorVisitAt,
      );

  static RecordsCompanion _stageDateCompanion(FollowStage stage, DateTime? at) => switch (stage) {
        CheckupStage.labBooking => RecordsCompanion(labBookingAt: Value(at)),
        CheckupStage.waitingResult => RecordsCompanion(resultReadyAt: Value(at)),
        CheckupStage.resultArrived => RecordsCompanion(doctorVisitAt: Value(at)),
        VisitStage.booked => RecordsCompanion(doctorVisitAt: Value(at)),
        _ => const RecordsCompanion(),
      };

  /// ساعة الصحيان بتاعت المريض، وإلا ٩ الصبح.
  Future<int> _reminderMinute(int patientId) async {
    final routine = await RoutineRepository(_db).getRoutine(patientId);
    return routine?.wake.minutes ?? _fallbackMinuteOfDay;
  }

  Stream<RecordRow?> watch(int id) => (_db.select(_db.records)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// بيبدأ متابعة — بالإيد، أو من سجل موجود في الملف.
  ///
  /// **المتابعة صف جديد، والمصدر بيفضل زي ما هو.** التقرير اللي في الملف
  /// حاجة حصلت خلاص، والمتابعة حاجة لسه بتحصل: لو حوّلنا التقرير نفسه
  /// لمتابعة، صف فيه نتايج هيبدأ من «طلب الطبيب» ويناقض نفسه. الربط
  /// بـ[fromRecordId] هو اللي بيخلّي «التقرير ده ليه متابعة خلاص» سؤال
  /// له إجابة.
  Future<int> start({
    required int patientId,
    required String title,
    String? doctor,
    String? place,
    required DateTime today,
    FollowKind kind = FollowKind.lab,
    DateTime? happenedAt,
    int? fromRecordId,
  }) async {
    final id = await _records.add(
      patientId: patientId,
      kind: kind == FollowKind.lab ? RecordKind.lab : RecordKind.visit,
      title: title,
      happenedAt: happenedAt ?? DateTime(today.year, today.month, today.day),
      doctor: doctor,
      place: place,
    );
    await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(RecordsCompanion(
          checkupStage: const Value(1),
          checkupStageSince: Value(today),
          followKind: Value(kind.name),
          followSourceId: Value(fromRecordId),
        ));
    return id;
  }

  /// المتابعة المفتوحة اللي اتبدت من السجل ده، أو null.
  ///
  /// بيه «تابع تحليل» بتعرف إن التقرير ده **متابَع خلاص** فتفتحه بدل ما
  /// تبدأ تانية — متابعتين لنفس الورقة يبقى الاتنين ناقصين.
  Future<RecordRow?> openFollowUpFor(int recordId) async {
    final rows = await (_db.select(_db.records)
          ..where((t) => t.followSourceId.equals(recordId) & t.deletedAt.isNull() & t.checkupStage.isNotNull()))
        .get();
    return rows.firstOrNull;
  }

  /// كل السجلات اللي اتبدت منها متابعة مفتوحة — بتتقرا مرة واحدة للقايمة.
  Future<Set<int>> followedSourceIds(int patientId) async {
    final rows = await (_db.select(_db.records)
          ..where((t) => t.patientId.equals(patientId) & t.deletedAt.isNull() & t.checkupStage.isNotNull()))
        .get();
    return {for (final r in rows) ?r.followSourceId};
  }

  /// **«ميعاد جديد» في مكان واحد** — زرار المريض وتغيير الممرض المعلّق
  /// بيعدّوا من هنا، فالاتنين بيعملوا نفس المتابعة بنفس الميعاد ونفس
  /// الإشعارات. معمل = الحجز اتعمل خلاص (بنعدّي «طلب الطبيب»)؛ زيارة =
  /// «الزيارة اتحجزت». المُنادي بينده `refreshAppointments` بعدها.
  Future<int> bookAppointment({
    required int patientId,
    required FollowKind kind,
    required String title,
    required DateTime day,
    required DateTime today,
    String? doctor,
  }) async {
    final id = await start(patientId: patientId, kind: kind, title: title, doctor: doctor, today: today);
    if (kind == FollowKind.lab) {
      await advance(id, now: today);
      await setStageDate(id, CheckupStage.labBooking, day: day, now: today);
    } else {
      await setStageDate(id, VisitStage.booked, day: day, now: today);
    }
    return id;
  }

  Future<void> advance(int id, {DateTime? now}) async {
    final row = await _row(id);
    final kind = kindOf(row);
    final current = stageOf(row);
    final next = current == null ? null : kind.nextAfter(current);
    if (next == null) return;
    await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(RecordsCompanion(
          checkupStage: Value(next.number),
          checkupStageSince: Value(now ?? DateTime.now()),
        ));
    if (next is CheckupStage && !fastingReminderStillUseful(next)) await cancelFasting(id);
    // تذكير بقى بلا معنى بيتشال — مش هنزنّ على حاجة اتعملت
    for (final stage in kind.datedStages) {
      if (!followReminderStillUseful(kind, stage, next)) await clearStageDate(id, stage);
    }
  }

  /// الرجوع مرحلة **دايماً** بيلغي تذكير الصيام — الخطة اتغيّرت.
  ///
  /// وبيلغي كمان ميعاد المرحلة اللي كان واقف عليها: هو رجع عشان الخطة
  /// اتغيّرت، فالميعاد اللي قاله لها مابقاش صحيح. لما يرجع لها تاني
  /// هيتسأل من جديد — نفس سلوك تذكير الصيام بالظبط.
  Future<void> back(int id, {DateTime? now}) async {
    final row = await _row(id);
    final kind = kindOf(row);
    final was = stageOf(row);
    final previous = was == null ? null : kind.beforeStage(was);
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
      // **بنعدّ بنوع الصف**: عمود «معاد الدكتور» بيشيل ميعاد الزيارة كمان،
      // ولو عدّيناه مرتين على نفس الصف كنا هنقفل الباب على ميعاد سليم.
      if (row.checkupStage == null) continue;
      for (final stage in kindOf(row).datedStages) {
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
    FollowStage stage, {
    required DateTime day,
    required DateTime now,
  }) async {
    final row = await _row(id);
    final slot = kindOf(row).slotOf(stage);
    final minute = await _reminderMinute(row.patientId);
    final at = DateTime(day.year, day.month, day.day, 0, minute);
    if (!at.isAfter(now)) return StageDateResult.inPast;
    // **الحجز عمره ما يترفض عشان الخانات** (مواصفة المواعيد). الخانتين
    // بقوا **نافذة متدحرجة** على iOS: الميعاد البعيد بيستنى دوره فيها،
    // وكارت «يومك» هو اللي بيقول إنه موجود لحد ما دوره يجي. الرفض القديم
    // كان بيقول لراجل حاجز عند الدكتور «شيل ميعاد الأول» — وده مش قرارنا.

    // **الجدولة مابقتش هنا.** الميعاد بقى إشعارين — هادي امبارحه ويوم
    // بيرن — والاتنين بيتحسبوا في [AppointmentScheduler] مع كل المواعيد
    // التانية، عشان نافذة iOS تشوفهم كلهم مع بعض. اللي بيتكتب هنا هو
    // **الميعاد**؛ الإشعارات بتتبني منه.
    //
    // والرقم القديم (`checkupIdFor`) بيتلغي: الصف ده كان له إشعار واحد
    // بالنطاق القديم، ولو سِبناه هيفضل معلّق ويرن لوحده جنب الجديدين.
    await _sink.cancel(checkupIdFor(id, slot));
    await (_db.update(_db.records)..where((t) => t.id.equals(id)))
        .write(_stageDateCompanion(stage, at));
    return StageDateResult.scheduled;
  }

  /// بيشيل ميعاد المرحلة. **إشعاراته بيشيلهم التوفيق، مش الدالة دي.**
  ///
  /// رقم إشعار المواعيد بقى مشتق من **اليوم** مش من (الصف، المرحلة)،
  /// عشان كل مواعيد اليوم يطلعوا في إشعار واحد. يعني إلغاء الرقم من هنا
  /// كان هيطفّي الإشعار بتاع ميعاد **تاني** واقع في نفس اليوم — ولده
  /// مالوش أي ذنب. فالنطاق بقى ملك [AppointmentScheduler.refresh] لوحده:
  /// بيحسب الخطة من الصفوف كلها وبيلغي اللي برّه الخطة. كل نداء هنا
  /// بيتبعه توفيق (شاشة المتابعة، وصف السجل).
  ///
  /// الرقم **القديم** (`checkupIdFor`) لسه بيتلغي: هو مشتق من الصف
  /// والمرحلة فمالوش جار يتأذى، والتوفيق بيفضّي نطاقه كله برضه.
  Future<void> clearStageDate(int id, FollowStage stage) async {
    final row = await _row(id);
    await _sink.cancel(checkupIdFor(id, kindOf(row).slotOf(stage)));
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
    for (final stage in kindOf(row).datedStages) {
      if (stageDateOf(row, stage) != null) await clearStageDate(id, stage);
    }
    await _records.delete(id, now: now, attachments: attachments);
  }
}
