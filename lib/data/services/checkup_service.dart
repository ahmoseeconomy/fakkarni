import 'package:drift/drift.dart';

import '../../core/format/arabic_time.dart';
import '../../domain/health/checkup.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import '../repositories/records_repository.dart';
import 'reminder_plan.dart';
import 'reminder_sink.dart';

enum FastingResult { scheduled, inPast, tooMany, badHours }

/// دورة الفحص وتذكير الصيام (D3.7).
///
/// **القاعدة ٤:** تذكير الصيام ما بيتجدولش إلا من [setFastingReminder]، واللي
/// ما بيتندهش غير من زرار «اضبط تذكير الصيام». الرجوع لمرحلة قبلها، أو
/// التقدّم بعد «سحب العينة»، أو مسح السجل — كلهم بيلغوه. الرجوع من المسح ما
/// بيرجّعهوش: إنسان يدوس تاني.
class CheckupService {
  CheckupService(this._db, this._sink);

  final AppDatabase _db;
  final ReminderSink _sink;

  RecordsRepository get _records => RecordsRepository(_db);

  Future<RecordRow> _row(int id) => (_db.select(_db.records)..where((t) => t.id.equals(id))).getSingle();

  Stream<RecordRow?> watch(int id) => (_db.select(_db.records)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> start({required int patientId, required String title, String? doctor, required DateTime today}) async {
    final id = await _records.add(
      patientId: patientId,
      kind: RecordKind.lab,
      title: title,
      happenedAt: DateTime(today.year, today.month, today.day),
      doctor: doctor,
    );
    await (_db.update(_db.records)..where((t) => t.id.equals(id)))
        .write(RecordsCompanion(checkupStage: Value(CheckupStage.doctorOrder.number)));
    return id;
  }

  Future<void> advance(int id) async {
    final row = await _row(id);
    final next = CheckupStage.fromNumber(row.checkupStage)?.next;
    if (next == null) return;
    await (_db.update(_db.records)..where((t) => t.id.equals(id)))
        .write(RecordsCompanion(checkupStage: Value(next.number)));
    if (!fastingReminderStillUseful(next)) await cancelFasting(id);
  }

  /// الرجوع مرحلة **دايماً** بيلغي التذكير — الخطة اتغيّرت.
  Future<void> back(int id) async {
    final row = await _row(id);
    final previous = CheckupStage.fromNumber(row.checkupStage)?.previous;
    if (previous == null) return;
    await (_db.update(_db.records)..where((t) => t.id.equals(id)))
        .write(RecordsCompanion(checkupStage: Value(previous.number)));
    await cancelFasting(id);
  }

  /// تذكيرات صيام لسه جاية، في كل الدورات غير الممسوحة.
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

  /// مسح ناعم (D3.5) + إلغاء التذكير لو فيه. الرجوع ما بيرجّعش التذكير.
  Future<void> softDelete(int id, {DateTime? now}) async {
    final row = await _row(id);
    await _records.softDelete(id, now: now);
    if (row.fastingReminderAt != null) await cancelFasting(id);
  }
}
