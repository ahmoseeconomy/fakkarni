import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:typed_data';

import '../../core/diagnostics.dart';
import '../../domain/care/medication_change.dart';
import '../care/medication_changes.dart';
import '../db/app_database.dart';
import '../files/attachment_store.dart';
import '../files/med_photo_sync.dart';
import '../files/med_photos.dart';
import '../../domain/health/follow_up.dart';
import '../db/tables.dart' show RecordKind;
import '../repositories/medication_repository.dart';
import '../repositories/records_repository.dart';
import '../repositories/not_bought_repository.dart';
import '../repositories/stock_repository.dart';
import '../services/appointment_scheduler.dart';
import '../services/checkup_service.dart';
import '../repositories/routine_repository.dart';
import '../services/reminder_scheduler.dart';

/// **سحبة تغييرات الأدوية اللي اقترحها ممرض** (المرحلة ب) لموبايل الأب.
///
/// كل تغيير بيتطبّق بنفس سكّة الأب: الإضافة بـ`addMedicationWithDoses`
/// (المراسي بتتحلّ بروتين الأب هو)، والإيقاف بـ`stopMedication`، والجرعة
/// بـ`updateAmount` — وبعدها `rescheduleAll`. **تعديل الأب المحلي بيكسب**:
/// دوا اتعدّل على الموبايل بعد ما التغيير اتبعت ما بيتلمسش، والتعارض
/// بيتسجّل على الصف (`conflict`) وفي diag. مجاملة: بيسجّل وما بيرميش.
class MedicationChangePuller {
  MedicationChangePuller({
    required this.remote,
    required this.db,
    required this.routines,
    required this.medications,
    required this.scheduler,
    required this.patientId,
    this.clock = DateTime.now,
    this.photoRemote,
    this.photoStore,
    this.preparePhoto,
  });

  /// ٠٠٢٩: الباكت ومكان صور الأدوية — null = مفيش سحابة للصور، والتغيير
  /// من نوع 'photo' بيتساب مستني.
  final MedPhotoRemote? photoRemote;
  final AttachmentStore? photoStore;

  /// التصغير وشيل الـEXIF — متحقن للاختبارات (الافتراضي `compute`).
  final Future<Uint8List?> Function(Uint8List raw)? preparePhoto;

  final MedicationChangeRemote remote;
  final AppDatabase db;
  final RoutineRepository routines;
  final MedicationRepository medications;
  final ReminderScheduler scheduler;
  final int patientId;
  final DateTime Function() clock;

  static const noticesKey = 'medChanges.notices';
  static const maxNotices = 5;

  /// الجُمل اللي «يومك» بتعرضها («سارة ضافت دوا Concor») — بتتحمّل من
  /// التخزين عند البناء وبتتمسح بدوسة.
  static final ValueNotifier<List<String>> notices = ValueNotifier<List<String>>(const []);

