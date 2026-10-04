import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:typed_data';

import '../../core/diagnostics.dart';
import '../../domain/care/medication_change.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/health/vitals.dart';
import '../../domain/medication/meal_relation.dart';
import '../../domain/scheduling/day_pattern.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../core/format/arabic_time.dart' show arabicTime;
import '../../domain/scheduling/minute_of_day.dart';
import '../care/medication_changes.dart';
import '../db/app_database.dart';
import '../db/tables.dart' show RecordKind;
import '../files/attachment_store.dart';
import '../files/med_photo_sync.dart';
import '../files/med_photos.dart';
import '../repositories/medication_repository.dart';
import '../repositories/not_bought_repository.dart';
import '../repositories/patient_repository.dart';
import '../repositories/preferences_repository.dart';
import '../repositories/records_repository.dart';
import '../repositories/stock_repository.dart';
import '../repositories/vitals_repository.dart';
import '../services/appointment_scheduler.dart';
import '../services/checkup_service.dart';
import '../services/medication_save_service.dart';
import '../services/reminder_scheduler.dart';
import 'change_undo.dart';
import '../../domain/medication/medicine_form.dart';

/// **سحبة تغييرات الأدوية اللي اقترحها ممرض** (المرحلة ب) لموبايل الأب.
///
/// كل تغيير بيتطبّق **بنفس سكّة الأب** — `MedicationSaveService` (الكتابة
/// وبعدها الجدولة، في مكان واحد)، فالتذكيرات بتتجدول كأن المريض ضافها
/// بنفسه. **تعديل الأب المحلي بيكسب**: دوا اتعدّل على الموبايل بعد ما
/// التغيير اتبعت ما بيتلمسش، والتعارض بيتسجّل على الصف (`conflict`) وفي
/// diag. مجاملة: بيسجّل وما بيرميش.
///
/// **مرة واحدة لكل uuid** (0035): التغيير اللي اتطبّق بيتسجّل محلياً قبل
/// ما نعلّمه في السحابة — لو النت وقع بين الاتنين، السحبة الجاية بتلاقيه
/// متطبّق وبتعلّمه بس، فمفيش دوا بيتضاف مرتين.
///
/// **«تراجع» في ٢٤ ساعة** ([undo]): بيرجّع بنفس السكّة (شيل ناعم للإضافة،
/// رجوع للإيقاف، الجرعة القديمة، الساعات القديمة…) وبيعلّم الصف `reverted`.
class MedicationChangePuller {
  MedicationChangePuller({
    required this.remote,
    required this.db,
    required this.patients,
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
  final PatientRepository patients;
  final MedicationRepository medications;
  final ReminderScheduler scheduler;
  final int patientId;
  final DateTime Function() clock;

  static const noticesKey = 'medChanges.notices';
  static const appliedKey = 'medChanges.applied';
  static const maxNotices = 5;
  static const maxApplied = 200;

  /// الجُمل اللي «يومك» بتعرضها («سارة ضافت دوا Concor») — بتتحمّل من
  /// التخزين عند البناء وبتتمسح بدوسة «تمام».
  static final ValueNotifier<List<ChangeNotice>> notices = ValueNotifier<List<ChangeNotice>>(const []);

  static Future<void> loadNotices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      notices.value = ChangeNotice.decodeList(prefs.getString(noticesKey));
    } catch (_) {}
  }

