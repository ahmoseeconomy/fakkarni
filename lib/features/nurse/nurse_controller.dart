import 'package:flutter/foundation.dart';

import '../../app/app_scope.dart';
import '../../data/care/caregiver_remote.dart';
import '../../data/care/nurse_change_queue.dart';
import '../../domain/billing/family_plan.dart';
import '../../domain/care/medication_change.dart';
import '../care/caregiver_snapshot_holder.dart';

/// **اللي الممرض بيعمله، في مكان واحد** — التبويبات كلها بتنده هنا.
///
/// كل فعل بيروح للسحابة كطلب، وموبايل المريض هو اللي بيكتبه: التأكيد
/// نيابةً (٠٠٢٣)، والتغييرات (٠٠٢٤/٠٠٢٦/0035) — بتتطبّق عليه **لوحدها**،
/// من غير موافقة، وبنفس سكّة الكتابة عنده. النت واقع؟ التغيير بيتحفظ هنا
/// وبيتبعت لوحده ([NurseChangeQueue]) — والممرض بيشوف «هيوصل لموبايله أول
/// ما يفتح النت».
/// **ممنوع بالتصميم**: روتين المريض، إعداداته، اللي بيتابعوه، اشتراكه —
/// مفيش دالة هنا بتلمسهم، ومفيش واجهة سحابة ليهم أصلاً للممرض.
class NurseController extends ChangeNotifier {
  NurseController({required this.holder, required this.services, NurseChangeQueue? queue})
      : queue = queue ?? (services.medChanges == null ? null : NurseChangeQueue(services.medChanges!));

  final CaregiverSnapshotHolder holder;
  final AppServices services;
  final NurseChangeQueue? queue;

  final busy = <String>{};
  String? error;

  /// آخر جملة بتتقال بعد إرسال — «اتبعت لموبايله…» / «هيوصل لموبايل … أول ما
  /// يفتح النت».
  String? lastLine;

  /// اللي بعته ولسه ما اتطبّقش على موبايل المريض (من السحابة).
  List<MedicationChange> pending = const [];

  /// اللي لسه على الموبايل ده مستني النت.
  List<QueuedChange> queued = const [];
  String? _pendingFor;

  CaregiverSnapshot? get snapshot => holder.snapshot;

  /// **الكتابة مع الاشتراك بس** (٠٠٢٦، والسيرفر بيفرضها كمان). القراية
  /// شغّالة دايماً عشان يشوف «التنبيهات واقفة» ويجدّد.
  bool get writesAllowed {
    final sub = services.subscription;
    if (sub == null) return true;
    return sub.notice().kind != FamilyNoticeKind.ended;
  }

  bool get canConfirm => (snapshot?.patient.permissions.canConfirm ?? false) && writesAllowed;
  bool get canEdit => (snapshot?.patient.permissions.canEditMeds ?? false) && writesAllowed;

  Future<String?> myName() async {
    final uuid = snapshot?.patient.uuid;
    if (uuid == null) return null;
    try {
      return (await services.caregiverPreferences?.load(uuid))?.name;
    } catch (_) {
      return null;
    }
  }

  Future<void> confirm(CaregiverDoseEvent event) async {
    final data = snapshot;
    final proxy = services.proxy;
    if (data == null || proxy == null || busy.contains(event.uuid) || !canConfirm) return;
    busy.add(event.uuid);
    error = null;
    notifyListeners();
    try {
      await proxy.confirmOnBehalf(
        patientUuid: data.patient.uuid,
        doseEventUuid: event.uuid,
        actorName: await myName(),
      );
      await holder.refresh();
    } on CareCircleException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'مقدرناش نأكّد. جرّب تاني.';
    } finally {
      busy.remove(event.uuid);
      notifyListeners();
    }
  }

  /// بيبعت تغيير — أو بيحطّه في الطابور لو النت واقع. true = اتبعت أو اتحفظ.
  Future<bool> submit({
    required MedicationChangeKind kind,
    required MedicationChangePayload payload,
    String? medicationUuid,
    String? medicationName,
  }) async {
    final data = snapshot;
    final q = queue;
    if (data == null || q == null || !canEdit) return false;
    error = null;
    notifyListeners();
    final change = QueuedChange(
      uuid: NurseChangeQueue.newUuid(),
      patientUuid: data.patient.uuid,
      patientName: data.patient.name,
      kind: kind,
      payload: payload,
      medicationUuid: medicationUuid,
      medicationName: medicationName,
      actorName: await myName(),
    );
    final result = await q.submit(change);
    switch (result.outcome) {
      case SubmitOutcome.sent:
        lastLine = null;
        await loadPending(force: true);
        notifyListeners();
        return true;
      case SubmitOutcome.queued:
        lastLine = NurseChangeQueue.queuedLine(data.patient.name);
        queued = await q.pendingFor(data.patient.uuid);
        notifyListeners();
        return true;
      case SubmitOutcome.failed:
        error = result.error;
        notifyListeners();
        return false;
    }
  }

  /// بعد كل صورة جديدة / رجوع للمقدمة: الطابور بيتبعت، والمعلّق بيتقرا.
  Future<void> flushQueue() async {
    final q = queue;
    final data = snapshot;
    if (q == null) return;
    final sent = await q.flush();
    if (data != null) queued = await q.pendingFor(data.patient.uuid);
    if (queued.isEmpty) lastLine = null;
    if (sent > 0) await loadPending(force: true);
    notifyListeners();
  }

  Future<void> loadPending({bool force = false}) async {
    final data = snapshot;
    final remote = services.medChanges;
    if (data == null || remote == null) return;
    if (!force && _pendingFor == data.patient.uuid) return;
    _pendingFor = data.patient.uuid;
    try {
      pending = await remote.pendingFor(data.patient.uuid);
      notifyListeners();
    } catch (_) {}
  }

  /// «اتبعت لموبايله — ضاف دوا Concor»
  static String pendingLine(MedicationChange c) =>
      'اتبعت لموبايله — ${c.kind.verb} ${changeSubject(c)}. هيتطبّق أول ما يفتح التطبيق.';

  /// سطر اللي في الطابور: «هيوصل لموبايل الحاج أحمد أول ما يفتح النت — ضاف دوا Concor».
  String queuedLine(QueuedChange q) =>
      '${NurseChangeQueue.queuedLine(q.patientName)} — ${q.kind.verb} ${q.medicationName ?? q.payload.name ?? ''}'.trim();
}
