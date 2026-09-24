import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../core/notifications/notification_service.dart';
import '../../domain/health/health_check.dart';
import '../../domain/health/health_report.dart';
import 'health_collector.dart';
import 'health_heartbeat.dart';

/// بيشغّل الفحص، وبيرفع النبضة، وبينبّه **مرة واحدة في اليوم لكل كود**.
///
/// **مجاملة بالكامل.** بيتنده بعد ما كل وعد اتنفّذ — تسجيل الجرعة وإلغاء
/// السلّم والجدولة — وعمره ما بيتستنى قبل واحد منهم. أي فشل جواه بيتسجّل
/// وبيتساب.
class HealthWatcher {
  HealthWatcher({required this.collector, this.heartbeat});

  final HealthCollector collector;
  final HealthHeartbeat? heartbeat;

  /// آخر نتيجة — «يومك» بتسمع لها وبتعرض شريط لما يبقى فيه مكسور.
  static final ValueNotifier<HealthReport?> latest =
      ValueNotifier<HealthReport?>(null);

  static const _alertedKey = 'health.alertedOn';

  /// رقم إشعار خارج كل النطاقات المحجوزة — مش بياخد خانة من أي تذكير.
  static const alertNotificationId = 60000001;

  /// حمولة إشعار السلامة — الجذر بيعرفها وبيفتح «اطمن إن التذكير هيشتغل»
  /// عليها، من الإطلاق البارد كمان. مش حمولة جرعة: `decodePayload` بترجّع
  /// null عليها عن قصد.
  static const tapPayload = '{"v":1,"open":"health"}';

  Future<void> run() async {
    try {
      final snapshot = await collector.collect();
      final report = runHealthChecks(snapshot);
      latest.value = report;

      await heartbeat?.report(report, snapshot);
      await _alertIfNew(report, snapshot.now);
    } catch (error) {
      diag('Health: الفحص وقع ($error)');
    }
  }

  /// كود مكسور **جديد** بس هو اللي بينبّه، ومرة في اليوم لكل كود —
  /// **ومن اللي في إيده يصلّحه بس** ([HealthFinding.notifies]).
  ///
  /// عطل مستمر بيفضل باين على الشاشة وفي الشريط؛ تنبيه بيتكرر كل فتحة
  /// بيتعلّم المريض إنه يعدّي على تنبيهاتنا — وهي نفس القناة اللي
  /// الجرعة الفايتة بتيجي منها. ومشكلة المزامنة بالذات ما بتنبّهش أبداً:
  /// الدوسة كانت بتفتح على ولا حاجة، والراجل ما يقدرش يصلّح السيرفر.
  Future<void> _alertIfNew(HealthReport report, DateTime now) async {
    final broken = report.broken.where((f) => f.notifies).toList();
    if (broken.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final today = '${now.year}-${now.month}-${now.day}';
    final alerted = prefs.getStringList(_alertedKey) ?? const [];

    final fresh = [
      for (final finding in broken)
        if (!alerted.contains('${finding.code.name}|$today')) finding,
    ];
    if (fresh.isEmpty) return;

    // إشعار واحد مهما كان عدد الجديد — مش تنبيه لكل كود.
    await NotificationService.showNow(
      id: alertNotificationId,
      title: 'فيه حاجة ممكن تمنع التذكير',
      body: fresh.first.title,
      payload: tapPayload,
    );

    await prefs.setStringList(_alertedKey, [
      for (final finding in broken) '${finding.code.name}|$today',
    ]);
  }

  /// أكواد النهارده اللي اتنبّه عليها — للاختبار.
  @visibleForTesting
  static String alertKey(HealthCode code, DateTime day) =>
      '${code.name}|${day.year}-${day.month}-${day.day}';
}
