import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../domain/care/medication_change.dart';
import '../care/medication_changes.dart';
import '../db/app_database.dart';
import '../repositories/medication_repository.dart';
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
  });

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
          lines.add(medicationChangeNotice(
            change.actorName,
            change.kind,
            change.payload.name ?? change.medicationName ?? 'دوا',
          ));
        }
        diag('MedChange: ${change.kind.name} ${change.medicationName ?? change.payload.name ?? ''} → ${outcome.name}');
      }
      if (applied > 0) {
        await scheduler.rescheduleAll(now: clock());
        await _remember(lines);
      }
      return applied;
    } catch (error) {
      diag('MedChange: السحبة وقعت ($error)');
      return 0;
    } finally {
      _running = false;
    }
  }

  Future<ChangeOutcome> _apply(MedicationChange change) async {
    switch (change.kind) {
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

  Future<void> _remember(List<String> lines) async {
    final merged = [...lines, ...notices.value].take(maxNotices).toList();
    notices.value = merged;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(noticesKey, merged);
    } catch (_) {}
  }
}
