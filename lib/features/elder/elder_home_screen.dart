import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/dose_state.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../adherence/patient_adherence_card.dart';
import '../medication/med_photo.dart';
import '../today/dose_actions.dart';

/// «نمط كبار السن» (المخطط 18): تحية، **كارت جرعة واحد**، و«تم ✅» عملاق.
///
/// الكارت هو أول حاجة في «الآن» بتاعة الرئيسية — أقدم جرعة فاتت من غير
/// تأكيد، وإلا الجاية — بنفس `nowGroups`، فالنمطين عمرهم ما يختلفوا على
/// «إيه اللي عليك دلوقتي». التأكيد والتأجيل هما نفس دوال الرئيسية.
///
/// المقاسات **أكبر** من الحد العادي: نص ٢٤+، والأساسي ٨٠. «تم ✅» أخضر زي
/// «تم التناول ✅» في شاشة التذكير — الأساسي الوحيد هنا.
///
/// مش مبني عن قصد: «📞 اتصل بمحمد» (مش بنجمّع أرقام تليفونات — المكالمات
/// اتلغت بقرار)، وسطر «قول تمام وأنا هسجّلها» (مفيش إدخال صوتي).
class ElderHomeScreen extends StatefulWidget {
  const ElderHomeScreen({required this.routine, this.now, super.key});

  final DayRoutine routine;