  static Future<void> clearNotices() async {
    notices.value = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(noticesKey);
    } catch (_) {}
  }

  static Future<void> dismiss(String uuid) => _setNotices([for (final n in notices.value) if (n.uuid != uuid) n]);

  static Future<void> _setNotices(List<ChangeNotice> list) async {
    notices.value = list;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (list.isEmpty) {
        await prefs.remove(noticesKey);
      } else {
        await prefs.setString(noticesKey, ChangeNotice.encodeList(list));
      }
    } catch (_) {}
  }

  /// بيضيف جُمل لكارت «يومك» — سحبة «خرج من الدايرة» بتنده عليها كمان
  /// (من غير رجوع).
  static Future<void> remember(List<String> lines) => rememberNotices([
        for (final (i, l) in lines.indexed) ChangeNotice(uuid: 'line-${DateTime.now().millisecondsSinceEpoch}-$i', line: l),
      ]);

  static Future<void> rememberNotices(List<ChangeNotice> fresh) =>
      _setNotices([...fresh, ...notices.value].take(maxNotices).toList());

  MedicationSaveService get _saves => MedicationSaveService(medications: medications, scheduler: scheduler, clock: clock);

  bool _running = false;

  Future<Set<String>> _appliedUuids() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(appliedKey)?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _rememberApplied(String uuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(appliedKey) ?? [];
      if (list.contains(uuid)) return;
      list.add(uuid);
      while (list.length > maxApplied) {
        list.removeAt(0);
      }
      await prefs.setStringList(appliedKey, list);
    } catch (_) {}
  }

  /// بيرجّع عدد التغييرات اللي اتطبّقت.
  Future<int> pull() async {
    if (_running) return 0;
    _running = true;
    try {
      final patient = await patients.getPatient(patientId);
      if (patient == null) return 0;
      final pending = await remote.fetchPending(patient.uuid);
      if (pending.isEmpty) return 0;
      final done = await _appliedUuids();
      var applied = 0;
      final fresh = <ChangeNotice>[];
      for (final change in pending) {
        ChangeOutcome outcome;
        ChangeNotice? notice;
        if (done.contains(change.uuid)) {
          // اتطبّق قبل كده والتعليم هو اللي وقع — مفيش تطبيق تاني
          outcome = ChangeOutcome.applied;
        } else {
          final result = await _apply(change);
          outcome = result.outcome;
          notice = result.notice;
          if (outcome == ChangeOutcome.applied) await _rememberApplied(change.uuid);
        }
        try {
          await remote.markApplied(change.uuid, outcome);
        } catch (error) {
          diag('MedChange: تعليم ${change.uuid} وقع ($error)');
        }
        if (notice != null) {
          applied++;
          fresh.add(notice);
        }
        diag('MedChange: ${change.kind.stored} ${change.medicationName ?? change.payload.name ?? ''} → ${outcome.name}');
      }
      if (fresh.isNotEmpty) await rememberNotices(fresh);
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
    final patient = await patients.getPatient(patientId);
    final uuid = change.medicationUuid;
    final path = change.payload.photoPath;
    if (patient == null || uuid == null) return ChangeOutcome.missing;
    if (!pendingPhotoPathValid(path, patient.uuid)) {
      await recordMediaRejected(clock(), 'مسار برّه pending بتاع المريض: $path');
      return ChangeOutcome.missing;
    }
    final med = await _medByUuid(uuid);
    if (med == null) return ChangeOutcome.missing;
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

  Future<MedicationRow?> _medByUuid(String uuid) async {
    final med = await (db.select(db.medications)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    return med == null || med.removedAt != null ? null : med;
  }

  DateTime get _today {
    final t = clock();
    return DateTime(t.year, t.month, t.day);
  }

  ChangeNotice _notice(MedicationChange change, {int? medicationId, int? recordId, Map<String, Object?> previous = const {}, String? detail}) {
    final base = medicationChangeNotice(change.actorName, change.kind, changeSubject(change));
    return ChangeNotice(
      uuid: change.uuid,
      line: detail == null || detail.isEmpty ? base : '$base — $detail',
      kind: change.kind,
      appliedAt: clock(),
      medicationId: medicationId,
      recordId: recordId,
      previous: previous,
    );
  }

  static DayPattern _pattern(MedicationChangePayload p) {
    try {
      if (p.weekdaysMask != null) return OnWeekdays.fromMask(p.weekdaysMask!);
      if (p.everyDays != null) return EveryNDays(p.everyDays!);
      if (p.cycleOn != null && p.cycleOff != null) return OnOffCycle(p.cycleOn!, p.cycleOff!);
    } catch (_) {}
    return DayPattern.everyDay;
  }

  /// «٨:٠٠ ص و٨:٠٠ م» — للجملة اللي المريض بيقراها.
  static String timesLine(List<FixedTiming> timings) =>
      timings.map((t) => arabicTime(DateTime(2000, 1, 1, 0, t.minuteOfDay.minutes))).join(' و');

  Future<({ChangeOutcome outcome, ChangeNotice? notice})> _apply(MedicationChange change) async {
    final p = change.payload;
    switch (change.kind) {
      case MedicationChangeKind.record:
        // ٠٠٢٦: ورقة من غير صورة — نفس سكّة «اكتب ورقة بإيدك»
        final kind = RecordKind.values.asNameMap()[p.recordKind];
        final title = p.name?.trim() ?? '';
        if (kind == null || title.isEmpty) return (outcome: ChangeOutcome.missing, notice: null);
        final id = await RecordsRepository(db).add(
          patientId: patientId,
          kind: kind,
          title: title,
          happenedAt: p.happenedAt ?? _today,
          doctor: _blankToNull(p.doctor),
          place: _blankToNull(p.place),
          notes: _blankToNull(p.notes),
        );
        return (outcome: ChangeOutcome.applied, notice: _notice(change, recordId: id));
      case MedicationChangeKind.restock:
        // **بيتزوّد، مش بيتكتب فوق** — فمفيش «تعديل الأب كسب» هنا: الجرعات
        // اللي اتاخدت بعد الطلب بتحرّك المخزون، وده مش تعارض.
        final q = p.quantity;
        final med = change.medicationUuid == null ? null : await _medByUuid(change.medicationUuid!);
        if (med == null || q == null || q <= 0) return (outcome: ChangeOutcome.missing, notice: null);
        await StockRepository(db).restock(med.id, q);
        return (outcome: ChangeOutcome.applied, notice: _notice(change, medicationId: med.id, previous: {'quantity_added': q}));
      case MedicationChangeKind.stockSet:
        final q = p.quantity;
        final med = change.medicationUuid == null ? null : await _medByUuid(change.medicationUuid!);
        if (med == null || q == null || q < 0) return (outcome: ChangeOutcome.missing, notice: null);
        final stock = StockRepository(db);
        final before = await stock.rowFor(med.id);
        await stock.setQuantity(med.id, q, warnDays: p.warnDays);
        return (
          outcome: ChangeOutcome.applied,
          notice: _notice(change, medicationId: med.id, previous: {'quantity': before?.quantity, 'warn_days': before?.warnDays, 'had_row': before != null}),
        );
      case MedicationChangeKind.appointment:
        // ٠٠٢٦: نفس «ميعاد جديد» بالظبط — المتابعة وميعادها وإشعاراتها
        final kind = FollowKind.fromStored(p.followKind);
        final day = p.day;
        if (day == null) return (outcome: ChangeOutcome.missing, notice: null);
        final id = await CheckupService(db, scheduler.sink).bookAppointment(
          patientId: patientId,
          kind: kind,
          title: p.name?.trim() ?? '',
          day: day,
          doctor: _blankToNull(p.doctor),
          today: _today,
        );
        await _refreshAppointments();
        return (outcome: ChangeOutcome.applied, notice: _notice(change, recordId: id));
      case MedicationChangeKind.add:
        final name = p.name?.trim() ?? '';
        if (name.isEmpty || p.timings.isEmpty) return (outcome: ChangeOutcome.missing, notice: null);
        final id = await _saves.add(
          patientId: patientId,
          name: name,
          timings: p.timings,
          startDate: p.startDate ?? _today,
          amountLabel: p.amountLabel,
          durationDays: p.durationDays,
          alertMode: p.alertMode,
          purpose: p.purpose,
          instructions: p.instructions,
          days: _pattern(p),
          mealRelation: MealRelation.fromStorage(p.mealRelation),
          form: MedicineForm.fromWire(p.form),
        );
        return (outcome: ChangeOutcome.applied, notice: _notice(change, medicationId: id, detail: timesLine(p.timings)));
      case MedicationChangeKind.timings:
        final med = change.medicationUuid == null ? null : await _medByUuid(change.medicationUuid!);
        if (med == null || p.timings.isEmpty) return (outcome: ChangeOutcome.missing, notice: null);
        if (_localWins(med, change)) return (outcome: ChangeOutcome.conflict, notice: null);
        final old = await medications.schedulesFor(med.id);
        final before = [
          for (final s in old)
            {
              'id': int.parse(s.id),
              'minute': s.timing.minuteOfDay.minutes,
              'start_ms': s.startDate.millisecondsSinceEpoch,
              'duration_days': s.durationDays,
            },
        ];
        final start = p.startDate ?? _today;
        await _saves.replaceDoses(
          med.id,
          add: [for (final t in p.timings) (timing: t, startDate: start, durationDays: p.durationDays, days: _pattern(p))],
          stop: [for (final s in old) int.parse(s.id)],
        );
        final added = await medications.schedulesFor(med.id);
        return (
          outcome: ChangeOutcome.applied,
          notice: _notice(change, medicationId: med.id, detail: timesLine(p.timings), previous: {
            'stopped': before,
            'added_ids': [for (final s in added) int.parse(s.id)],
          }),
        );
      case MedicationChangeKind.photo:
        final outcome = await _applyPhoto(change);
        final med = change.medicationUuid == null ? null : await _medByUuid(change.medicationUuid!);
        return (outcome: outcome, notice: outcome == ChangeOutcome.applied ? _notice(change, medicationId: med?.id) : null);
      case MedicationChangeKind.bought:
        // ٠٠٣١: بيشيل العلامة وبس. **المخزون ما بيتلمسش** — مفيش كمية
        // نخمّنها؛ لو متتبّع، المريض بيسجّل العلبة من «اشتريت علبة جديدة».
        final med = change.medicationUuid == null ? null : await _medByUuid(change.medicationUuid!);
        if (med == null) return (outcome: ChangeOutcome.missing, notice: null);
        await NotBoughtRepository(db, clock: clock).markBought(med.id);
        return (outcome: ChangeOutcome.applied, notice: _notice(change, medicationId: med.id, previous: {'not_bought': med.notBoughtAt != null}));
      case MedicationChangeKind.vital:
        final kind = VitalKind.fromStored(p.vitalKind);
        final value = p.value;
        if (kind == null || value == null) return (outcome: ChangeOutcome.missing, notice: null);
        await VitalsRepository(db).add(
          patientId,
          VitalEntry(kind: kind, value: value, value2: p.value2, pulse: p.pulse),
          measuredAt: p.measuredAt ?? clock(),
        );
        return (outcome: ChangeOutcome.applied, notice: _notice(change, detail: kind.label));
      case MedicationChangeKind.pharmacy:
        final prefs = PreferencesRepository(db);
        final before = await prefs.pharmacy();
        await prefs.setPharmacy(name: p.pharmacyName, whatsapp: p.pharmacyWhatsapp, call: p.pharmacyCall ?? '', clearCall: p.pharmacyCall == null);
        return (
          outcome: ChangeOutcome.applied,
          notice: _notice(change, previous: {'pharmacy_name': before.name, 'pharmacy_whatsapp': before.whatsapp, 'pharmacy_call': before.call}),
        );
      case MedicationChangeKind.remove:
      case MedicationChangeKind.resume:
      case MedicationChangeKind.stop:
      case MedicationChangeKind.amount:
        final med = change.medicationUuid == null ? null : await _medByUuid(change.medicationUuid!);
        if (med == null) return (outcome: ChangeOutcome.missing, notice: null);
        if (_localWins(med, change)) return (outcome: ChangeOutcome.conflict, notice: null);
        switch (change.kind) {
          case MedicationChangeKind.stop:
            if (med.stoppedAt == null) await _saves.stop(med.id);
            return (outcome: ChangeOutcome.applied, notice: _notice(change, medicationId: med.id, previous: {'was_stopped': med.stoppedAt != null}));
          case MedicationChangeKind.resume:
            if (med.stoppedAt != null) await _saves.resume(med.id);
            return (outcome: ChangeOutcome.applied, notice: _notice(change, medicationId: med.id, previous: {'was_stopped': med.stoppedAt != null}));
          case MedicationChangeKind.remove:
            final store = photoStore;
            if (store != null) {
              await _saves.remove(med.id, MedPhotos(db, store, prepare: preparePhoto));
            } else {
              await _saves.removePlain(med.id);
            }
            return (outcome: ChangeOutcome.applied, notice: _notice(change, medicationId: med.id));
          default:
            await _saves.updateAmount(med.id, change.payload.amountLabel?.trim() ?? '');
            return (
              outcome: ChangeOutcome.applied,
              notice: _notice(change, medicationId: med.id, detail: change.payload.amountLabel?.trim(), previous: {'amount': med.amountLabel, 'amount_unknown': med.amountUnknown}),
            );
        }
    }
  }

  bool _localWins(MedicationRow row, MedicationChange change) {
    final wins = localEditWins(
      localUpdatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs),
      changeCreatedAt: change.createdAt,
    );
    if (wins) diag('MedChange: تعارض — الأب عدّل ${row.name} بعد اقتراح الممرض، التعديل المحلي كسب');
    return wins;
  }

  Future<void> _refreshAppointments() async {
    try {
      await AppointmentScheduler(db: db, patientId: patientId, sink: scheduler.sink).refresh(now: clock());
    } catch (error) {
      diag('MedChange: إشعارات الميعاد ما اتجدولتش — التذكيرات مش متأثرة ($error)');
    }
  }

  /// **«تراجع»** — بيرجّع بنفس السكّة، وبيعلّم الصف في السحابة `reverted`.
  /// true = اترجع. برّه الـ٢٤ ساعة أو نوع من غير رجوع = false ومفيش لمس.
  Future<bool> undo(ChangeNotice notice) async {
    final now = clock();
    if (!notice.canUndoAt(now)) return false;
    final prev = notice.previous;
    final medId = notice.medicationId;
    try {
      switch (notice.kind!) {
        case MedicationChangeKind.add:
          if (medId == null) return false;
          final store = photoStore;
          if (store != null) {
            await _saves.remove(medId, MedPhotos(db, store, prepare: preparePhoto));
          } else {
            await _saves.removePlain(medId);
          }
        case MedicationChangeKind.remove:
          if (medId == null) return false;
          await _saves.unremove(medId);
        case MedicationChangeKind.stop:
          if (medId == null) return false;
          if (prev['was_stopped'] != true) await _saves.resume(medId);
        case MedicationChangeKind.resume:
          if (medId == null) return false;
          if (prev['was_stopped'] == true) await _saves.stop(medId);
        case MedicationChangeKind.amount:
          if (medId == null) return false;
          final old = prev['amount'] as String?;
          if (prev['amount_unknown'] == true) {
            await medications.updateAmount(medId, null);
            await scheduler.rescheduleAll(now: now);
          } else {
            await _saves.updateAmount(medId, old ?? '');
          }
        case MedicationChangeKind.timings:
          if (medId == null) return false;
          final stopped = (prev['stopped'] as List?)?.cast<Map>() ?? const [];
          final addedIds = (prev['added_ids'] as List?)?.cast<num>().map((n) => n.toInt()).toList() ?? const [];
          await _saves.replaceDoses(
            medId,
            add: [
              for (final s in stopped)
                (
                  timing: FixedTiming(MinuteOfDay((s['minute'] as num).toInt())),
                  startDate: DateTime.fromMillisecondsSinceEpoch((s['start_ms'] as num).toInt()),
                  durationDays: (s['duration_days'] as num?)?.toInt(),
                  days: DayPattern.everyDay,
                ),
            ],
            stop: addedIds,
          );
        case MedicationChangeKind.restock:
          if (medId == null) return false;
          final added = (prev['quantity_added'] as num?)?.toDouble() ?? 0;
          final stock = StockRepository(db);
          final row = await stock.rowFor(medId);
          if (row != null) await stock.setQuantity(medId, row.quantity - added);
        case MedicationChangeKind.stockSet:
          if (medId == null) return false;
          final stock = StockRepository(db);
          if (prev['had_row'] == true) {
            await stock.setQuantity(medId, (prev['quantity'] as num?)?.toDouble() ?? 0, warnDays: (prev['warn_days'] as num?)?.toInt());
          } else {
            await stock.setQuantity(medId, 0);
          }
        case MedicationChangeKind.bought:
          if (medId == null) return false;
          if (prev['not_bought'] == true) await NotBoughtRepository(db, clock: clock).markNotBought(medId);
        case MedicationChangeKind.record:
        case MedicationChangeKind.appointment:
          final id = notice.recordId;
          if (id == null) return false;
          await RecordsRepository(db).delete(id, now: now);
          await _refreshAppointments();
        case MedicationChangeKind.pharmacy:
          await PreferencesRepository(db).setPharmacy(
            name: prev['pharmacy_name'] as String?,
            whatsapp: prev['pharmacy_whatsapp'] as String?,
            call: (prev['pharmacy_call'] as String?) ?? '',
            clearCall: prev['pharmacy_call'] == null,
          );
        case MedicationChangeKind.photo:
        case MedicationChangeKind.vital:
          return false;
      }
    } catch (error) {
      diag('MedChange: «تراجع» وقع ($error)');
      return false;
    }
    await dismiss(notice.uuid);
    try {
      await remote.markReverted(notice.uuid);
    } catch (error) {
      diag('MedChange: تعليم «اترجع» ${notice.uuid} ما وصلش ($error)');
    }
    diag('MedChange: تراجع ${notice.kind!.stored}');
    return true;
  }

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
