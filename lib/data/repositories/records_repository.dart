import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables.dart';
import '../files/attachment_store.dart';

/// الملف الصحي (D3.5) — محلي. SyncService ما بيقراهوش.
class RecordsRepository {
  RecordsRepository(this._db);

  final AppDatabase _db;

  /// عنوان الشاهدة. الصف الممسوح بيفضل موجود **من غير محتواه**، والعمود
  /// ده `not null` هنا وفي السحابة، فمحتاج كلمة. محدش بيشوفها: كل قراية
  /// بتفلتر الممسوح، والابن كمان (`recordFromRow` بترجّع null).
  static const tombstoneTitle = 'اتمسح';

  /// كل السجلات — **من غير الممسوح**. الأحدث الأول.
  ///
  /// كانت بترجّع الممسوح كمان عشان يتعرض مشطوب و«↺ رجّعه» جنبه. المسح
  /// بقى مسح: الصف بيختفي من هنا في نفس اللحظة.
  Stream<List<RecordRow>> watchAll(int patientId) => (_db.select(_db.records)
        ..where((t) => t.patientId.equals(patientId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.happenedAt), (t) => OrderingTerm.desc(t.id)]))
      .watch();

  Future<List<RecordRow>> all(int patientId) => (_db.select(_db.records)
        ..where((t) => t.patientId.equals(patientId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.happenedAt), (t) => OrderingTerm.desc(t.id)]))
      .get();

  /// بيحفظ اللي اتكتب بالظبط؛ الفاضي null. العنوان إجباري.
  Future<int> add({
    required int patientId,
    required RecordKind kind,
    required String title,
    required DateTime happenedAt,
    String? doctor,
    String? place,
    String? notes,

    /// مسار **نسبي** للصورة اللي السجل جه منها ([AttachmentStore]).
    ///
    /// **الصورة بتفضل على الموبايل ده.** `attachment_path` مش بيترفع
    /// للسحابة ومفيش له عمود هناك أصلاً (0012)، واستعلام الابن ما بيختارهوش
    /// — فالوعد اللي في «دائرة الرعاية» («مش هيشوفوا الصور») بيفضل صح.
    /// `health_file_sync_guard_test` بيقع لو الاسم ده ظهر في أي حمولة سحابة.
    String? attachmentPath,
  }) {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError.value(title, 'title', 'العنوان فاضي');
    return _db.into(_db.records).insert(RecordsCompanion.insert(
          patientId: patientId,
          kind: kind,
          title: t,
          happenedAt: happenedAt,
          doctor: Value(clean(doctor)),
          place: Value(clean(place)),
          notes: Value(clean(notes)),
          attachmentPath: Value(clean(attachmentPath)),
        ));
  }

  /// **بيمسح.** المحتوى بيروح دلوقتي، والصف بيفضل شاهدة فاضية.
  ///
  /// «هيفضل باين مشطوب، وهيتمسح نهائي بعد ٣٠ يوم» كان غلط في الحالة اللي
  /// الناس بتمسح فيها فعلاً: روشتة اتقرت غلط أو حاجة الراجل أصلاً ما كانش
  /// عايزها. هو بيمسحها وهي بتفضل في ملفه الطبي شهر.
  ///
  /// اللي بيفضل هو **الشاهدة** — uuid وتاريخ المسح وبس — ودي مش أثر
  /// إهمال: المزامنة بترفع بس (الدين ١)، فلو الصف اتشال محلي من غير أثر،
  /// النسخة السحابية تفضل مكانها من غير ما حاجة تقول إنها اتمسحت، والابن
  /// يفضل شايفها. الشاهدة هي اللي بتسيب المزامنة تمسحها من هناك.
  ///
  /// بيتمسح مع الصف في نفس اللحظة: الصورة المرفقة (ممكن تكون النسخة
  /// الوحيدة من تقرير — وده بيتقال في التأكيد قبل الدوسة)، وسطور التحاليل
  /// بتاعته.
  Future<void> delete(int id, {DateTime? now, AttachmentStore? attachments}) async {
    final row = await (_db.select(_db.records)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await _db.transaction(() async {
      await (_db.delete(_db.labResults)..where((t) => t.recordId.equals(id))).go();
      await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(RecordsCompanion(
        deletedAt: Value(now ?? DateTime.now()),
        title: const Value(tombstoneTitle),
        doctor: const Value(null),
        place: const Value(null),
        notes: const Value(null),
        attachmentPath: const Value(null),
        checkupStage: const Value(null),
        fastingReminderAt: const Value(null),
      ));
    });
    // بعد الصف: صف من غير ملف أهون من ملف يتيم فيه بيانات مريض.
    final path = row.attachmentPath;
    if (path != null) await attachments?.delete(path);
  }
}
