import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/health/health_collector.dart';
import '../../domain/health/health_check.dart';
import '../../domain/health/health_report.dart';
import '../link/sign_in_screen.dart';

/// «اطمن إن التذكير هيشتغل» — الشاشة اللي بتخلّي العطل الساكت مسموع.
///
/// **بتطمّن، مش بتخوّف.** كل سطر بيقول إيه اللي حاصل ومعناه إيه بالنسبة
/// له، ومعاه زرار واحد بيحلّها — أو جملة بتقول اللي بيحصل لما الحل مش في
/// إيده. مفيش أسماء دوال ولا أكواد على الشاشة.
///
/// والسطر الأخضر مهم قد الأحمر: شاشة عمرها ما بتقول «كله تمام» بتبقى
/// معناها الوحيد «فيه بايظ».
class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({this.isCaregiver = false, super.key});

  final bool isCaregiver;

  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> {
  HealthReport? _report;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_report == null) _run();
  }

  HealthCollector get _collector =>
      HealthCollector(AppScope.of(context), isCaregiver: widget.isCaregiver);

  Future<void> _run() async {
    final report = await _collector.run();
    if (mounted) setState(() => _report = report);
  }

  Future<void> _apply(HealthFix fix) async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    try {
      switch (fix) {
        case HealthFix.rescheduleNow:
          await services.scheduler.rescheduleAll();
          await _collector.rememberTimezone();
        case HealthFix.syncNow:
          services.sync?.onAppForeground();
        case HealthFix.openNotificationSettings:
          if (!await NotificationService.requestPermissions()) {
            await _openSystemSettings();
          }
        case HealthFix.openExactAlarmSettings:
          await NotificationService.requestExactAlarmPermission();
        case HealthFix.linkCaregiver:
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SignInScreen(
              auth: services.auth,
              caregiver: services.caregiver,
              push: services.push,
            ),
          ));
        case HealthFix.none:
          break;
      }
    } catch (_) {
      // إصلاح فشل مش سبب لشاشة بايظة — الفحص التاني هيقول الحقيقة
    }
    if (mounted) setState(() => _busy = false);
    await _run();
  }

  Future<void> _openSystemSettings() async {
    try {
      await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('اطمن إن التذكير هيشتغل')),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap,
                  F.s30 + MediaQuery.of(context).padding.bottom),
              children: [
                if (report.allWell) const _AllWellCard(),
                for (final finding in report.findings)
                  _FindingCard(
                    finding: finding,
                    busy: _busy,
                    onFix: () => _apply(finding.fix),
                  ),
                const SizedBox(height: F.gap),
                FSecondaryButton(
                  label: 'افحص تاني',
                  onPressed: _busy ? null : _run,
                ),
              ],
            ),
    );
  }
}

/// غياب الإنذار لازم يتشاف.
class _AllWellCard extends StatelessWidget {
  const _AllWellCard();

  @override
  Widget build(BuildContext context) => FCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 32, color: F.greenDeep),
            const SizedBox(width: F.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'كله تمام',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.subtitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.s4),
                  Text(
                    'التذكير هيرن في معاده، واللي بيتابعك بيشوف جرعاتك أول بأول.',
                    style: TextStyle(
                        fontSize: F.minBodySize, color: F.mutedDark, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.finding,
    required this.busy,
    required this.onFix,
  });

  final HealthFinding finding;
  final bool busy;
  final VoidCallback onFix;

  /// **ذهبي للمكسور، مش أحمر.** الأحمر للطوارئ وبس، والراجل اللي بيقرا
  /// السطر ده مش في خطر — فيه حاجة محتاجة انتباهه دلوقتي، وده بالظبط
  /// معنى الذهبي في التطبيق كله.
  @override
  Widget build(BuildContext context) {
    final broken = finding.isBroken;
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s12),
      child: FCard(
        tone: broken ? FCardTone.attention : FCardTone.plain,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              finding.title,
              style: TextStyle(
                fontSize: F.subtitleSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: F.s4),
            Text(
              finding.why,
              style: TextStyle(
                  fontSize: F.minBodySize, color: F.mutedDark, height: 1.6),
            ),
            if (finding.fix != HealthFix.none) ...[
              const SizedBox(height: F.s12),
              FSecondaryButton(
                label: _fixLabel(finding.fix),
                onPressed: busy ? null : onFix,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fixLabel(HealthFix fix) => switch (fix) {
        HealthFix.rescheduleNow => 'جهّز التذكيرات دلوقتي',
        HealthFix.syncNow => 'ابعتها دلوقتي',
        HealthFix.openNotificationSettings => 'افتح إعدادات التنبيهات',
        HealthFix.openExactAlarmSettings => 'اسمح بالتنبيه في معاده',
        HealthFix.linkCaregiver => 'اربط حد يتابعك',
        HealthFix.none => '',
      };
}
