import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack, kDebugMode;
import 'package:flutter/widgets.dart';

import '../../core/diagnostics.dart';
import '../../data/services/reminder_sink.dart';
import 'caregiver_appointment_notices.dart';

import '../../data/care/caregiver_remote.dart';

/// كل قد إيه بيسأل السحابة وتبويب بيانات ظاهر قدامه.
///
/// الشاشة دي بتتفرّج على موبايل تاني — لو ما بتحدّثش لوحدها، الابن بيبص
/// عليها ويشوف بيانات قديمة من غير ما حاجة تقوله (3fef3f4). البديل الصح على
/// المدى الطويل اشتراك Realtime **مكان** السؤال ده، مش جنبه.
const Duration refreshEvery = Duration(seconds: 10);

/// صورة الابن الواحدة (D5.2): سحبة واحدة لكل تحديث، والتبويبين («متابعة»
/// و«الملف الصحي») بيقروا منها. من غيرها كل تبويب كان هيسحب لوحده —
/// ضعف النداءات، وصورتين ممكن يختلفوا.
///
/// السؤال الدوري هنا بس: شغّال ⇔ [active] (تبويب بيانات ظاهر) **و**التطبيق
/// في المقدمة. في الخلفية أو على «الإعدادات» مقفول.
class CaregiverSnapshotHolder extends ChangeNotifier with WidgetsBindingObserver {
  CaregiverSnapshotHolder(this.remote, {this.onNotLinked, this.sink}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final CaregiverRemote remote;

  /// جهاز الإشعارات بتاع **موبايل الابن** — null = مفيش جدولة (اختبارات،
  /// أو شاشة مفتوحة من غير خدمات).
  ///
  /// مواعيد الأب بتتجدول محلياً هنا لأن مفيش دفع من السيرفر لسه. الجدولة
  /// بتحصل **بعد** ما الصورة توصل، في `try/catch` بتاعها: إشعار ميعاد ما
  /// اتجدولش ما ينفعش يمنع الشاشة من إنها تتعرض.
  final ReminderSink? sink;

  /// السحابة قالت «مفيش مريض مربوط» → الجذر يرجّع لشاشة البداية. null =
  /// الجملة بتتقال على الشاشة (الطريق القديم من شاشة الربط).
  final VoidCallback? onNotLinked;

  CaregiverSnapshot? snapshot;

  /// ٠٠٢٦: كل المرضى المربوط بيهم — أكتر من واحد يعني الترويسة فيها مبدّل.
  /// فاضية لو السحابة مش بتعرف تجاوب ([MultiPatientRemote] مش متنفّذ).
  List<CaregiverPatient> patients = const [];

  /// المريض المختار — null = الأحدث ربطاً (السلوك القديم).
  String? selectedPatientUuid;

  /// بيغيّر المريض وبيسحب على طول. الشاشة بتتبني من جديد على صورته هو.
  Future<void> selectPatient(String uuid) async {
    if (uuid == selectedPatientUuid) return;
    selectedPatientUuid = uuid;
    snapshot = null;
    await refresh();
  }

  String? error;
  bool loading = true;

  bool _active = false;
  Timer? _timer;
  bool _disposed = false;

  bool get active => _active;

  /// null في الاختبارات قبل أي حدث دورة حياة — بيتعامل كمقدمة.
  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// تبويب بيانات بقى ظاهر (أو اختفى). الظهور بيسأل على طول — صورة طازة، مش
  /// بعد عشر ثواني.
  void setActive(bool active) {
    final becameActive = active && !_active;
    _active = active;
    _syncTimer();
    if (becameActive) refresh();
  }

  void _syncTimer() {
    final shouldRun = _active && _foreground && !_disposed;
    if (shouldRun && _timer == null) {
      _timer = Timer.periodic(refreshEvery, (_) => refresh());
    } else if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_active) refresh();
        _syncTimer();
      case AppLifecycleState.paused || AppLifecycleState.inactive:
        _timer?.cancel();
        _timer = null;
      default:
        break;
    }
  }

  /// **بتتنده بعد كل سحبة، وبتبلع أي عطل.**
  ///
  /// نفس قاعدة موبايل الأب: سكّة المواعيد ما تقدرش توقّع اللي قبلها.
  Future<void> _scheduleAppointments() async {
    final device = sink;
    final data = snapshot;
    if (device == null || data == null) return;
    try {
      await syncCaregiverAppointments(data, sink: device, now: DateTime.now());
    } catch (error, stack) {
      diag('Care: جدولة مواعيد الأب على موبايل الابن فشلت: $error\n$stack');
    }
  }

  /// مع [MultiPatientRemote]: القايمة الأول، وبعدين صورة المختار (أو
  /// الأحدث لو المختار اتشال). من غيرها: السلوك القديم بالظبط.
  Future<CaregiverSnapshot?> _fetch() async {
    final multi = remote;
    if (multi is! MultiPatientRemote) return remote.snapshot();
    final all = await (multi as MultiPatientRemote).linkedPatients();
    patients = all;
    if (all.isEmpty) return null;
    final chosen = all.any((p) => p.uuid == selectedPatientUuid) ? selectedPatientUuid! : all.first.uuid;
    selectedPatientUuid = chosen;
    return (multi as MultiPatientRemote).snapshotFor(chosen);
  }

  Future<void> refresh() async {
    if (_disposed) return;
    loading = snapshot == null;
    error = null;
    notifyListeners();
    try {
      final next = await _fetch();
      if (_disposed) return;
      if (next == null && onNotLinked != null) {
        onNotLinked!();
        return;
      }
      snapshot = next ?? snapshot;
      loading = false;
      if (next == null) error = 'مفيش ربط شغّال دلوقتي.';
      await _scheduleAppointments();
    } on CareCircleException catch (e) {
      // البيانات القديمة بتفضل معروضة — الجملة فوقها بتقول إنها قديمة
      if (_disposed) return;
      loading = false;
      error = e.message;
    } catch (e, st) {
      // أي حاجة تانية: الجملة للمستخدم زي ما هي، والسبب الحقيقي في اللوج.
      // (الاستعلامات نفسها بتطبع تفاصيلها في `SupabaseCaregiverRemote`؛
      // السطر ده بيمسك اللي بيقع برّه — تحويل صف، أو خطأ مش متوقع.)
      if (kDebugMode) {
        debugPrint('Care: تحديث شاشة الابن فشل — ${e.runtimeType}: $e');
        debugPrintStack(stackTrace: st, label: 'Care');
      }
      if (_disposed) return;
      loading = false;
      error = 'مقدرناش نكمّل. جرّب تاني.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