  /// للاختبارات.
  final DateTime? now;

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  StreamSubscription<List<DoseSchedule>>? _schedulesSub;
  List<DoseSchedule> _schedules = const [];
  Stream<List<DoseEventView>>? _events;
  Stream<PatientRow?>? _patient;
  final Set<DateTime> _snoozed = {};

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _routineDay => currentRoutineDay(widget.routine, _now);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_events != null) return;
    final services = AppScope.of(context);
    _events = services.events.watchDay(_routineDay);
    _patient = services.routines.watchPatient(services.patientId);
    _schedulesSub = services.medications.watchActiveSchedules(services.patientId).listen((schedules) async {
      if (!mounted) return;
      setState(() => _schedules = schedules);
      await services.events.materializeDay(
        _routineDay,
        ScheduleEngine(widget.routine).remindersForDay(schedules, _routineDay),
      );
    });
  }

  @override
  void dispose() {
    _schedulesSub?.cancel();
    super.dispose();
  }

  String? _ruleFor(int doseScheduleId) {
    for (final s in _schedules) {
      if (s.id == doseScheduleId.toString()) return s.ruleLabel;
    }
    return null;
  }

  Future<void> _later(List<DoseEventView> group) async {
    await snoozeGroup(AppScope.of(context), _routineDay, group, now: _now);
    if (mounted) setState(() => _snoozed.add(group.first.scheduledAt));
  }

  @override
  Widget build(BuildContext context) {
    final say = PatientVoice.of(context);
    return Scaffold(
      body: StreamBuilder<List<DoseEventView>>(
        stream: _events,
        builder: (context, snapshot) {
          final events = snapshot.data ?? const <DoseEventView>[];
          final all = groupByMinute(events);
          final now = nowGroups(all, _now);
          final group = now.isEmpty ? null : now.first;
          // باقي اليوم: كل المجموعات ما عدا اللي فوق في الكارت.
          final rest = [
            for (final g in all)
              if (group == null || g.first.scheduledAt != group.first.scheduledAt) g,
          ];

          return ListView(
            padding: EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: [
              StreamBuilder<PatientRow?>(
                stream: _patient,
                builder: (context, snap) => _Greeting(patient: snap.data, now: _now),
              ),
              const SizedBox(height: F.gap),
              if (group != null)
                _DoseCard(
                  doses: group,
                  now: _now,
                  rule: _ruleFor(group.first.doseScheduleId),
                  snoozed: _snoozed.contains(group.first.scheduledAt),
                  onDone: () => confirmGroup(AppScope.of(context), _routineDay, group),
                  onLater: () => _later(group),
                )
              else
                _Quiet(text: events.isEmpty ? 'مفيش أدوية النهارده' : say.allDone),
              const SizedBox(height: F.gap),
              // «إنت ماشي إزاي» — تحت كارت الجرعة، بالمقاس الكبير، قراية بس.
              PatientAdherenceCard(routineDay: _routineDay, now: _now, elder: true),
              // باقي اليوم — **للقراية بس**. الكارت فوق هو المكان الوحيد
              // اللي فيه «تمام» و«بعد شوية»؛ صف بزرار هنا معناه مكانين
              // للتأكيد، وده اللي نمط كبار السن موجود عشان يمنعه.
              if (rest.isNotEmpty) ...[
                const SizedBox(height: F.gap),
                Text(
                  'باقي اليوم',
                  style: TextStyle(
                    fontSize: F.elderTextSize,
                    fontWeight: FontWeight.w700,
                    color: F.mutedDark,
                  ),
                ),
                const SizedBox(height: F.s10),
                for (final g in rest) ...[
                  _DayRow(group: g, now: _now),
                  const SizedBox(height: F.s10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// صف من باقي اليوم: الساعة، أسامي الدوا، وحالته — بخط النمط الكبير.
///
/// **من غير أزرار.** القراية مش تحكّم: المريض بيشوف يومه كله، والفعل مكانه
/// الكارت اللي فوق. والفايتة بتقول «لسه ما اتأكدتش» زي السكة العادية —
/// مش «فات»: هو نسي، ما فشلش (نفس قاعدة الذهبي والكلام الهادي).
class _DayRow extends StatelessWidget {
  const _DayRow({required this.group, required this.now});

  final List<DoseEventView> group;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final done = group.every((d) => d.isDone);
    final at = group.first.scheduledAt;
    final unconfirmed =
        !done && (at.isBefore(now) || group.any((d) => d.state == DoseState.missed));
    final state = done
        ? (group.first.state == DoseState.skipped ? 'اتأجّل' : 'اتاخد')
        : unconfirmed
            ? 'لسه ما اتأكدتش'
            : 'جاي';

    return Container(
      key: ValueKey('elder-day-${at.millisecondsSinceEpoch}'),
      padding: const EdgeInsets.all(F.s14),
      decoration: BoxDecoration(
        color: done ? F.railGround : F.cardGround,
        borderRadius: BorderRadius.circular(F.radiusCard),
        // الذهبي معناه «دي لسه عايزاك» — وبس
        border: Border.all(color: unconfirmed ? F.gold : F.line, width: unconfirmed ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (done) ...[
                Icon(Icons.check, size: 26, color: F.greenOk),
                const SizedBox(width: F.s8),
              ],
              Expanded(
                child: Text(
                  arabicTime(at),
                  style: TextStyle(
                    fontSize: F.elderTextSize,
                    fontWeight: FontWeight.w700,
                    color: done ? F.mutedDark : F.ink,
                  ),
                ),
              ),
              Text(
                state,
                style: TextStyle(
                  fontSize: F.elderTextSize,
                  fontWeight: FontWeight.w600,
                  color: done ? F.mutedDark : F.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s6),
          Text(
            group.map((d) => d.medicationName).join(' + '),
            textDirection: nameDirection(group.first.medicationName),
            style: TextStyle(
              fontSize: F.elderNameSize,
              fontWeight: FontWeight.w700,
              color: done ? F.mutedDark : F.ink,
              fontFamily: F.monoFamily,
              fontFamilyFallback: F.monoFallback,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.patient, required this.now});

  final PatientRow? patient;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final name = patient?.name;
    final hasName = name != null && name.isNotEmpty && name != 'أنا';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          now.hour >= 4 && now.hour < 12 ? 'صباح الخير' : 'مساء الخير',
          style: TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.elderTitleSize,
            fontWeight: FontWeight.w700,
            color: F.ink,
          ),
        ),
        if (hasName)
          Text(
            'يا $name',
            style: TextStyle(fontSize: F.elderTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
          ),
      ],
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.doses,
    required this.now,
    required this.rule,
    required this.snoozed,
    required this.onDone,
    required this.onLater,
  });

  final List<DoseEventView> doses;
  final DateTime now;
  final String? rule;
  final bool snoozed;
  final VoidCallback onDone;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final say = PatientVoice.of(context);
    final at = doses.first.scheduledAt;
    final overdue = at.isBefore(now) || doses.any((d) => d.state == DoseState.missed);
    final body = TextStyle(fontSize: F.elderTextSize, color: F.mutedDark, height: 1.45);

    return FCard(
      tone: FCardTone.attention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overdue)
            Text(say.forgotIt, style: body.copyWith(fontWeight: FontWeight.w700, color: F.ink)),
          for (final dose in doses) ...[
            // نمط كبار السن: الصورة أكبر (١١٢) — فوق الاسم، مش جنبه
            if (dose.photoPath != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: F.s8),
                  child: MedPhotoThumb(
                    path: dose.photoPath,
                    name: dose.medicationName,
                    size: 112,
                    fallback: const SizedBox.shrink(),
                  ),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                dose.medicationName,
                textDirection: nameDirection(dose.medicationName),
                style: TextStyle(
                  fontSize: F.elderNameSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                  height: 1.3,
                ),
              ),
            ),
            if (dose.amountLabel != null) Text(dose.amountLabel!, style: body),
          ],
          if (rule != null) Text(rule!, style: body),
          Text(
            overdue ? 'لسه ما اتأكدتش — كان معادها ${arabicTime(at)}' : 'الساعة ${arabicTime(at)}',
            style: body.copyWith(color: F.ink),
          ),
          if (snoozed)
            Text(
              'هنفكّرك تاني بعد ربع ساعة',
              style: body.copyWith(fontWeight: FontWeight.w600, color: F.greenOk),
            ),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            label: 'تم ✅',
            height: F.elderPrimaryButtonHeight,
            fontSize: F.elderTitleSize,
            onPressed: onDone,
          ),
          const SizedBox(height: F.s10),
          FSecondaryButton(
            label: 'بعد شوية ⏰',
            height: F.elderSecondaryButtonHeight,
            fontSize: F.elderTextSize,
            onPressed: onLater,
          ),
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radius)),
        child: Text(
          text,
          style: const TextStyle(fontSize: F.elderTextSize, fontWeight: FontWeight.w600, color: F.greenDeep, height: 1.5),
        ),
      );
}
