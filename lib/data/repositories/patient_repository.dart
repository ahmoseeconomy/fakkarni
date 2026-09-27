import 'package:drift/drift.dart' show Value;

import '../services/reminder_plan.dart' show maxPatients;
import '../db/app_database.dart';

/// صف المريض على الموبايل ده — اسمه وسنّه وخانة إشعاراته.
///
/// (كان اسمه `PatientRepository` وكان بيمسك روتين اليوم كمان؛ الروتين
/// اتشال بقرار المالك في ٢٧ سبتمبر ٢٠٢٦ وفضل المريض.)
class PatientRepository {
  PatientRepository(this._db);

  final AppDatabase _db;

  /// «فيه مريض على الموبايل ده؟» (D4) — مشتقة من البيانات، مفيش عمود دور:
  /// «نتعرّف عليك» اتحفظت (`profile_done_at`). صف «أنا» الفاضي اللي
  /// [ensurePatient] بيعمله عند الإقلاع لوحده مش مريض. الشكل الصح على المدى
  /// الطويل إن الصف ما يتعملش غير لما «نتعرّف عليك» تتحفظ (دين تقني في
  /// CLAUDE.md).
  Stream<bool> watchHasPatient(int patientId) =>
      (_db.select(_db.patients)..where((t) => t.id.equals(patientId)))
          .watchSingleOrNull()
          .map((row) => row?.profileDoneAt != null);

  /// صف المريض — بيتحدّث مع أي تعديل (الاسم أو السن).
  Stream<PatientRow?> watchPatient(int patientId) =>
      (_db.select(_db.patients)..where((t) => t.id.equals(patientId))).watchSingleOrNull();

  /// «نتعرّف عليك»: الاسم والسن — وبتعلّم إن فيه مريض.
  ///
  /// السن **محلي** — SyncService بيبعت uuid والاسم والخانة بس. null لو ما
  /// اتختارش: مش بنكتب رقم ما قالهوش.
  Future<void> saveProfile(
    int patientId, {
    required String name,
    int? age,
    DateTime? now,
  }) =>
      (_db.update(_db.patients)..where((t) => t.id.equals(patientId))).write(
        PatientsCompanion(
          name: Value(name),
          age: Value(age),
          profileDoneAt: Value(now ?? DateTime.now()),
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
