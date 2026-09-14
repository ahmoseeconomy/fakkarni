import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../medication/edit_medication_screen.dart';
import '../reminder/reminder_screen.dart';
import 'widgets/day_rail.dart';
import 'widgets/next_dose_card.dart';

/// «جدول النهاردة» (المخطط 24) — الجرعة الجاية مثبّتة فوق، وباقي اليوم
/// تحتها على سكة. العنوان في جسم الصفحة — الشريط العلوي للهيكل ([AppShell]).
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

  /// الأدوية اللي جرعتها مش معروفة — سؤال هادي للصيدلي، مش تنبيه.
  Stream<List<MedicationRow>>? _amountUnknown;

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _routineDay => currentRoutineDay(widget.routine, _now);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_events != null) return;

    final services = AppScope.of(context);
    _events = services.events.watchDay(_routineDay);
    _amountUnknown = services.medications.watchAmountUnknown(services.patientId);

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

  void _openEdit(int medicationId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EditMedicationScreen(medicationId: medicationId),
        ),
      );

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

  /// الدوسة على كارت في السكة بتفتح شاشة التذكير بتاعته — أخدته / فكّرني /
  /// مش هاخده — بدل زرار أساسي على كل كارت.
  void _openReminder(List<DoseEventView> group) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReminderScreen(
            routineDay: _routineDay,
            scheduleIds: [for (final d in group) d.doseScheduleId.toString()],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Scaffold جوّه تبويب الهيكل: الأرضية، وMaterial للـInkWell لما الشاشة
    // تتبني لوحدها في الاختبار.
    return Scaffold(
      body: StreamBuilder<List<DoseEventView>>(
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
                'جدول النهاردة',
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
              const SizedBox(height: F.s4),
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
              ] else if (events.isNotEmpty) ...[
                const _AllDonePanel(),
                const SizedBox(height: F.gap),
              ],
              if (events.isEmpty)
                const _EmptyPanel()
              else
                DayRail(
                  anchors: _anchors,
                  groups: groups,
                  now: _now,
                  ruleLabelFor: _ruleLabelFor,
                  onOpen: _openReminder,
                ),
              // القاعدة ٤: مجهول اتسجّل لازم يفضل ظاهر هنا — سؤال هادي للصيدلي
              StreamBuilder<List<MedicationRow>>(
                stream: _amountUnknown,
                builder: (context, snapshot) {
                  final meds = snapshot.data ?? const <MedicationRow>[];
                  if (meds.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: F.gap),
                    child: _FollowUpPanel(
                      items: [
                        for (final m in meds)
                          (label: 'اسأل الصيدلي عن جرعة ${m.name}', onTap: () => _openEdit(m.id)),
                      ],
                    ),
                  );
                },
              ),
              // مسافة تحت عشان آخر سطر ما يستخبّاش ورا زرار «ضيف»
              const SizedBox(height: F.s30 * 2),
            ],
          );
        },
      ),
    );
  }
}

/// نفس نبرة «التذكير هيفضل شغال لحد ما توقفه بنفسك»: سطر هادي، مش تنبيه.
///
/// مجهول اتسجّل ونقدر نتابعه كويس؛ اللي مش كويس هو مجهول اتنسي في صمت.
class _FollowUpPanel extends StatelessWidget {
  const _FollowUpPanel({required this.items});

  final List<({String label, VoidCallback onTap})> items;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              // الدوسة بتفتح التعديل — السؤال ليه مكان يتجاوب فيه.
              InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(F.radius),
                child: Container(
                  constraints: const BoxConstraints(minHeight: F.minTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: 10),
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.6),
                        ),
                      ),
                      const Text(
                        'اكتبها',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.green),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
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
        child: Text(
          PatientVoice.of(context).allDone,
          style: const TextStyle(
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
          'مفيش أدوية لسه. دوس «ضيف» تحت وإحنا نفكّرك بيه.',
          style: TextStyle(
            fontSize: F.minBodySize,
            color: F.ink,
            height: 1.6,
          ),
        ),
      );
}
