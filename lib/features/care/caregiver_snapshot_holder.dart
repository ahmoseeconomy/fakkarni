import 'dart:async';

import 'package:flutter/widgets.dart';

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
  CaregiverSnapshotHolder(this.remote, {this.onNotLinked}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final CaregiverRemote remote;

  /// السحابة قالت «مفيش مريض مربوط» → الجذر يرجّع لشاشة البداية. null =
  /// الجملة بتتقال على الشاشة (الطريق القديم من شاشة الربط).
  final VoidCallback? onNotLinked;

  CaregiverSnapshot? snapshot;
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

  Future<void> refresh() async {
    if (_disposed) return;
    loading = snapshot == null;
    error = null;
    notifyListeners();
    try {
      final next = await remote.snapshot();
      if (_disposed) return;
      if (next == null && onNotLinked != null) {
        onNotLinked!();
        return;
      }
      snapshot = next ?? snapshot;
      loading = false;
      if (next == null) error = 'مفيش ربط شغّال دلوقتي.';
    } on CareCircleException catch (e) {
      // البيانات القديمة بتفضل معروضة — الجملة فوقها بتقول إنها قديمة
      if (_disposed) return;
      loading = false;
      error = e.message;
    } catch (_) {
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
