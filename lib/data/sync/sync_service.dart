// ignore_for_file: prefer_initializing_formals
// المُنشئ بيربط معاملات عامة بحقول خاصة — الصيغة الأوضح هنا.
import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/format/arabic_time.dart';
import '../db/app_database.dart';
import '../../core/diagnostics.dart';

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

  /// **أول مسح في المزامنة** (الدين ١ كان بيقول «مفيش deletes»).
  ///
  /// سجل الإنسان مسحه لازم يروح من السحابة كمان، وإلا الابن يفضل شايفه
  /// في «الملف الصحي» بتاعه. بيتنده بالـuuid — نفس المفتاح اللي الـupsert
  /// بيشتغل عليه — وتكراره بيمسح صفر صف من غير خطأ، فالإعادة آمنة.
  Future<void> deleteByUuid(String table, List<String> uuids);
}

/// مهلة دفعة الخلفية.
///
/// iOS بيدي الـisolate ثواني معدودة؛ الرقم ده مساحة لنداء واحد على شبكة
/// بطيئة، مش لمحاولة عنيدة. أطول من كده معناه إن الـisolate بيتقفل وهو
/// مستني، وأقصر معناه إننا بنفشل على شبكة مصرية عادية.
const Duration backgroundPushTimeout = Duration(seconds: 5);

/// نتيجة دفعة واحدة — **كل الحالات، مش اللي بترمي بس**.
///
/// الحالتين `noSession` و`notLinked` كانتا بترجّعا من `push()` في صمت عن
/// قصد (جهاز مش مربوط لازم ما يعملش ولا نداء شبكة). المشكلة إن «ساكت لأنه
/// مظبوط كده» و«ساكت لأنه بايظ» بقوا شكلهم واحد من برّه: جرعة اتأكدت من
/// شاشة القفل وما وصلتش السحابة، ومفيش سطر واحد بيقول ليه. النتيجة بقت
/// قيمة بتترجع وبتتقال، فالفرق بان.
enum PushOutcome {
  /// مفيش `SyncService` أصلاً — إعداد ناقص، أو تهيئة السحابة فشلت.
  noConfig,

  /// فيه دفعة شغّالة؛ اللي بعدها هيتعاد تلقائياً.
  busy,

  noSession,
  notLinked,

  /// وصل — شوف عدد الصفوف.
  pushed,

  timedOut,
  failed,
}

/// جملة واحدة بتوصف النتيجة — دالة نقية عشان الاختبار يثبّت الكلام نفسه.
String describePushOutcome(PushOutcome outcome, {int rows = 0, Duration? timeout}) =>
    switch (outcome) {
      PushOutcome.noConfig => 'مفيش إعداد سحابة — لا جلسة ولا مفاتيح، الجهاز أوفلاين بالكامل',
      PushOutcome.busy => 'فيه دفعة شغّالة — هتتعاد بعدها',
      PushOutcome.noSession => 'مفيش جلسة — الجهاز مش مسجّل دخول',
      PushOutcome.notLinked => 'الجهاز مش مربوط بحد — مفيش رفع أصلاً',
      PushOutcome.pushed when rows == 0 => 'مفيش صفوف متوسّخة — مفيش حاجة تترفع',
      PushOutcome.pushed => 'اترفع ${arabicNumber(rows)} صف',
      PushOutcome.timedOut =>
        'عدّى المهلة (${arabicNumber(timeout?.inSeconds ?? backgroundPushTimeout.inSeconds)} ث) '
              '— الصفوف بتفضل متوسّخة',
      PushOutcome.failed => 'فشل — الصفوف بتفضل متوسّخة',
    };

/// وقت على السلك: UTC ISO دايماً — المحطة المحلية بتفضل على الجهاز.
String utcIso(DateTime local) => local.toUtc().toIso8601String();

String dateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// حالة الرفع زي ما هي على الجهاز دلوقتي — لفحص السلامة.
///
/// **قراية بس**: مفيش أي نداء شبكة هنا، فاستدعاؤها آمن في أي وقت.
class SyncStats {
  const SyncStats({
    required this.dirtyCount,
    this.oldestDirtyAt,
    this.lastSyncedAt,
  });

