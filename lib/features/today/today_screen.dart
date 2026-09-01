import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../medication/add_medication_screen.dart';
import '../routine/edit_routine_screen.dart';
import 'widgets/day_rail.dart';
import 'widgets/next_dose_card.dart';

/// «يومك» — الجرعة الجاية فوق، وباقي اليوم تحتها على شريط زمني.
class TodayScreen extends StatefulWidget {
  const TodayScreen({required this.routine, this.now, super.key});

  final DayRoutine routine;

  /// للاختبارات — الشاشة بتستخدم دلوقتي الحقيقي في التطبيق.
  final DateTime? now;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  StreamSubscription<List<DoseSchedule>>? _schedulesSub;
  List<DoseSchedule> _schedules = const [];

  /// البث بيتعمل مرة واحدة هنا مش جوّه build.
  ///
  /// لو اتعمل جوّه build، كل إشعار من البث بيعيد البناء، وإعادة البناء
  /// بتعمل بث جديد بيبعت إشعار تاني — لفة مالهاش آخر.
  Stream<List<DoseEventView>>? _events;

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _routineDay => currentRoutineDay(widget.routine, _now);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_events != null) return;

    final services = AppScope.of(context);
    _events = services.events.watchDay(_routineDay);

    // أول ما الأدوية تتغيّر بنولّد أحداث اليوم من جديد — الإضافة بتظهر
    // فوراً، والإيقاف بيختفي، من غير ما حد يعمل refresh.
    _schedulesSub = services.medications
        .watchActiveSchedules(services.patientId)
        .listen(_onSchedules);
  }

  Future<void> _onSchedules(List<DoseSchedule> schedules) async {
    if (!mounted) return;
    setState(() => _schedules = schedules);

    final services = AppScope.of(context);
    final engine = ScheduleEngine(widget.routine);
    await services.events.materializeDay(
      _routineDay,
      engine.remindersForDay(schedules, _routineDay),
    );
  }

  @override
  void didUpdateWidget(TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // الروتين اتغيّر → ساعات اليوم بتتحرك، فبنعيد التوليد.
    if (oldWidget.routine != widget.routine) {
      unawaited(_onSchedules(_schedules));
    }
  }

  @override
  void dispose() {
    _schedulesSub?.cancel();
    super.dispose();
  }

  Future<void> _markTaken(List<DoseEventView> group) async {
    final services = AppScope.of(context);
    for (final dose in group) {
      await services.events.markTaken(dose.doseScheduleId, _routineDay);
    }
    // التذكير ده خلاص — نلغيه، ونمدّ النافذة بالخانة اللي فضيت.
    await services.scheduler.afterConfirmation(group.first.scheduledAt);
  }

  Future<void> _markSkipped(List<DoseEventView> group) async {
    final services = AppScope.of(context);
    for (final dose in group) {
      await services.events.markSkipped(dose.doseScheduleId, _routineDay);
    }
    await services.scheduler.afterConfirmation(group.first.scheduledAt);
  }

  String? _ruleLabelFor(int doseScheduleId) {
    for (final schedule in _schedules) {
      if (schedule.id == doseScheduleId.toString()) return schedule.ruleLabel;
    }
    return null;
  }

  List<AnchorMark> get _anchors {
    final engine = ScheduleEngine(widget.routine);
    return [
      for (final anchor in DayAnchor.values)
        AnchorMark(
          anchor,
          engine.resolveTime(
            anchor: anchor,
            offsetMinutes: 0,
            onDay: _routineDay,
          ),
        ),
    ];
  }

  /// بتجمّع الأحداث اللي في نفس الدقيقة — نفس تجميع المحرك بالظبط.
  List<List<DoseEventView>> _group(List<DoseEventView> events) {
    final byTime = <DateTime, List<DoseEventView>>{};
    for (final event in events) {
      byTime.putIfAbsent(event.scheduledAt, () => []).add(event);
    }
    final times = byTime.keys.toList()..sort();
    return [for (final time in times) byTime[time]!];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<DoseEventView>>(
          stream: _events,
          builder: (context, snapshot) {
            final events = snapshot.data ?? const <DoseEventView>[];
            final groups = _group(events);

            final pending = groups.where((g) => g.any((d) => !d.isDone));
            final next = pending.isEmpty ? null : pending.first;

            return ListView(
              padding: const EdgeInsets.all(F.gap),
              children: [
                const Text(
                  'يومك',
                  style: TextStyle(
                    fontSize: F.screenTitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'المراسي ثابتة، والجرعات معلّقة عليها.',
                  style: TextStyle(fontSize: F.minTextSize, color: F.muted),
                ),
                const SizedBox(height: F.gap),
                if (next != null) ...[
                  NextDoseCard(
                    doses: next,
                    now: _now,
                    onTaken: () => _markTaken(next),
                    onSkipped: () => _markSkipped(next),
                  ),
                  const SizedBox(height: F.gap),
                ] else if (events.isNotEmpty)
                  const _AllDonePanel(),
                if (events.isEmpty)
                  const _EmptyPanel()
                else
                  DayRail(
                    anchors: _anchors,
                    groups: groups,
                    now: _now,
                    ruleLabelFor: _ruleLabelFor,
                    onTaken: _markTaken,
                  ),
                const SizedBox(height: F.gap),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: F.primaryButtonHeight,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AddMedicationScreen(routine: widget.routine),
                            ),
                          ),
                          child: const Text(
                            'ضيف دوا',
                            style: TextStyle(
                              fontSize: F.minBodySize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: F.primaryButtonHeight,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  EditRoutineScreen(routine: widget.routine),
                            ),
                          ),
                          child: const Text(
                            'عدّل يومك',
                            style: TextStyle(
                              fontSize: F.minBodySize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AllDonePanel extends StatelessWidget {
  const _AllDonePanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: const Text(
          'خلصت أدوية النهاردة كلها. تسلم.',
          style: TextStyle(
            fontSize: F.minBodySize,
            fontWeight: FontWeight.w600,
            color: F.greenDeep,
          ),
        ),
      );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: const Text(
          'مفيش أدوية لسه. ضيف أول دوا وإحنا نفكّرك بيه.',
          style: TextStyle(
            fontSize: F.minBodySize,
            color: F.ink,
            height: 1.6,
          ),
        ),
      );
}