  static Future<void> loadNotices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      notices.value = prefs.getStringList(noticesKey) ?? const [];
    } catch (_) {}
  }

  static Future<void> clearNotices() async {
    notices.value = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(noticesKey);
    } catch (_) {}
  }

  bool _running = false;

  /// بيرجّع عدد التغييرات اللي اتطبّقت.
  Future<int> pull() async {
    if (_running) return 0;
    _running = true;
    try {
      final patient = await routines.getPatient(patientId);
      if (patient == null) return 0;
      final pending = await remote.fetchPending(patient.uuid);
      if (pending.isEmpty) return 0;
      var applied = 0;
      final lines = <String>[];
      for (final change in pending) {
        final outcome = await _apply(change);
        try {
          await remote.markApplied(change.uuid, outcome);
        } catch (error) {
          diag('MedChange: تعليم ${change.uuid} وقع ($error)');
        }
        if (outcome == ChangeOutcome.applied) {
          applied++;
          lines.add(medicationChangeNotice(change.actorName, change.kind, changeSubject(change)));
        }
        diag('MedChange: ${change.kind.name} ${change.medicationName ?? change.payload.name ?? ''} → ${outcome.name}');
      }
      if (applied > 0) {
        await scheduler.rescheduleAll(now: clock());
        await remember(lines);
      }
      return applied;
    } catch (error) {
      diag('MedChange: السحبة وقعت ($error)');
      return 0;
    } finally {
      _running = false;
    }
  }

  /// ٠٠٢٩: صورة من الممرض. **بتتحقق الأول**: المسار لازم يبقى تحت
  /// `pending/` بتاع المريض ده، والملف لازم يتفكّ كصورة. غير كده بتترفض
  /// (`missing`) وبتتسجّل للأدمن — المريض ما بيشوفش حاجة. لو اتقبلت:
  /// بتعدّي على نفس التجهيز (لفّ، ≤٨٠٠، من غير EXIF)، بتتحفظ محلي، بتترفع
  /// كالنسخة الرسمية، وبعدين نسخة `pending/` بتتمسح.
  Future<ChangeOutcome> _applyPhoto(MedicationChange change) async {
    final remote = photoRemote;
    final store = photoStore;
    if (remote == null || store == null) {
      diag('MedChange: صورة وصلت والموبايل ده مالوش باكت صور');
      return ChangeOutcome.missing;
    }
    final patient = await routines.getPatient(patientId);
    final uuid = change.medicationUuid;
    final path = change.payload.photoPath;
    if (patient == null || uuid == null) return ChangeOutcome.missing;
    if (!pendingPhotoPathValid(path, patient.uuid)) {
      await recordMediaRejected(clock(), 'مسار برّه pending بتاع المريض: $path');
      return ChangeOutcome.missing;
    }
    final med = await (db.select(db.medications)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (med == null || med.removedAt != null) return ChangeOutcome.missing;
    final raw = await remote.download(path!);
    if (raw == null) {
      await recordMediaRejected(clock(), 'الصورة مش موجودة: $path');
      return ChangeOutcome.missing;
    }
    final photos = MedPhotos(db, store, prepare: preparePhoto);
    if (!await photos.setFromBytes(med.id, raw)) {
      await recordMediaRejected(clock(), 'الملف مش صورة: $path');
      try {
        await remote.remove([path]);
      } catch (_) {}
      return ChangeOutcome.missing;
    }
    // النسخة الرسمية دلوقتي، ونسخة الممرض تتمسح — الاتنين مجاملة: الطابور
    // بيكمّل الرفع لو فشل هنا
    await MedPhotoSync(db: db, remote: remote, store: store, clock: clock).sync(patientId: patientId);
    try {
      await remote.remove([path]);
    } catch (error) {
      diag('MedChange: نسخة pending ما اتمسحتش ($error)');
    }
    return ChangeOutcome.applied;
  }

  Future<ChangeOutcome> _apply(MedicationChange change) async {
    switch (change.kind) {
      case MedicationChangeKind.record:
        // ٠٠٢٦: ورقة من غير صورة — نفس سكّة «اكتب ورقة بإيدك»
        final p = change.payload;
        final kind = RecordKind.values.asNameMap()[p.recordKind];
        final title = p.name?.trim() ?? '';
        if (kind == null || title.isEmpty) return ChangeOutcome.missing;
        final today = clock();
        await RecordsRepository(db).add(
          patientId: patientId,
          kind: kind,
          title: title,
          happenedAt: p.happenedAt ?? DateTime(today.year, today.month, today.day),
          doctor: _blankToNull(p.doctor),
          place: _blankToNull(p.place),
          notes: _blankToNull(p.notes),
        );
        return ChangeOutcome.applied;
      case MedicationChangeKind.restock:
        // **بيتزوّد، مش بيتكتب فوق** — فمفيش «تعديل الأب كسب» هنا: الجرعات
        // اللي اتاخدت بعد الطلب بتحرّك المخزون، وده مش تعارض.
        final uuid = change.medicationUuid;
        final q = change.payload.quantity;
        if (uuid == null || q == null || q <= 0) return ChangeOutcome.missing;
        final med = await (db.select(db.medications)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        if (med == null || med.removedAt != null) return ChangeOutcome.missing;
        await StockRepository(db).restock(med.id, q);
        return ChangeOutcome.applied;
      case MedicationChangeKind.appointment:
        // ٠٠٢٦: نفس «ميعاد جديد» بالظبط — المتابعة وميعادها وإشعاراتها
        final p = change.payload;
        final kind = FollowKind.fromStored(p.followKind);
        final day = p.day;
        if (day == null) return ChangeOutcome.missing;
        final today = clock();
        await CheckupService(db, scheduler.sink).bookAppointment(
          patientId: patientId,
          kind: kind,
          title: p.name?.trim() ?? '',
          day: day,
          doctor: _blankToNull(p.doctor),
          today: DateTime(today.year, today.month, today.day),
        );
        try {
          await AppointmentScheduler(db: db, patientId: patientId, sink: scheduler.sink).refresh(now: today);
        } catch (error) {
          diag('MedChange: إشعارات الميعاد ما اتجدولتش — التذكيرات مش متأثرة ($error)');
        }
        return ChangeOutcome.applied;
      case MedicationChangeKind.add:
        final p = change.payload;
        final name = p.name?.trim() ?? '';
        if (name.isEmpty || p.timings.isEmpty) return ChangeOutcome.missing;
        final today = clock();
        await medications.addMedicationWithDoses(
          patientId: patientId,
          name: name,
          timings: p.timings,
          startDate: p.startDate ?? DateTime(today.year, today.month, today.day),
          amountLabel: p.amountLabel,
          durationDays: p.durationDays,
          alertMode: p.alertMode,
          purpose: p.purpose,
          instructions: p.instructions,
        );
        return ChangeOutcome.applied;
      case MedicationChangeKind.photo:
        return _applyPhoto(change);
      case MedicationChangeKind.bought:
        // ٠٠٣١: بيشيل العلامة وبس. **المخزون ما بيتلمسش** — مفيش كمية
        // نخمّنها؛ لو متتبّع، المريض بيسجّل العلبة من «اشتريت علبة جديدة».
        // ومفيش «تعديل الأب كسب»: العلامة دي مش بتكتب فوق حاجة.
        final uuid = change.medicationUuid;
        if (uuid == null) return ChangeOutcome.missing;
        final med = await (db.select(db.medications)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        if (med == null || med.removedAt != null) return ChangeOutcome.missing;
        await NotBoughtRepository(db, clock: clock).markBought(med.id);
        return ChangeOutcome.applied;
      case MedicationChangeKind.stop:
      case MedicationChangeKind.amount:
        final uuid = change.medicationUuid;
        if (uuid == null) return ChangeOutcome.missing;
        final row = await (db.select(db.medications)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        if (row == null || row.removedAt != null) return ChangeOutcome.missing;
        if (localEditWins(
          localUpdatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs),
          changeCreatedAt: change.createdAt,
        )) {
          diag('MedChange: تعارض — الأب عدّل ${row.name} بعد اقتراح الممرض، التعديل المحلي كسب');
          return ChangeOutcome.conflict;
        }
        if (change.kind == MedicationChangeKind.stop) {
          if (row.stoppedAt != null) return ChangeOutcome.applied;
          await medications.stopMedication(row.id, now: clock());
        } else {
          await (db.update(db.medications)..where((t) => t.id.equals(row.id))).write(
            MedicationsCompanion(
              amountLabel: Value(change.payload.amountLabel?.trim()),
              amountUnknown: const Value(false),
            ),
          );
        }
        return ChangeOutcome.applied;
    }
  }

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  /// بيضيف جُمل لكارت «يومك» — سحبة «خرج من الدايرة» بتنده عليها كمان.
  static Future<void> remember(List<String> lines) async {
    final merged = [...lines, ...notices.value].take(maxNotices).toList();
    notices.value = merged;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(noticesKey, merged);
    } catch (_) {}
  }
}
