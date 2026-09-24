import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/health/health_watcher.dart';
import '../../domain/health/health_check.dart';
import '../../domain/health/health_report.dart';
import '../../domain/health/health_snapshot.dart';

/// السطر الوحيد عن «مشكلة» اللي بيوصل شاشة المريض: **إذن التنبيهات مقفول**.
///
/// قاعدة المالك: المريض ما يشوفش مشكلة تقنية أبداً. ده مش تقني وفي إيده هو
/// بس — جملة واحدة وزرار بيفتح إعدادات النظام. من غير كود، من غير شرح،
/// ومفيش حاجة خالص لما الإذن مفتوح (أو مش معروف: الشك مش سبب نخوّفه).
///
/// بيتحدّث لوحده: من نتيجة الفحص عند الإطلاق، وبقراية حقيقية للإذن كل ما
/// التطبيق يرجع للمقدمة — عشان أول ما يفتح الإذن من الإعدادات ويرجع، السطر
/// يختفي من غير ما يقفل التطبيق.
class NotificationsOffLine extends StatefulWidget {
  const NotificationsOffLine({super.key});

  static const String line = 'التنبيهات مقفولة — افتحها عشان نفكّرك';
  static const String action = 'افتح الإعدادات';

  @override
  State<NotificationsOffLine> createState() => _NotificationsOffLineState();
}

class _NotificationsOffLineState extends State<NotificationsOffLine>
    with WidgetsBindingObserver {
  bool _off = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HealthWatcher.latest.addListener(_fromReport);
    _fromReport();
  }

  @override
  void dispose() {
    HealthWatcher.latest.removeListener(_fromReport);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fromDevice();
  }

  void _fromReport() {
    final HealthReport? report = HealthWatcher.latest.value;
    if (report == null) return;
    final off = report.findings.any(
      (f) => f.code == HealthCode.notificationPermission && f.patientVisible,
    );
    if (mounted && off != _off) setState(() => _off = off);
  }

  Future<void> _fromDevice() async {
    NotificationPermission state;
    try {
      state = await NotificationService.permissionState();
    } catch (_) {
      return;
    }
    // «مش معروف» ما بيغيّرش حاجة — الشك مش سبب لسطر
    final off = switch (state) {
      NotificationPermission.denied || NotificationPermission.provisional => true,
      NotificationPermission.granted => false,
      NotificationPermission.unknown => _off,
    };
    if (mounted && off != _off) setState(() => _off = off);
  }

  Future<void> _open() async {
    // أول مرة النظام بيسأل بنفسه؛ لو رفض قبل كده، الإعدادات هي الباب
    var granted = false;
    try {
      granted = await NotificationService.requestPermissions();
    } catch (_) {}
    if (granted) {
      await _fromDevice();
      return;
    }
    try {
      await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_off) return const SizedBox.shrink();
    // نفس شكل الكارت الذهبي بتاع «الآن»: حد جانبي ذهبي = «دي عايزاك دلوقتي»
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s12),
      child: Container(
        key: const ValueKey('notifications-off'),
        padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
        decoration: BoxDecoration(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
          border: const BorderDirectional(start: BorderSide(color: F.gold, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              NotificationsOffLine.line,
              style: TextStyle(
                fontSize: F.minBodySize,
                fontWeight: FontWeight.w700,
                color: F.ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: F.s8),
            FSecondaryButton(label: NotificationsOffLine.action, onPressed: _open),
          ],
        ),
      ),
    );
  }
}
