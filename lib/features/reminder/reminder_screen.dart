import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/scheduling/dose_schedule.dart';

/// شاشة التذكير — اللي بتفتح لما المريض يدوس على الإشعار.
///
/// حاجة واحدة بس مطلوبة منه هنا: يقول خدها ولا لأ. عشان كده الشاشة غامقة،
/// الدوا في النص، وزرار «أخدته» أكبر حاجة فيها. مفيش شريط يوم ولا قايمة —
/// «يومك» موجودة وراها لما يخلص.
class ReminderScreen extends StatefulWidget {
  const ReminderScreen({
    required this.routineDay,
    required this.scheduleIds,
    this.now,
    super.key,
  });

  /// يوم الروتين اللي التذكير بتاعه — من الـpayload، مش من الساعة دلوقتي.
  final DateTime routineDay;

  /// الجداول اللي رنّ عشانها — جرعة أو أكتر في نفس الدقيقة.
  final List<String> scheduleIds;

  /// للاختبارات — الشاشة بتستخدم دلوقتي الحقيقي في التطبيق.
  final DateTime? now;

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  Stream<List<DoseEventView>>? _events;
  StreamSubscription<List<DoseSchedule>>? _schedulesSub;
  Map<String, DoseSchedule> _schedules = const {};
  bool _busy = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_events != null) return;

    final services = AppScope.of(context);
    final ids = widget.scheduleIds.toSet();
    _events = services.events.watchDay(widget.routineDay).map(
          (events) => [
            for (final e in events)
              if (ids.contains(e.doseScheduleId.toString())) e,
          ],
        );
    _schedulesSub = services.medications
        .watchActiveSchedules(services.patientId)
        .listen((schedules) {
      if (!mounted) return;
      setState(() => _schedules = {for (final s in schedules) s.id: s});
    });
  }

  @override
  void dispose() {
    _schedulesSub?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function(AppServices) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    try {
      await action(services);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // ما نطلعش من شاشة الجذر لو الشاشة دي اتفتحت لوحدها في اختبار.
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _taken(List<DoseEventView> doses) => _act((services) async {
        for (final dose in doses) {
          await services.events.markTaken(dose.doseScheduleId, widget.routineDay);
        }
        // فوراً وقبل أي حاجة تانية: التأكيد بيلغي التذكير في نفس اللحظة.
        await services.scheduler.afterConfirmation(doses.first.scheduledAt);
      });

  Future<void> _skipped(List<DoseEventView> doses) => _act((services) async {
        for (final dose in doses) {
          await services.events.markSkipped(dose.doseScheduleId, widget.routineDay);
        }
        await services.scheduler.afterConfirmation(doses.first.scheduledAt);
      });

  Future<void> _snooze(List<DoseEventView> doses) => _act((services) async {
        await services.scheduler.snooze(
          originalAt: doses.first.scheduledAt,
          body: reminderBodyFor([
            for (final d in doses) (name: d.medicationName, amount: d.amountLabel),
          ]),
          payload: encodePayloadFor(widget.routineDay, widget.scheduleIds),
          now: _now,
        );
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: F.greenDeep,
      body: SafeArea(
        child: StreamBuilder<List<DoseEventView>>(
          stream: _events,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: F.gold));
            }
            final doses = snapshot.data!;
            if (doses.isEmpty) return const _GonePanel();

            final pending = [for (final d in doses) if (!d.isDone) d];
            final at = doses.first.scheduledAt;

            return ListView(
              padding: const EdgeInsets.all(F.gap),
              children: [
                const SizedBox(height: F.gap),
                // الذهبي هنا في مكانه: ده تذكير.
                const Text(
                  'تذكير',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    fontWeight: FontWeight.w700,
                    color: F.gold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  pending.isEmpty ? 'خدته خلاص' : _headline(at),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: F.questionSize,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: F.gap),
                _DoseCard(doses: doses, ruleLabelFor: _ruleLabelFor),
                const SizedBox(height: F.gap),
                if (pending.isEmpty)
                  _DoneActions(onBack: () => Navigator.of(context).maybePop())
                else
                  _PendingActions(
                    enabled: !_busy,
                    onTaken: () => _taken(pending),
                    onSnooze: () => _snooze(pending),
                    onSkipped: () => _skipped(pending),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// «وقت الدوا» لو لسه، «فات معاده بـ١٥ دقيقة» لو اتأخر — من غير لوم.
  String _headline(DateTime at) {
    final diff = at.difference(_now);
    if (diff.abs().inMinutes < 1 || !diff.isNegative) return 'وقت الدوا';
    return arabicCountdown(diff);
  }

  String? _ruleLabelFor(int doseScheduleId) =>
      _schedules[doseScheduleId.toString()]?.ruleLabel;
}

/// كارت الدوا — أبيض على الغامق، الاسم أكبر حاجة فيه.
class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.doses, required this.ruleLabelFor});

  final List<DoseEventView> doses;
  final String? Function(int doseScheduleId) ruleLabelFor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(F.radius + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, dose) in doses.indexed) ...[
            if (i > 0) const Divider(color: F.line, height: F.gap * 2),
            _DoseRow(dose: dose, ruleLabel: ruleLabelFor(dose.doseScheduleId)),
          ],
        ],
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose, required this.ruleLabel});

  final DoseEventView dose;
  final String? ruleLabel;

  @override
  Widget build(BuildContext context) {
    final details = [
      ?dose.amountLabel,
      ?ruleLabel,
      arabicTime(dose.scheduledAt),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dose.medicationName,
                style: const TextStyle(
                  fontSize: F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                  height: 1.3,
                ),
              ),
            ),
            if (dose.isDone) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check, color: F.green, size: 28),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          dose.isDone && dose.actedAt != null
              ? 'أخدته ${arabicTime(dose.actedAt!)}'
              : details,
          style: const TextStyle(
            fontSize: F.minTextSize,
            color: F.muted,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// الأزرار الثلاثة: أساسي ذهبي، تأجيل مرسوم، وتخطّي نصّي.
///
/// المخطط عنده أربع تحكّمات (تناول، تأجيل، تخطّي، لا أذكر) — «لا أذكر» مش
/// موجود عن قصد: حد الشاشة إجراءين أساسيين، ولو مش فاكر فده هو نفسه
/// «مش هاخده دلوقتي» مع واحد يسأله.
class _PendingActions extends StatelessWidget {
  const _PendingActions({
    required this.enabled,
    required this.onTaken,
    required this.onSnooze,
    required this.onSkipped,
  });

  final bool enabled;
  final VoidCallback onTaken;
  final VoidCallback onSnooze;
  final VoidCallback onSkipped;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: F.primaryButtonHeight,
          child: FilledButton(
            onPressed: enabled ? onTaken : null,
            style: FilledButton.styleFrom(
              backgroundColor: F.gold,
              foregroundColor: F.ink,
              textStyle: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('أخدته'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: F.primaryButtonHeight,
          child: OutlinedButton(
            onPressed: enabled ? onSnooze : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: F.ivory.withValues(alpha: 0.6), width: 1.5),
              textStyle: const TextStyle(
                fontSize: F.minBodySize,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('فكّرني بعد ربع ساعة'),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: F.minTapTarget,
          child: TextButton(
            onPressed: enabled ? onSkipped : null,
            child: Text(
              'مش هاخده دلوقتي',
              style: TextStyle(
                fontSize: F.minTextSize,
                color: F.ivory.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// الجرعة دي خلاص اتقفلت — من «يومك» أو من دوسة قبل كده.
class _DoneActions extends StatelessWidget {
  const _DoneActions({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تسلم. مفيش حاجة مطلوبة منك دلوقتي.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: F.minBodySize,
            color: F.ivory.withValues(alpha: 0.85),
            height: 1.6,
          ),
        ),
        const SizedBox(height: F.gap),
        SizedBox(
          height: F.primaryButtonHeight,
          child: FilledButton(
            onPressed: onBack,
            style: FilledButton.styleFrom(
              backgroundColor: F.ivory,
              foregroundColor: F.ink,
            ),
            child: const Text('ارجع ليومك'),
          ),
        ),
      ],
    );
  }
}

/// الإشعار بتاع جرعة مبقتش موجودة — دوا اتوقف، أو إشعار قديم.
class _GonePanel extends StatelessWidget {
  const _GonePanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(F.gap),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'الجرعة دي مبقتش في يومك.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: F.questionSize,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: F.gap),
          SizedBox(
            height: F.primaryButtonHeight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(
                backgroundColor: F.ivory,
                foregroundColor: F.ink,
              ),
              child: const Text('ارجع ليومك'),
            ),
          ),
        ],
      ),
    );
  }
}
