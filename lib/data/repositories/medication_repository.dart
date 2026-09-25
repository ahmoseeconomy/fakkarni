import 'package:drift/drift.dart';

import '../../domain/medication/duplicate_check.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/escalation/alert_mode.dart';
import '../../domain/scheduling/day_pattern.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../dose_state.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import '../mappers.dart';

/// دوا وجداوله مع بعض.
class MedicationSummary {
  MedicationSummary(this.medication, this.schedules);
  final MedicationRow medication;
  final List<DoseSchedule> schedules;
}

/// الأدوية وجرعاتها.
/// دوا واحد زي ما هيتكتب — اسمه وجرعاته ومدته.
typedef MedicationWrite = ({
  String name,
  List<DoseTiming> timings,
  String? amountLabel,
  bool amountUnknown,
  int? durationDays,
  AlertMode? alertMode,
  MedicationPurpose? purpose,
  String? instructions,

  /// بداية الدوا ده لوحده — null = تاريخ الدفعة.
  DateTime? startDate,
});

class MedicationRepository {
  MedicationRepository(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;

  /// لحظة سريان القاعدة ([DoseSchedules.activeFrom]) بتتاخد من هنا — عند
  /// الإنشاء وعند تعديل التوقيت. متحقنة عشان الاختبارات تثبّت «دلوقتي».
  final DateTime Function() _clock;

  JoinedSelectStatement<HasResultSet, dynamic> _activeQuery(int patientId) =>
      _joined(patientId)
        ..where(
          _db.medications.patientId.equals(patientId) &
              _db.medications.stoppedAt.isNull() &
              // المتشال مالوش وجود في أي قايمة، والجرعة الموقوفة ما بتولّدش
              // حاجة جديدة — الجدولة بتقرا من هنا.
              _db.medications.removedAt.isNull() &
              _db.doseSchedules.stoppedAt.isNull(),
        );

  /// نفس الـjoin من غير فلتر الإيقاف — لقايمة «الأدوية» اللي بتعرض الموقوف
  /// في قسم لوحده بدل ما يختفي.
  JoinedSelectStatement<HasResultSet, dynamic> _allQuery(int patientId) =>
      _joined(patientId)
        ..where(
          _db.medications.patientId.equals(patientId) &
              // «موقوفة» قسم في القايمة؛ «متشال» مش قايمة أصلاً.
              _db.medications.removedAt.isNull() &
              _db.doseSchedules.stoppedAt.isNull(),
        );

  JoinedSelectStatement<HasResultSet, dynamic> _joined(int patientId) =>
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
      ]);

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

  /// بيضيف دوا **بكل جرعاته**، في معاملة واحدة.
  ///
  /// الدوا اللي بياخده المريض مرتين أو تلاتة في اليوم هو الحالة العادية مش
  /// الاستثناء، والطريق ده هو **الطريق الوحيد** اللي بيكتب «دوا بـN جرعة»:
  /// شاشة «ضيف دوا» وشاشة مراجعة الروشتة الاتنين بينادوه.
  ///
  /// قبل كده كل شاشة كانت بتكتب بنفسها (`addMedication` وبعدها لفة على
  /// `addDoseSchedule`)، وده اللي خبّى إن تعديل سطر من المراجعة كان بيوصّل
  /// جرعة واحدة بس لشاشة الإضافة: الكتابة كانت مظبوطة، واللي بيتبعتلها لأ.
  /// طريق واحد معناه إن نقص زي ده يبان في مكان واحد.
  ///
  /// ومعاملة واحدة كمان: جرعة وقعت في النص ما بتسيبش دوا ناقص جرعاته.
  Future<int> addMedicationWithDoses({
    required int patientId,
    required String name,
    required List<DoseTiming> timings,
    required DateTime startDate,
    String? amountLabel,
    bool amountUnknown = false,
    DoseRepeat repeat = DoseRepeat.daily,
    int? durationDays,

    /// المادة الفعّالة زي ما اتقرت من العلبة — null في كل طريق تاني.
    /// بيتقرا منها سؤال واحد بعدين: «الدوا ده عندك خلاص؟».
    String? activeIngredient,

    /// نوع التنبيه — null = زي إعداد الجهاز.
    AlertMode? alertMode,

    /// «الدوا ده لإيه؟» و«تعليمات» — اختياريين، null = ما قالش.
    MedicationPurpose? purpose,
    String? instructions,

    /// أنهي أيام (الجولة ٢) — «كل يوم» افتراضياً.
    DayPattern days = DayPattern.everyDay,
  }) {
    if (timings.isEmpty) {
      throw ArgumentError.value(timings, 'timings', 'الدوا لازم له جرعة واحدة على الأقل');
    }
    return _db.transaction(() async {
      final medicationId = await _db.into(_db.medications).insert(
            MedicationsCompanion.insert(
              patientId: patientId,
              name: name,
              amountLabel: Value(amountLabel),
              amountUnknown: Value(amountUnknown),
              activeIngredient: Value(activeIngredient),
              alertMode: Value(alertMode?.storageName),
              purpose: Value(purpose?.storageName),
              instructions: Value(instructions),
            ),
          );
      for (final timing in timings) {
        await _insertSchedule(
          medicationId,
          timing: timing,
          startDate: startDate,
          repeat: repeat,
          durationDays: durationDays,
          days: days,
        );
      }
      return medicationId;
    });
  }

  /// **كل أدوية الروشتة في معاملة واحدة: يا كلهم يا ولا واحد.**
  ///
  /// شاشة المراجعة مسوّدة لحد ما الإنسان يدوس «تمام» — والدوسة دي كتابة
  /// واحدة. قبل كده كانت لفّة نداءات منفصلة، فنص روشتة كان ممكن يتحفظ
  /// والنص التاني لأ (والشاشة تفضل مفتوحة بسطور «اتضافت» وسطور لأ).
  ///
  /// كل سطر بيعدّي من [addMedicationWithDoses] — معاملة متداخلة — فطريق
  /// كتابة «دوا بـN جرعة» يفضل واحد.
  Future<List<int>> addMedicationsWithDoses({
    required int patientId,
    required List<MedicationWrite> medications,
    required DateTime startDate,

    /// ترتيب الأدوية اللي «مرة واحدة» (`DoseRepeat.once`) — الباقي كل يوم.
    Set<int> onceAt = const {},
  }) =>
      _db.transaction(() async {
        final ids = <int>[];
        for (final (i, m) in medications.indexed) {
          ids.add(
            await addMedicationWithDoses(
              patientId: patientId,
              name: m.name,
              timings: m.timings,
              startDate: m.startDate ?? startDate,
              amountLabel: m.amountLabel,
              amountUnknown: m.amountUnknown,
              durationDays: m.durationDays,
              alertMode: m.alertMode,
              purpose: m.purpose,
              instructions: m.instructions,
              repeat: onceAt.contains(i) ? DoseRepeat.once : DoseRepeat.daily,
            ),
          );
        }
        return ids;
      });

  /// دوا بجرعة واحدة — غلاف على [addMedicationWithDoses].
  Future<int> addMedication({
    required int patientId,
    required String name,
    required DoseTiming timing,
    required DateTime startDate,
    String? amountLabel,
    bool amountUnknown = false,
    DoseRepeat repeat = DoseRepeat.daily,
    int? durationDays,
  }) =>
      addMedicationWithDoses(
        patientId: patientId,
        name: name,
        timings: [timing],
        startDate: startDate,
        amountLabel: amountLabel,
        amountUnknown: amountUnknown,
        repeat: repeat,
        durationDays: durationDays,
      );

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
    DayPattern days = DayPattern.everyDay,
  }) =>
      _db.transaction(
        () => _insertSchedule(
          medicationId,
          timing: timing,
          startDate: startDate,
          repeat: repeat,
          durationDays: durationDays,
          days: days,
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
    DayPattern days = DayPattern.everyDay,
  }) async {
    final day = DateTime(startDate.year, startDate.month, startDate.day);
    final cols = dayPatternColumns(days);
    // القاعدة سارية من دلوقتي — جرعة معادها قبل كده ما كانتش موجودة.
    final activeFrom = _clock();

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
                activeFrom: Value(activeFrom),
                weekdaysMask: Value(cols.weekdaysMask),
                everyDays: Value(cols.everyDays),
                cycleOn: Value(cols.cycleOn),
                cycleOff: Value(cols.cycleOff),
              ),
            FixedTiming() => DoseSchedulesCompanion.insert(
                medicationId: medicationId,
                timingKind: const Value(DoseTimingKind.fixed),
                repeat: repeat,
                startDate: day,
                durationDays: Value(durationDays),
                activeFrom: Value(activeFrom),
                weekdaysMask: Value(cols.weekdaysMask),
                everyDays: Value(cols.everyDays),
                cycleOn: Value(cols.cycleOn),
                cycleOff: Value(cols.cycleOff),
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

  /// دوا واحد بجداوله — لشاشة التعديل.
  Stream<MedicationRow?> watchMedication(int medicationId) =>
      (_db.select(_db.medications)..where((t) => t.id.equals(medicationId)))
          .watchSingleOrNull();

  Future<List<DoseSchedule>> schedulesFor(int medicationId) async => _map(
        await (_activeQueryAll()
              ..where(
                _db.doseSchedules.medicationId.equals(medicationId) &
                    _db.doseSchedules.stoppedAt.isNull(),
              ))
            .get(),
      );

  JoinedSelectStatement<HasResultSet, dynamic> _activeQueryAll() =>
      _db.select(_db.doseSchedules).join([
        innerJoin(
          _db.medications,
          _db.medications.id.equalsExp(_db.doseSchedules.medicationId),
        ),
        leftOuterJoin(
          _db.fixedTimings,
          _db.fixedTimings.doseScheduleId.equalsExp(_db.doseSchedules.id),
        ),
      ]);

  /// الأدوية الشغّالة، كل واحد بجداوله — لقايمة «أدويتك».
  Stream<List<MedicationSummary>> watchActiveSummaries(int patientId) =>
      _activeQuery(patientId).watch().map(_summaries);

  /// كل الأدوية — الشغّالة والموقوفة — كل واحد بجداوله. الموقوف بيتعرف من
  /// `medication.stoppedAt`؛ الشاشة هي اللي بتفصله في قسم «موقوفة».
  Stream<List<MedicationSummary>> watchAllSummaries(int patientId) =>
      _allQuery(patientId).watch().map(_summaries);

  List<MedicationSummary> _summaries(List<TypedResult> rows) {
    final byMed = <int, MedicationSummary>{};
    for (final row in rows) {
      final med = row.readTable(_db.medications);
      final schedule = doseScheduleFromRow(
        row.readTable(_db.doseSchedules),
        med,
        fixed: row.readTableOrNull(_db.fixedTimings),
      );
      byMed.putIfAbsent(med.id, () => MedicationSummary(med, [])).schedules.add(schedule);
    }
    return byMed.values.toList();
  }

  /// تغيير توقيت جرعة موجودة — بإيد إنسان من محرّر الجرعة.
  ///
  /// نفس قاعدة الكتابة: النوع على الصف، والساعة الثابتة في جدولها، في
  /// معاملة واحدة. مرساة → أنكر + إزاحة والساعة الثابتة بتتمسح؛ ساعة ثابتة →
  /// المرساة والإزاحة null والساعة بتتكتب في fixed_timings. الصف نفسه بيفضل
  /// (نفس id وuuid) فأحداث اليوم اللي عليه ما بتضيعش.
  /// نوع التنبيه بتاع دوا محفوظ — null = ارجع لإعداد الجهاز. اللي بينده
  /// لازم يعيد الجدولة بعدها: الإعادات بتتبني وقت الجدولة.
  Future<void> setAlertMode(int medicationId, AlertMode? mode) =>
      (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
          .write(MedicationsCompanion(alertMode: Value(mode?.storageName)));

  Future<void> updateTiming(int scheduleId, DoseTiming timing) =>
      _db.transaction(() async {
        await (_db.update(_db.doseSchedules)..where((t) => t.id.equals(scheduleId))).write(
          switch (timing) {
            AnchorTiming(:final anchor, :final offsetMinutes) => DoseSchedulesCompanion(
                timingKind: const Value(DoseTimingKind.anchor),
                anchor: Value(anchor),
                offsetMinutes: Value(offsetMinutes),
                // التوقيت الجديد ساري من لحظة التعديل
                activeFrom: Value(_clock()),
              ),
            FixedTiming() => DoseSchedulesCompanion(
                timingKind: const Value(DoseTimingKind.fixed),
                anchor: const Value(null),
                offsetMinutes: const Value(null),
                activeFrom: Value(_clock()),
              ),
          },
        );
        await (_db.delete(_db.fixedTimings)..where((t) => t.doseScheduleId.equals(scheduleId))).go();
        if (timing case FixedTiming(:final minuteOfDay)) {
          await _db.into(_db.fixedTimings).insert(
                FixedTimingsCompanion.insert(
                  doseScheduleId: Value(scheduleId),
                  minuteOfDay: minuteOfDay.minutes,
                ),
              );
        }
      });

  /// الجرعة زي ما الصيدلي قالها. نص فاضي = لسه مش معروفة.
  ///
  /// دي الحتة الوحيدة اللي بتقفل `amountUnknown` — بإيد إنسان، بقيمة كتبها.
  Future<void> updateAmount(int medicationId, String? amountLabel) {
    final text = amountLabel?.trim();
    final unknown = text == null || text.isEmpty;
    return (_db.update(_db.medications)..where((t) => t.id.equals(medicationId))).write(
      MedicationsCompanion(
        amountLabel: Value(unknown ? null : text),
        amountUnknown: Value(unknown),
      ),
    );
  }

  /// التعليمات والمدة — من شاشة التعديل بس (الإضافة ما بتسألش عنهم).
  ///
  /// المدة على جداول الدوا كلها: null = مفتوحة لحد ما إنسان يوقفها
  /// (القاعدة ٣ — عمرنا ما بنخترع مدة).
  Future<void> updateDetails(
    int medicationId, {
    required String? instructions,
    required int? durationDays,
  }) {
    final text = instructions?.trim();
    return _db.transaction(() async {
      await (_db.update(_db.medications)..where((t) => t.id.equals(medicationId))).write(
        MedicationsCompanion(instructions: Value(text == null || text.isEmpty ? null : text)),
      );
      await (_db.update(_db.doseSchedules)..where((t) => t.medicationId.equals(medicationId)))
          .write(DoseSchedulesCompanion(durationDays: Value(durationDays)));
    });
  }

  /// بيوقف دوا — **بإيد إنسان وبس**، وبيتراجع عنه.
  ///
  /// مفيش أي مسار تاني في التطبيق بيكتب في `stoppedAt`. مدة مفتوحة معناها
  /// التذكير يفضل شغال لحد ما حد يقرر يوقفه.
  ///
  /// وبيعلّم جرعاته الجاية اللي «لسه» بـ`superseded`: من غير كده الصفوف دي
  /// بتفضل `pending` في السحابة، والسيرفر بيصعّد عند +٦٠ على جرعة الأب
  /// وقّفها بنفسه. اللي عدّى ما بيتلمسش — ده تاريخ حصل.
  Future<void> stopMedication(int medicationId, {DateTime? now}) =>
      _db.transaction(() async {
        final at = now ?? _clock();
        await (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
            .write(MedicationsCompanion(stoppedAt: Value(at)));
        await _supersedeFuture(medicationId: medicationId, from: at);
      });

  /// بيرجّع دوا موقوف للخدمة. الجدولة بعدها بتنزّل أيامه من جديد.
  Future<void> resumeMedication(int medicationId) =>
      (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
          .write(const MedicationsCompanion(stoppedAt: Value(null)));

  /// بيشيل الدوا من كل القوايم — **من غير مسح، ومن غير رجوع**.
  ///
  /// الصف وأحداثه القديمة بيفضلوا مكانهم كتاريخ. المسح الحقيقي ممنوع:
  /// المزامنة بترفع بس (دين ١)، و`dose_events` بتتمسح بالـcascade — فالجهاز
  /// ينسى والسحابة تفضل تنبّه الابن على جرعة مابقتش موجودة.
  Future<void> removeMedication(int medicationId, {DateTime? now}) =>
      _db.transaction(() async {
        final at = now ?? _clock();
        await (_db.update(_db.medications)..where((t) => t.id.equals(medicationId)))
            .write(MedicationsCompanion(removedAt: Value(at)));
        await _supersedeFuture(medicationId: medicationId, from: at);
      });

  /// بيوقف جرعة واحدة من دوا شغّال — نفس القاعدة: إيقاف ناعم، مش مسح.
  Future<void> stopDoseSchedule(int scheduleId, {DateTime? now}) =>
      _db.transaction(() async {
        final at = now ?? _clock();
        await (_db.update(_db.doseSchedules)..where((t) => t.id.equals(scheduleId)))
            .write(DoseSchedulesCompanion(stoppedAt: Value(at)));
        await _supersedeFuture(scheduleId: scheduleId, from: at);
      });

  /// «اتغيّرت القاعدة» على كل حدث **جاي** لسه `pending`.
  ///
  /// `superseded` حالة موجودة أصلاً (٠٠١٠): الشاشات بتخفيها، و
  /// `due_escalations` ما بتختارش غير `pending`/`missed` — فالصف ده ما
  /// بيوصلش الابن. ومفيش مسح، فالسحابة بتاخد نفس الصف محدّث.
  Future<void> _supersedeFuture({int? medicationId, int? scheduleId, required DateTime from}) async {
    final ids = scheduleId != null
        ? [scheduleId]
        : (await (_db.select(_db.doseSchedules)
                  ..where((t) => t.medicationId.equals(medicationId!)))
                .get())
            .map((r) => r.id)
            .toList();
    if (ids.isEmpty) return;
    await (_db.update(_db.doseEvents)
          ..where(
            (t) =>
                t.doseScheduleId.isIn(ids) &
                t.state.equalsValue(DoseState.pending) &
                t.scheduledAt.isBiggerThanValue(from),
          ))
        .write(const DoseEventsCompanion(state: Value(DoseState.superseded)));
  }

  /// الأدوية اللي جرعتها مش معروفة ولسه شغّالة — عشان «اسأل الصيدلي عن…».
  Stream<List<MedicationRow>> watchAmountUnknown(int patientId) =>
      (_db.select(_db.medications)
            ..where(
              (t) =>
                  t.patientId.equals(patientId) &
                  t.amountUnknown.equals(true) &
                  t.stoppedAt.isNull() &
                  t.removedAt.isNull(),
            ))
          .watch();

  /// أدويته اللي في القايمة دلوقتي — لفحص «الدوا ده عندك خلاص؟».
  ///
  /// **الموقوف داخل والممسوح خارج.** الموقوف لسه في القايمة تحت
  /// «موقوفة» وبيرجع بدوسة، فعلبة تانية منه تكرار فعلاً؛ الممسوح خرج
  /// من كل قايمة ومفيش رجوع، فالتحذير عنه بيبقى كلام عن حاجة مش موجودة.
  Future<List<ExistingMedicine>> currentMedicines(int patientId) async {
    final rows = await (_db.select(_db.medications)
          ..where((t) => t.patientId.equals(patientId) & t.removedAt.isNull()))
        .get();
    return [
      for (final r in rows)
        ExistingMedicine(name: r.name, activeIngredient: r.activeIngredient),
    ];
  }

  Stream<List<MedicationRow>> watchMedications(int patientId) =>
      (_db.select(_db.medications)
            ..where((t) => t.patientId.equals(patientId) & t.removedAt.isNull()))
          .watch();
}
