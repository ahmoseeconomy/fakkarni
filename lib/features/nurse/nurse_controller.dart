import 'package:flutter/foundation.dart';

import '../../app/app_scope.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/billing/family_plan.dart';
import '../../domain/care/medication_change.dart';
import '../care/caregiver_snapshot_holder.dart';

/// **اللي الممرض بيعمله، في مكان واحد** — التبويبات التلاتة بتنده هنا.
///
/// كل فعل بيروح للسحابة كطلب، وموبايل المريض هو اللي بيكتبه: التأكيد
/// نيابةً (٠٠٢٣)، والتغييرات المعلّقة للدوا والورقة والميعاد (٠٠٢٤/٠٠٢٦).
/// **ممنوع بالتصميم**: روتين المريض، إعداداته، اللي بيتابعوه، اشتراكه —
/// مفيش دالة هنا بتلمسهم، ومفيش واجهة سحابة ليهم أصلاً للممرض.
class NurseController extends ChangeNotifier {
  NurseController({required this.holder, required this.services});

  final CaregiverSnapshotHolder holder;
  final AppServices services;

  final busy = <String>{};
  String? error;

  /// اللي بعته ولسه ما اتطبّقش على موبايل المريض.
  List<MedicationChange> pending = const [];
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

  /// بيبعت تغيير معلّق. true = اتبعت.
  Future<bool> submit({
    required MedicationChangeKind kind,
    required MedicationChangePayload payload,
    String? medicationUuid,
    String? medicationName,
  }) async {
    final data = snapshot;
    final remote = services.medChanges;
    if (data == null || remote == null || !canEdit) return false;
    error = null;
    notifyListeners();
    try {
      await remote.submit(
        patientUuid: data.patient.uuid,
        kind: kind,
        payload: payload,
        medicationUuid: medicationUuid,
        medicationName: medicationName,
        actorName: await myName(),
      );
      await loadPending(force: true);
      return true;
    } on CareCircleException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'مقدرناش نبعت. جرّب تاني.';
    }
    notifyListeners();
    return false;
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
}
