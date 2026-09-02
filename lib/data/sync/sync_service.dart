// ignore_for_file: prefer_initializing_formals
// المُنشئ بيربط معاملات عامة بحقول خاصة — الصيغة الأوضح هنا.
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../db/app_database.dart';

/// السحابة نسخة، والمحلي هو الحقيقة — اتجاه واحد.
///
/// جهاز المالك بس هو اللي بيكتب صفوفه، ومفيش حاجة بتسحب في الجولة دي
/// (3.5 بتقرا Supabase مباشرة). يعني مفيش دمج ومفيش «مين يكسب» — أي كود
/// من ده هيبقى حراسة لحالة مستحيلة وغطا على عيوب حقيقية.
///
/// المستخدم مش المفروض يعرف إن في مزامنة أصلاً: أي فشل بيتسجّل ويتساب،
/// والصفوف المتوسّخة بتستنى المحاولة الجاية. عمرها ما بترمي في الواجهة.
abstract interface class SyncRemote {
  /// upsert on conflict (uuid) do update — تكرار الدفع ما بيكرّرش صفوف.
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);
}

/// مهلة دفعة الخلفية.
///
/// iOS بيدي الـisolate ثواني معدودة؛ الرقم ده مساحة لنداء واحد على شبكة
/// بطيئة، مش لمحاولة عنيدة. أطول من كده معناه إن الـisolate بيتقفل وهو
/// مستني، وأقصر معناه إننا بنفشل على شبكة مصرية عادية.
const Duration backgroundPushTimeout = Duration(seconds: 5);

/// وقت على السلك: UTC ISO دايماً — المحطة المحلية بتفضل على الجهاز.
String utcIso(DateTime local) => local.toUtc().toIso8601String();

String dateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SyncService {
  SyncService({
    required AppDatabase db,
    required SyncRemote remote,
    required bool Function() hasSession,
    Stream<Object?>? localWrites,
    Duration debounce = const Duration(seconds: 3),
    Duration backgroundTimeout = backgroundPushTimeout,
    int batchSize = 200,
  })  : _db = db,
        _remote = remote,
        _hasSession = hasSession,
        _localWrites = localWrites,
        _debounce = debounce,
        _backgroundTimeout = backgroundTimeout,
        _batchSize = batchSize;

  final AppDatabase _db;
  final SyncRemote _remote;
  final bool Function() _hasSession;
  final Stream<Object?>? _localWrites;
  final Duration _debounce;
  final Duration _backgroundTimeout;
  final int _batchSize;

  StreamSubscription<Object?>? _writesSub;
  StreamSubscription<Object?>? _connectivitySub;
  Timer? _debounceTimer;
  bool _pushing = false;
  bool _pushAgain = false;

  /// المحفّزات: كتابة محلية (بعد سكوت [_debounce])، ورجوع الشبكة.
  /// الرجوع للمقدمة بييجي من AppRoot. **مفيش مؤقّت دوري** — عن قصد.
  void start({Stream<Object?>? connectivity}) {
    _writesSub = (_localWrites ?? _db.tableUpdates()).listen((_) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounce, () => unawaited(push()));
    });
    if (connectivity != null) {
      _connectivitySub = connectivity.listen((_) => unawaited(push()));
    }
  }

  void onAppForeground() => unawaited(push());

  /// دفعة واحدة محدودة بوقت — لصحوة الخلفية بتاعة زرار الإشعار.
  ///
  /// الـisolate بيتفتح للحظة والنظام بيقفله بعدها؛ مفيش وقت لطابور ولا
  /// إعادة محاولة. محاولة واحدة، مهلة قصيرة، وعمرها ما بترمي: اللي ما لحقش
  /// بيفضل متوسّخاً (العلامة بتتحط بعد نجاح الـupsert مش قبله) وأول دفعة
  /// في المقدمة بتشيله.
  ///
  /// المهلة مش بتلغي النداء اللي في السكة — دارت ما بتقدرش — هي بتحرّرنا
  /// إحنا بس. وده كفاية: الكتابة المحلية وإلغاء الإشعارات خلصوا قبلها.
  Future<void> pushOnce({Duration? timeout}) async {
    try {
      await push().timeout(timeout ?? _backgroundTimeout);
    } on TimeoutException {
      debugPrint('Sync: دفعة الخلفية عدّت المهلة — الصفوف بتفضل متوسّخة');
    } catch (error, stack) {
      // push() بتبلع أخطاءها جوّه، فده للنادر اللي بيفلت — ومش هنوقّع
      // isolate بيسجّل جرعة عشان السحابة اتعبت.
      debugPrint('Sync: دفعة الخلفية فشلت: $error\n$stack');
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _writesSub?.cancel();
    await _connectivitySub?.cancel();
  }

  /// شاشة الربط أكّدت إن صف المريض اترفع (3.3) — من هنا ورايح المزامنة
  /// مسموحة. من غير العلامة دي المستخدم غير المربوط أوفلاين ١٠٠٪.
  Future<void> confirmLinked() async {
    final rows = await _db.select(_db.patients).get();
    for (final p in rows) {
      await (_db.update(_db.patients)..where((t) => t.id.equals(p.id)))
          .write(PatientsCompanion(syncedAtMs: Value(p.updatedAtMs)));
    }
  }

  Future<bool> _linked() async {
    final row = await (_db.select(_db.patients)
          ..where((t) => t.syncedAtMs.isNotNull())
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// بيدفع المتوسّخ، الأب قبل الابن، وبيعلّم كل جدول بعد ما دفعته تنجح.
  ///
  /// العلامة هي updated_at_ms **اللي اتدفعت** مش now(): صف اتعدّل أثناء
  /// الدفع بتبقى ساعته أحدث من العلامة فبيفضل متوسّخاً للمحاولة الجاية.
  Future<void> push() async {
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    if (!_hasSession()) return;
    if (!await _linked()) return;

    _pushing = true;
    try {
      await _pushPatients();
      await _pushDayRoutines();
      await _pushMedications();
      await _pushDoseSchedules();
      await _pushFixedTimings();
      await _pushDoseEvents();
    } catch (error, stack) {
      // بنسجّل ونسيب الصفوف متوسّخة — المحاولة الجاية مع أي محفّز.
      debugPrint('Sync: push فشلت وهتتعاد: $error\n$stack');
    } finally {
      _pushing = false;
      if (_pushAgain) {
        _pushAgain = false;
        unawaited(push());
      }
    }
  }

  Expression<bool> _dirty(SyncIdentityColumns t) =>
      t.syncedAtMs.isNull() | t.syncedAtMs.isSmallerThan(t.updatedAtMs);

  Future<void> _upsertAndMark(
    String table,
    List<({String uuid, int updatedAtMs, Map<String, dynamic> json})> rows,
    Future<void> Function(String uuid, int updatedAtMs) mark,
  ) async {
    for (var i = 0; i < rows.length; i += _batchSize) {
      final chunk = rows.sublist(
          i, i + _batchSize > rows.length ? rows.length : i + _batchSize);
      await _remote.upsert(table, [for (final r in chunk) r.json]);
      for (final r in chunk) {
        await mark(r.uuid, r.updatedAtMs);
      }
    }
  }

  Future<void> _pushPatients() async {
    final rows = await (_db.select(_db.patients)
          ..where((t) => _dirty(_cols(t.syncedAtMs, t.updatedAtMs))))
        .get();
    await _upsertAndMark(
      'patients',
      [
        for (final p in rows)
          (
            uuid: p.uuid,
            updatedAtMs: p.updatedAtMs,
            json: {
              'uuid': p.uuid,
              'name': p.name,
              'notification_slot': p.notificationSlot,
            }
          ),
      ],
      (uuid, ms) => (_db.update(_db.patients)..where((t) => t.uuid.equals(uuid)))
          .write(PatientsCompanion(syncedAtMs: Value(ms))),
    );
  }

  Future<void> _pushDayRoutines() async {
    final query = _db.select(_db.dayRoutines).join([
      innerJoin(_db.patients, _db.patients.id.equalsExp(_db.dayRoutines.patientId)),
    ])
      ..where(_db.dayRoutines.syncedAtMs.isNull() |
          _db.dayRoutines.syncedAtMs.isSmallerThan(_db.dayRoutines.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'day_routines',
      [
        for (final row in rows)
          () {
            final r = row.readTable(_db.dayRoutines);
            final p = row.readTable(_db.patients);
            return (
              uuid: r.uuid,
              updatedAtMs: r.updatedAtMs,
              json: {
                'uuid': r.uuid,
                'patient_uuid': p.uuid,
                'wake_minutes': r.wakeMinutes,
                'breakfast_minutes': r.breakfastMinutes,
                'lunch_minutes': r.lunchMinutes,
                'dinner_minutes': r.dinnerMinutes,
                'sleep_minutes': r.sleepMinutes,
              }
            );
          }(),
      ],
      (uuid, ms) =>
          (_db.update(_db.dayRoutines)..where((t) => t.uuid.equals(uuid)))
              .write(DayRoutinesCompanion(syncedAtMs: Value(ms))),
    );
  }

  Future<void> _pushMedications() async {
    final query = _db.select(_db.medications).join([
      innerJoin(_db.patients, _db.patients.id.equalsExp(_db.medications.patientId)),
    ])
      ..where(_db.medications.syncedAtMs.isNull() |
          _db.medications.syncedAtMs.isSmallerThan(_db.medications.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'medications',
      [
        for (final row in rows)
          () {
            final m = row.readTable(_db.medications);
            final p = row.readTable(_db.patients);
            return (
              uuid: m.uuid,
              updatedAtMs: m.updatedAtMs,
              json: {
                'uuid': m.uuid,
                'patient_uuid': p.uuid,
                'name': m.name,
                'amount_label': m.amountLabel,
                'notes': m.notes,
                'stopped_at': m.stoppedAt == null ? null : utcIso(m.stoppedAt!),
                'amount_unknown': m.amountUnknown,
              }
            );
          }(),
      ],
      (uuid, ms) =>
          (_db.update(_db.medications)..where((t) => t.uuid.equals(uuid)))
              .write(MedicationsCompanion(syncedAtMs: Value(ms))),
    );
  }

  Future<void> _pushDoseSchedules() async {
    final query = _db.select(_db.doseSchedules).join([
      innerJoin(_db.medications,
          _db.medications.id.equalsExp(_db.doseSchedules.medicationId)),
    ])
      ..where(_db.doseSchedules.syncedAtMs.isNull() |
          _db.doseSchedules.syncedAtMs
              .isSmallerThan(_db.doseSchedules.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'dose_schedules',
      [
        for (final row in rows)
          () {
            final s = row.readTable(_db.doseSchedules);
            final m = row.readTable(_db.medications);
            return (
              uuid: s.uuid,
              updatedAtMs: s.updatedAtMs,
              json: {
                'uuid': s.uuid,
                'medication_uuid': m.uuid,
                'timing_kind': s.timingKind.name,
                'anchor': s.anchor?.name,
                'offset_minutes': s.offsetMinutes,
                'repeat': s.repeat.name,
                'start_date': dateOnly(s.startDate),
                'duration_days': s.durationDays,
              }
            );
          }(),
      ],
      (uuid, ms) =>
          (_db.update(_db.doseSchedules)..where((t) => t.uuid.equals(uuid)))
              .write(DoseSchedulesCompanion(syncedAtMs: Value(ms))),
    );
  }

  Future<void> _pushFixedTimings() async {
    final query = _db.select(_db.fixedTimings).join([
      innerJoin(_db.doseSchedules,
          _db.doseSchedules.id.equalsExp(_db.fixedTimings.doseScheduleId)),
    ])
      ..where(_db.fixedTimings.syncedAtMs.isNull() |
          _db.fixedTimings.syncedAtMs
              .isSmallerThan(_db.fixedTimings.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'fixed_timings',
      [
        for (final row in rows)
          () {
            final f = row.readTable(_db.fixedTimings);
            final s = row.readTable(_db.doseSchedules);
            return (
              uuid: f.uuid,
              updatedAtMs: f.updatedAtMs,
              json: {
                'uuid': f.uuid,
                'dose_schedule_uuid': s.uuid,
                'minute_of_day': f.minuteOfDay,
              }
            );
          }(),
      ],
      (uuid, ms) =>
          (_db.update(_db.fixedTimings)..where((t) => t.uuid.equals(uuid)))
              .write(FixedTimingsCompanion(syncedAtMs: Value(ms))),
    );
  }

  Future<void> _pushDoseEvents() async {
    final query = _db.select(_db.doseEvents).join([
      innerJoin(_db.doseSchedules,
          _db.doseSchedules.id.equalsExp(_db.doseEvents.doseScheduleId)),
    ])
      ..where(_db.doseEvents.syncedAtMs.isNull() |
          _db.doseEvents.syncedAtMs.isSmallerThan(_db.doseEvents.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'dose_events',
      [
        for (final row in rows)
          () {
            final e = row.readTable(_db.doseEvents);
            final s = row.readTable(_db.doseSchedules);
            return (
              uuid: e.uuid,
              updatedAtMs: e.updatedAtMs,
              json: {
                'uuid': e.uuid,
                'dose_schedule_uuid': s.uuid,
                'routine_day': dateOnly(e.routineDay),
                'scheduled_at': utcIso(e.scheduledAt),
                'state': e.state.name,
                'acted_at': e.actedAt == null ? null : utcIso(e.actedAt!),
              }
            );
          }(),
      ],
      (uuid, ms) =>
          (_db.update(_db.doseEvents)..where((t) => t.uuid.equals(uuid)))
              .write(DoseEventsCompanion(syncedAtMs: Value(ms))),
    );
  }
}

/// عمودا ساعة المزامنة بشكل generic — عشان شرط الوسخ يتكتب مرة واحدة.
class SyncIdentityColumns {
  const SyncIdentityColumns(this.syncedAtMs, this.updatedAtMs);
  final Column<int> syncedAtMs;
  final Column<int> updatedAtMs;
}

SyncIdentityColumns _cols(Column<int> synced, Column<int> updated) =>
    SyncIdentityColumns(synced, updated);
