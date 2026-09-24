import 'package:drift/drift.dart' show Value, Variable;

import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/ramadan.dart';
import '../services/reminder_plan.dart' show maxPatients;
import '../db/app_database.dart';
import '../mappers.dart';

/// روتين يوم المريض — بيتسأل مرة واحدة، وكل الجرعات بتترتّب عليه.
class RoutineRepository {
  RoutineRepository(this._db);

  final AppDatabase _db;

  Stream<DayRoutine?> watchRoutine(int patientId) =>
      (_db.select(_db.dayRoutines)
            ..where((t) => t.patientId.equals(patientId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : routineFromRow(row));

  Future<DayRoutine?> getRoutine(int patientId) async {
    final row = await (_db.select(_db.dayRoutines)
          ..where((t) => t.patientId.equals(patientId)))
        .getSingleOrNull();
    return row == null ? null : routineFromRow(row);
  }

  /// بيستبدل الروتين بالكامل.
  ///
  /// ملاحظة مهمة: مفيش أي جرعة بتتلمس هنا. تحريك الفطار بيحرّك كل الجرعات
  /// المربوطة بيه لوحدها لأنها متخزّنة كمرساة، مش كساعة.
  Future<void> saveRoutine(int patientId, DayRoutine routine) =>
      _db.transaction(() async {
        await (_db.delete(_db.dayRoutines)
              ..where((t) => t.patientId.equals(patientId)))
            .go();
        await _db.into(_db.dayRoutines).insert(
              DayRoutinesCompanion.insert(
                patientId: patientId,
                wakeMinutes: routine.wake.minutes,
                breakfastMinutes: routine.breakfast.minutes,
                lunchMinutes: routine.lunch.minutes,
                dinnerMinutes: routine.dinner.minutes,
                sleepMinutes: routine.sleep.minutes,
                unsetAnchors: Value(unsetAnchorsToText(routine.unset)),
              ),
            );
      });

  /// المستخدم حدّد مرساة واحدة بإيده — من محرّر الجرعة أو من مراجعة
  /// الروشتة («بتفطر الساعة كام؟» مرة واحدة). بتتكتب **متحددة**، وباقي
  /// الروتين زي ما هو. لو مفيش صف أصلاً بيتعمل صف مش متحدد منه غير دي.
  Future<void> setAnchor(int patientId, DayAnchor anchor, MinuteOfDay time) async {
    final current = await getRoutine(patientId) ?? DayRoutine.none;
    await saveRoutine(patientId, current.withAnchor(anchor, time));
  }

  // ------------------------------------------------------------ وضع رمضان

  /// الفطار والسحور لو رمضان شغّال — null لو مقفول. وجود النسخة
  /// الاحتياطية هو الحالة نفسها.
  Future<RamadanTimes?> ramadanTimes(int patientId) async {
    final row = await _backup(patientId);
    return row == null
        ? null
        : RamadanTimes(
            iftar: MinuteOfDay(row.iftarMinutes),
            suhoor: MinuteOfDay(row.suhoorMinutes),
          );
  }

  /// الروتين الأصلي المحفوظ وهو رمضان شغّال — للعرض بس (المعاينة بتقارن
  /// الأصل بالساري). null لو رمضان مقفول. **قراءة فقط**: الكتابة والرجوع
  /// من [enterRamadan] و[leaveRamadan] وبس.
  Future<DayRoutine?> ramadanOriginal(int patientId) async {
    final row = await _backup(patientId);
    return row == null
        ? null
        : DayRoutine(
            wake: MinuteOfDay(row.wakeMinutes),
            breakfast: MinuteOfDay(row.breakfastMinutes),
            lunch: MinuteOfDay(row.lunchMinutes),
            dinner: MinuteOfDay(row.dinnerMinutes),
            sleep: MinuteOfDay(row.sleepMinutes),
            unset: unsetAnchorsFromText(row.unsetAnchors),
          );
  }

  /// بيفتح وضع رمضان — أو بيعدّل مواعيده لو مفتوح خلاص.
  ///
  /// أول مرة: الروتين الحالي بيتنسخ بالحرف في routine_backups **قبل** أي
  /// كتابة. لو مفتوح خلاص، النسخة الاحتياطية ما بتتلمسش — روتين رمضان
  /// بيتحسب من الأصل المحفوظ، مش من الروتين الساري، عشان تعديل الفطار
  /// مرتين ما يخلّيش «الأصل» هو رمضان نفسه.
  ///
  /// الصف في day_routines بيتعدّل في مكانه (نفس uuid) — مش delete/insert
  /// زي [saveRoutine] — عشان الرجوع يبقى بالحرف فعلاً والسحابة تشوف صف
  /// واحد بيتغيّر.
  Future<void> enterRamadan(int patientId, RamadanTimes times) =>
      _db.transaction(() async {
        final current = await _routineRow(patientId);
        if (current == null) {
          throw StateError('مفيش روتين للمريض $patientId');
        }
        final existing = await _backup(patientId);
        final original = existing == null
            ? routineFromRow(current)
            : DayRoutine(
                wake: MinuteOfDay(existing.wakeMinutes),
                breakfast: MinuteOfDay(existing.breakfastMinutes),
                lunch: MinuteOfDay(existing.lunchMinutes),
                dinner: MinuteOfDay(existing.dinnerMinutes),
                sleep: MinuteOfDay(existing.sleepMinutes),
                unset: unsetAnchorsFromText(existing.unsetAnchors),
              );

        await _db.into(_db.routineBackups).insertOnConflictUpdate(
              RoutineBackupsCompanion.insert(
                patientId: Value(patientId),
                wakeMinutes: original.wake.minutes,
                breakfastMinutes: original.breakfast.minutes,
                lunchMinutes: original.lunch.minutes,
                dinnerMinutes: original.dinner.minutes,
                sleepMinutes: original.sleep.minutes,
                iftarMinutes: times.iftar.minutes,
                suhoorMinutes: times.suhoor.minutes,
                unsetAnchors: Value(unsetAnchorsToText(original.unset)),
              ),
            );
        await _updateInPlace(patientId, ramadanRoutine(original, times));
      });

  /// بيقفل وضع رمضان: الأصل بيرجع بالحرف والنسخة الاحتياطية بتتمسح.
  /// لو مش مفتوح، مفيش حاجة بتحصل.
  Future<void> leaveRamadan(int patientId) => _db.transaction(() async {
        final backup = await _backup(patientId);
        if (backup == null) return;
        await _updateInPlace(
          patientId,
          DayRoutine(
            wake: MinuteOfDay(backup.wakeMinutes),
            breakfast: MinuteOfDay(backup.breakfastMinutes),
            lunch: MinuteOfDay(backup.lunchMinutes),
            dinner: MinuteOfDay(backup.dinnerMinutes),
            sleep: MinuteOfDay(backup.sleepMinutes),
            unset: unsetAnchorsFromText(backup.unsetAnchors),
          ),
        );
        await (_db.delete(_db.routineBackups)
              ..where((t) => t.patientId.equals(patientId)))
            .go();
      });

  Future<DayRoutineRow?> _routineRow(int patientId) =>
      (_db.select(_db.dayRoutines)
            ..where((t) => t.patientId.equals(patientId)))
          .getSingleOrNull();

  Future<RoutineBackupRow?> _backup(int patientId) =>
      (_db.select(_db.routineBackups)
            ..where((t) => t.patientId.equals(patientId)))
          .getSingleOrNull();

  /// الخمس أعمدة بس — الصف وuuid بتاعه بيفضلوا هما هما.
  Future<void> _updateInPlace(int patientId, DayRoutine routine) =>
      (_db.update(_db.dayRoutines)
            ..where((t) => t.patientId.equals(patientId)))
          .write(DayRoutinesCompanion(
        wakeMinutes: Value(routine.wake.minutes),
        breakfastMinutes: Value(routine.breakfast.minutes),
        lunchMinutes: Value(routine.lunch.minutes),
        dinnerMinutes: Value(routine.dinner.minutes),
        sleepMinutes: Value(routine.sleep.minutes),
        unsetAnchors: Value(unsetAnchorsToText(routine.unset)),
      ));

  /// «فيه مريض على الموبايل ده؟» (D4) — مشتقة من البيانات، مفيش عمود دور:
  /// روتين محفوظ **أو** جنس اتسأل. صف «أنا» الفاضي اللي [ensurePatient]
  /// بيعمله عند الإقلاع لوحده مش مريض. الشكل الصح على المدى الطويل إن الصف
  /// ما يتعملش غير لما «نتعرّف عليك» تتحفظ (دين تقني في CLAUDE.md).
  Stream<bool> watchHasPatient(int patientId) => _db
      .customSelect(
        'SELECT EXISTS(SELECT 1 FROM day_routines WHERE patient_id = ?1) '
        'OR EXISTS(SELECT 1 FROM patients WHERE id = ?1 AND sex IS NOT NULL) AS has_patient',
        variables: [Variable.withInt(patientId)],
        readsFrom: {_db.dayRoutines, _db.patients},
      )
      .watchSingle()
      .map((row) => row.read<bool>('has_patient'));

  /// صف المريض — بيتحدّث مع أي تعديل (الاسم أو الجنس أو السن).
  Stream<PatientRow?> watchPatient(int patientId) =>
      (_db.select(_db.patients)..where((t) => t.id.equals(patientId))).watchSingleOrNull();

  /// «نتعرّف عليك» (المخطط 21): الاسم والجنس والسن.
  ///
  /// الجنس والسن **محليين** — SyncService بيبعت uuid والاسم والخانة بس.
  /// السن null لو ما اتختارش: مش بنكتب رقم ما قالهوش.
  Future<void> saveProfile(
    int patientId, {
    required String name,
    required Sex sex,
    int? age,
  }) =>
      (_db.update(_db.patients)..where((t) => t.id.equals(patientId))).write(
        PatientsCompanion(
          name: Value(name),
          sex: Value(sex),
          age: Value(age),
        ),
      );

  /// صف المريض كامل — شاشة الربط محتاجة uuid والاسم.
  Future<PatientRow?> getPatient(int patientId) =>
      (_db.select(_db.patients)..where((t) => t.id.equals(patientId)))
          .getSingleOrNull();

  /// بيرجّع المريض الوحيد، وبينشئه لو التطبيق لسه جديد.
  Future<int> ensurePatient({String name = 'أنا'}) async {
    final existing =
        await (_db.select(_db.patients)..limit(1)).getSingleOrNull();
    if (existing != null) return existing.id;

    return _db.into(_db.patients).insert(
          PatientsCompanion.insert(
            name: name,
            notificationSlot: Value(await _lowestFreeSlot()),
          ),
        );
  }

  /// خانة المريض في نطاق أرقام الإشعارات.
  Future<int> patientIndex(int patientId) async {
    final row = await (_db.select(_db.patients)
          ..where((t) => t.id.equals(patientId)))
        .getSingleOrNull();
    return row?.notificationSlot ?? 0;
  }

  /// أصغر خانة فاضية.
  ///
  /// بنعيد استخدام خانات المرضى المتشالين بدل ما نعدّ لفوق على طول، عشان
  /// النطاق ما يفضاش من غير ما يكون فيه ١٢٨ مريض فعلاً.
  Future<int> _lowestFreeSlot() async {
    final taken = (await _db.select(_db.patients).get())
        .map((p) => p.notificationSlot)
        .toSet();

    for (var slot = 0; slot < maxPatients; slot++) {
      if (!taken.contains(slot)) return slot;
    }
    throw StateError('مفيش خانة إشعارات فاضية — الحد الأقصى $maxPatients مريض');
  }
}