  /// صفوف اتغيّرت وما اترفعتش.
  final int dirtyCount;

  /// أقدم صف متوسّخ — ده اللي بيحدّد لو الابن هيتبلّغ بالغلط.
  final DateTime? oldestDirtyAt;

  /// آخر مرة صف اترفع بنجاح.
  final DateTime? lastSyncedAt;
}

/// الجداول اللي بتتزامن — مكتوبة هنا مرة واحدة عشان الإحصاء يمشي عليهم.
const List<String> syncedTableNames = [
  'patients',
  'day_routines',
  'medications',
  'dose_schedules',
  'fixed_timings',
  'dose_events',
  'records',
  'readings',
  'lab_results',
  'visit_questions',
  'emergency_profile',
];

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
  /// دفعة واحدة محدودة — **وبتقول نتيجتها في كل مرة**.
  ///
  /// السطر ده هو الفرق بين «الجرعة وصلت» و«الجرعة قاعدة على الموبايل»،
  /// وقبل كده مكانش فيه غيره غير السكوت. بيتطبع بسابقة `Handle:` زي باقي
  /// سطور صحوة شاشة القفل، عشان يتلاقوا مع بعض في Console.app.
  Future<PushOutcome> pushOnce({Duration? timeout}) async {
    final limit = timeout ?? _backgroundTimeout;
    PushOutcome outcome;
    try {
      outcome = await push().timeout(limit);
    } on TimeoutException {
      outcome = PushOutcome.timedOut;
    } catch (error, stack) {
      // push() بتبلع أخطاءها جوّه، فده للنادر اللي بيفلت — ومش هنوقّع
      // isolate بيسجّل جرعة عشان السحابة اتعبت.
      outcome = PushOutcome.failed;
      diag('Sync: دفعة الخلفية فشلت: $error\n$stack');
    }
    diag('Handle: الرفع للسحابة — '
        '${describePushOutcome(outcome, rows: _rowsPushed, timeout: limit)}');
    return outcome;
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

  /// إحصاء المتوسّخ — نفس تعريف الاتساخ اللي الدفع بيمشي عليه بالظبط.
  ///
  /// استعلام واحد على اتحاد الجداول بدل ١١ استعلام: الرقم ده بيتقرا في
  /// فحص السلامة، والفحص مجاملة — ماينفعش يكلّف أكتر من اللي بيحميه.
  Future<SyncStats> stats() async {
    final union = syncedTableNames
        .map((t) => 'select updated_at_ms, synced_at_ms from $t')
        .join(' union all ');
    const dirty = 'synced_at_ms is null or synced_at_ms < updated_at_ms';
    final row = await _db.customSelect(
      'select '
      'sum(case when $dirty then 1 else 0 end) as dirty_count, '
      'min(case when $dirty then updated_at_ms end) as oldest_dirty, '
      'max(synced_at_ms) as last_synced '
      'from ($union)',
    ).getSingle();

    DateTime? at(String column) {
      final ms = row.data[column] as int?;
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return SyncStats(
      dirtyCount: (row.data['dirty_count'] as int?) ?? 0,
      oldestDirtyAt: at('oldest_dirty'),
      lastSyncedAt: at('last_synced'),
    );
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
  Future<PushOutcome> push() async {
    if (_pushing) {
      _pushAgain = true;
      return PushOutcome.busy;
    }
    if (!_hasSession()) return PushOutcome.noSession;
    if (!await _linked()) return PushOutcome.notLinked;

    _pushing = true;
    _rowsPushed = 0;
    var failed = false;
    try {
      await _pushPatients();
      await _pushDayRoutines();
      await _pushMedications();
      await _pushDoseSchedules();
      await _pushFixedTimings();
      await _pushDoseEvents();
      // الملف الصحي (D5.1) — بعد المريض، والسجلات قبل سطور تحاليلها
      await _pushRecords();
      await _pushReadings();
      await _pushLabResults();
      await _pushVisitQuestions();
      await _pushEmergencyProfile();
    } catch (error, stack) {
      // بنسجّل ونسيب الصفوف متوسّخة — المحاولة الجاية مع أي محفّز.
      failed = true;
      diag('Sync: push فشلت وهتتعاد: $error\n$stack');
    } finally {
      _pushing = false;
      if (_pushAgain) {
        _pushAgain = false;
        unawaited(push());
      }
    }
    return failed ? PushOutcome.failed : PushOutcome.pushed;
  }

  /// كام صف اترفع في آخر دفعة — بيتصفّر مع كل دفعة، وبيتعدّ في المكان
  /// الوحيد اللي بيرفع ([_upsertAndMark]).
  int _rowsPushed = 0;

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
      _rowsPushed += chunk.length;
      for (final r in chunk) {
        await mark(r.uuid, r.updatedAtMs);
      }
    }
  }

  Future<void> _pushPatients() async {
    // مريض لسه ما اتعرّفناش عليه (صف «أنا» الفاضي اللي ensurePatient بيعمله
    // عند الإقلاع — D4) مالوش مكان في السحابة: من غير روتين ومن غير أدوية
    // مفيش حاجة تتتابع، وعلى موبايل ابن الصف ده مش مريض أصلاً. بيفضل متوسّخ
    // ويطلع أول ما يبقى ليه روتين أو دوا.
    final rows = await (_db.select(_db.patients)
          ..where((t) =>
              _dirty(_cols(t.syncedAtMs, t.updatedAtMs)) &
              (existsQuery(_db.select(_db.dayRoutines)..where((r) => r.patientId.equalsExp(t.id))) |
                  existsQuery(_db.select(_db.medications)..where((m) => m.patientId.equalsExp(t.id))))))
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
                // الإيقاف الناعم بيترفع زي أي عمود — **مفيش مسح** (دين ١)،
                // والسحابة بتاخد نفس الصف محدّث فما بيرجعش يعيش.
                'removed_at': m.removedAt == null ? null : utcIso(m.removedAt!),
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
                'stopped_at': s.stoppedAt == null ? null : utcIso(s.stoppedAt!),
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

  // ------------------------------------------------ الملف الصحي (D5.1)
  // الابن هيقراه في D5.2. كل جدول بنفس شكل _pushMedications بالظبط: join
  // عشان الـuuid، شرط الوسخ المشتق، وعلامة بعد الـupsert بس.

  /// السجلات — **من غير مسار الصورة**: مسار ملف على موبايل الأب مالوش
  /// معنى في السحابة (الصور في D5.3).
  ///
  /// **والممسوح بيتمسح من السحابة هنا، مش بعد ٣٠ يوم.** الراجل مسح روشتة
  /// من ملفه؛ إنها تفضل في ملف ابنه شهر كمان مش «مهلة»، ده نفس الصف اللي
  /// هو مش عايزه.
  ///
  /// بترفع الشاهدة الأول (upsert بـ`deleted_at`) وبعدين بتمسح، والترتيب ده
  /// مقصود: لو المسح فشل — شبكة قطعت في النص — الصف السحابي يبقى معلّم
  /// ممسوح، فاستعلام الابن (`deleted_at is null`) ما بيشوفوش، وكرون
  /// `purge_deleted_records` بتاع 0012 بيشيله بعد ٣٠ يوم كشبكة أمان. لو
  /// مسحنا على طول وفشلنا، الصف بيفضل ظاهر للابن على طول. الصف بيفضل
  /// متوسّخ في الحالتين فالمحاولة بتتكرر.
  Future<void> _pushRecords() async {
    final query = _db.select(_db.records).join([
      innerJoin(_db.patients, _db.patients.id.equalsExp(_db.records.patientId)),
    ])
      ..where(_db.records.syncedAtMs.isNull() |
          _db.records.syncedAtMs.isSmallerThan(_db.records.updatedAtMs));
    final rows = await query.get();
    ({String uuid, int updatedAtMs, Map<String, dynamic> json}) wire(TypedResult row) {
      final r = row.readTable(_db.records);
      final p = row.readTable(_db.patients);
      return (
        uuid: r.uuid,
        updatedAtMs: r.updatedAtMs,
        json: {
          'uuid': r.uuid,
          'patient_uuid': p.uuid,
          'kind': r.kind.name,
          'title': r.title,
          'happened_at': utcIso(r.happenedAt),
          'doctor': r.doctor,
          'place': r.place,
          'notes': r.notes,
          'deleted_at': r.deletedAt == null ? null : utcIso(r.deletedAt!),
          'checkup_stage': r.checkupStage,
          // نوع المتابعة (نسخة ١٩ / 0017) — من غيره الرقم فوق ما ينفعش
          // يتفسّر: ٢ في تحليل «حجز المعمل»، وفي زيارة «الزيارة تمت».
          // **ومصدر المتابعة مش هنا عن قصد**: ده رقم صف داخلي، ومالوش أي
          // معنى برّه الموبايل — نفس سبب مسار الصورة. (الحارس بيقرا الملف
          // كله، فحتى الاسم في تعليق بيوقّعه — وده مقصود.)
          'follow_kind': r.followKind,
          'fasting_reminder_at':
              r.fastingReminderAt == null ? null : utcIso(r.fastingReminderAt!),
          // نسخة ١٧ — مواعيد المتابعة اللي الإنسان قالها
          'checkup_stage_since':
              r.checkupStageSince == null ? null : utcIso(r.checkupStageSince!),
          'lab_booking_at': r.labBookingAt == null ? null : utcIso(r.labBookingAt!),
          'result_ready_at': r.resultReadyAt == null ? null : utcIso(r.resultReadyAt!),
          'doctor_visit_at': r.doctorVisitAt == null ? null : utcIso(r.doctorVisitAt!),
        }
      );
    }

    Future<void> mark(String uuid, int ms) =>
        (_db.update(_db.records)..where((t) => t.uuid.equals(uuid)))
            .write(RecordsCompanion(syncedAtMs: Value(ms)));

    final live = [for (final row in rows) if (row.readTable(_db.records).deletedAt == null) row];
    final gone = [for (final row in rows) if (row.readTable(_db.records).deletedAt != null) row];

    await _upsertAndMark('records', [for (final row in live) wire(row)], mark);

    if (gone.isEmpty) return;
    final tombstones = [for (final row in gone) wire(row)];
    // الرفع من غير علامة: العلامة بعد المسح بس، وإلا فشل المسح بينضّف الصف
    // من الوسخ والمحاولة الجاية ما بتشوفوش أصلاً.
    for (var i = 0; i < tombstones.length; i += _batchSize) {
      final chunk = tombstones.sublist(
          i, i + _batchSize > tombstones.length ? tombstones.length : i + _batchSize);
      await _remote.upsert('records', [for (final r in chunk) r.json]);
      await _remote.deleteByUuid('records', [for (final r in chunk) r.uuid]);
      for (final r in chunk) {
        await mark(r.uuid, r.updatedAtMs);
      }
    }
  }

  Future<void> _pushReadings() async {
    final query = _db.select(_db.readings).join([
      innerJoin(_db.patients, _db.patients.id.equalsExp(_db.readings.patientId)),
    ])
      ..where(_db.readings.syncedAtMs.isNull() |
          _db.readings.syncedAtMs.isSmallerThan(_db.readings.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'readings',
      [
        for (final row in rows)
          () {
            final r = row.readTable(_db.readings);
            final p = row.readTable(_db.patients);
            return (
              uuid: r.uuid,
              updatedAtMs: r.updatedAtMs,
              json: {
                'uuid': r.uuid,
                'patient_uuid': p.uuid,
                'value_mg_dl': r.valueMgDl,
                'measured_at': utcIso(r.measuredAt),
                'context': r.context.name,
              }
            );
          }(),
      ],
      (uuid, ms) => (_db.update(_db.readings)..where((t) => t.uuid.equals(uuid)))
          .write(ReadingsCompanion(syncedAtMs: Value(ms))),
    );
  }

  /// سطور التحليل بتتربط بسجلها بالـuuid — الـid المحلي عمره ما يطلع.
  Future<void> _pushLabResults() async {
    final query = _db.select(_db.labResults).join([
      innerJoin(_db.records, _db.records.id.equalsExp(_db.labResults.recordId)),
    ])
      ..where(_db.labResults.syncedAtMs.isNull() |
          _db.labResults.syncedAtMs.isSmallerThan(_db.labResults.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'lab_results',
      [
        for (final row in rows)
          () {
            final l = row.readTable(_db.labResults);
            final r = row.readTable(_db.records);
            return (
              uuid: l.uuid,
              updatedAtMs: l.updatedAtMs,
              json: {
                'uuid': l.uuid,
                'record_uuid': r.uuid,
                'test_name': l.testName,
                'value': l.value,
                'unit': l.unit,
                // نطاق الورقة (v18 / 0016) — عشان الابن يشوف نفس الرقم بنفس
                // النطاق، مش رقم عريان.
                'ref_low': l.refLow,
                'ref_high': l.refHigh,
                'ref_text': l.refText,
              }
            );
          }(),
      ],
      (uuid, ms) => (_db.update(_db.labResults)..where((t) => t.uuid.equals(uuid)))
          .write(LabResultsCompanion(syncedAtMs: Value(ms))),
    );
  }

  Future<void> _pushVisitQuestions() async {
    final query = _db.select(_db.visitQuestions).join([
      innerJoin(_db.patients, _db.patients.id.equalsExp(_db.visitQuestions.patientId)),
    ])
      ..where(_db.visitQuestions.syncedAtMs.isNull() |
          _db.visitQuestions.syncedAtMs.isSmallerThan(_db.visitQuestions.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'visit_questions',
      [
        for (final row in rows)
          () {
            final q = row.readTable(_db.visitQuestions);
            final p = row.readTable(_db.patients);
            return (
              uuid: q.uuid,
              updatedAtMs: q.updatedAtMs,
              json: {
                'uuid': q.uuid,
                'patient_uuid': p.uuid,
                'body': q.body,
                // `created_at` في السحابة بتاع السيرفر — لحظة الكتابة اسمها written_at
                'written_at': utcIso(q.createdAt),
                'asked': q.asked,
              }
            );
          }(),
      ],
      (uuid, ms) => (_db.update(_db.visitQuestions)..where((t) => t.uuid.equals(uuid)))
          .write(VisitQuestionsCompanion(syncedAtMs: Value(ms))),
    );
  }

  /// فصيلة الدم والحساسية والأمراض — **من غير جهات الاتصال**. أسماء وأرقام
  /// التليفونات بتفضل على موبايل الأب: السيرفر ما بيشيلش ولا رقم تليفون،
  /// والعمود مش موجود في السحابة أصلاً (0012). رفعها قرار خصوصية لوحده.
  Future<void> _pushEmergencyProfile() async {
    final query = _db.select(_db.emergencyProfile).join([
      innerJoin(_db.patients, _db.patients.id.equalsExp(_db.emergencyProfile.patientId)),
    ])
      ..where(_db.emergencyProfile.syncedAtMs.isNull() |
          _db.emergencyProfile.syncedAtMs.isSmallerThan(_db.emergencyProfile.updatedAtMs));
    final rows = await query.get();
    await _upsertAndMark(
      'emergency_profile',
      [
        for (final row in rows)
          () {
            final e = row.readTable(_db.emergencyProfile);
            final p = row.readTable(_db.patients);
            return (
              uuid: e.uuid,
              updatedAtMs: e.updatedAtMs,
              json: {
                'uuid': e.uuid,
                'patient_uuid': p.uuid,
                'blood_type': e.bloodType,
                'allergies': e.allergies,
                'chronic_conditions': e.chronicConditions,
              }
            );
          }(),
      ],
      (uuid, ms) => (_db.update(_db.emergencyProfile)..where((t) => t.uuid.equals(uuid)))
          .write(EmergencyProfileCompanion(syncedAtMs: Value(ms))),
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
