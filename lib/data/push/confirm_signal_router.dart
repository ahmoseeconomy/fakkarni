import 'dart:async';

import '../../core/diagnostics.dart';
import 'confirm_signals.dart';

/// بيوصّل إشارة «اتأكّدت» لمكانها على الموبايل ده:
/// - **موبايل المريض**: سحبة من الدايرة — التأكيد نيابةً بيتكتب `taken` وبيلغي
///   الجرعة وسلّمها وإعاداتها (`ProxyConfirmationPuller`، القاعدة ٥).
/// - **موبايل الممرض**: التذكير والتأجيل بتوع الجرعة دي بيتلغوا حالاً.
///
/// **مرة واحدة لكل حدث** ([seen]): نفس الإشارة ممكن توصل من المقدمة والخلفية.
/// وكل حاجة هنا مجاملة — الفشل بيتسجّل والمقارنة الجاية بتكمّل.
class ConfirmSignalRouter {
  ConfirmSignalRouter({required this.onPatientSide, required this.onNurseSide});

  final Future<void> Function() onPatientSide;
  final Future<int> Function(ConfirmSignal signal) onNurseSide;

  final seen = <String>{};
  StreamSubscription<Map<String, dynamic>>? _sub;

  void listen(PushMessages? messages) {
    if (!confirmPushEnabled || messages == null) return;
    _sub = messages.data.listen((data) => unawaited(handle(data)));
  }

  Future<void> handle(Map<String, dynamic> data) async {
    final signal = ConfirmSignal.fromData(data);
    if (signal == null) return;
    final key = '${signal.doseEventUuid}|${signal.source.name}';
    if (!seen.add(key)) return;
    try {
      final cancelled = await onNurseSide(signal);
      if (signal.source == ConfirmSource.proxy) await onPatientSide();
      diag('Push: إشارة تأكيد ${signal.source.name} — تذكيرات ممرض اتلغت: $cancelled');
    } catch (error) {
      diag('Push: إشارة التأكيد وقعت ($error) — المقارنة الجاية بتكمّل');
    }
  }

  Future<void> dispose() async => _sub?.cancel();
}
