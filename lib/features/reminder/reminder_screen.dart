import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/med_name.dart';

import '../medication/med_photo.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/wording/patient_words.dart';
import '../../data/repositories/preferences_repository.dart';
import '../../domain/voice/answer_parser.dart';
import '../voice/listen_button.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../core/widgets/primitives.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/escalation/escalation_ladder.dart';
import '../../domain/medication/medicine_form.dart';
import '../../domain/scheduling/dose_schedule.dart';

/// «تنبيه متصاعد» (المخطط 10) — اللي بتفتح لما المريض يدوس على الإشعار.
///
/// حاجة واحدة بس مطلوبة منه هنا: يقول خدها ولا لأ. عشان كده الشاشة غامقة،
/// الدوا في النص، و«تم التناول» أكبر حاجة فيها وهو الأساسي الوحيد. مفيش
/// شريط يوم ولا قايمة — «يومك» موجودة وراها لما يخلص.
///
/// السلّم **أربع** درجات — اللي موجود فعلاً: في الموعد · +١٥ · +٣٠ ·
/// +٦٠ (إشعار لابنه من السيرفر). الرامب بيقف عند البرتقالي؛ مفيش أحمر لأن الدرجة
/// الخامسة (دائرة الرعاية كلها) مش مبنية. المرحلة من الوقت الفعلي اللي
/// عدّى، والدرجات من `domain/escalation/` — مش أرقام تانية هنا.
/// درجة على السلّم زي ما بتتعرض.
class LadderStep {
  const LadderStep(this.label, this.after);
  final String label;
  final Duration after;
}

/// الأربع درجات — من ثوابت الدومين، مش نسخة تانية منها.
final List<LadderStep> ladderSteps = [
  const LadderStep('في الموعد', Duration.zero),
  LadderStep(
    '+${arabicNumber(EscalationRung.first.delay.inMinutes)} د',
    EscalationRung.first.delay,
  ),
  LadderStep(
    '+${arabicNumber(EscalationRung.second.delay.inMinutes)} د',
    EscalationRung.second.delay,
  ),
  // السيرفر هو اللي بيبلّغ الابن، بعد مهلته هو (٦٠) — مش مهلة الجهاز (٤٥).
  // «+٤٥» كان بيوعد بإشعار قبل ما حد يبعته فعلاً.
  LadderStep(
    '+${arabicNumber(serverGraceWindow.inMinutes)} د — إشعار لعيلتك أو ممرضك',
    serverGraceWindow,
  ),
];

/// المرحلة الحالية (0..3) من الوقت اللي عدّى فعلاً على معاد الجرعة.
int stageFor(Duration elapsed) {
  var stage = 0;
  for (var i = 1; i < ladderSteps.length; i++) {
    if (elapsed >= ladderSteps[i].after) stage = i;
  }
  return stage;
}

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({
    required this.routineDay,
    required this.scheduleIds,
    this.now,
    this.onExit,
    super.key,
  });

  /// يوم الروتين اللي التذكير بتاعه — من الـpayload، مش من الساعة دلوقتي.
  final DateTime routineDay;

  /// الجداول اللي رنّ عشانها — جرعة أو أكتر في نفس الدقيقة.
  final List<String> scheduleIds;

  /// للاختبارات — الشاشة بتستخدم دلوقتي الحقيقي في التطبيق.
  final DateTime? now;

  /// التنبيه قد يكون هو أول صفحة في التنزيلة الباردة، فلا يوجد route تحته
  /// نرجع له. الجذر يستعملها للانتقال إلى «يومك» بعد انتهاء التنبيه فقط.
  final VoidCallback? onExit;

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  Stream<List<DoseEventView>>? _dayEvents;
  late final Set<String> _scheduleIds = widget.scheduleIds.toSet();
  Stream<DeviceSettings>? _settings;
  StreamSubscription<List<DoseSchedule>>? _schedulesSub;
  Map<String, DoseSchedule> _schedules = const {};
  bool _busy = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dayEvents != null) return;

    final services = AppScope.of(context);
    // نمط كبار السن: الكلمة اللي جنب المايك أكبر
    _settings = services.preferences.watch();
    // **تنبيه الجرعة بيكسب**: أي كلام للرفيق الصوتي بيسكت لحظة ما الشاشة
    // دي تتفتح، من أي باب (إشعار، «يومك»، السكة).
    unawaited(services.voice?.stop());
    _dayEvents = services.events.watchDay(widget.routineDay);
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
    _leave(navigator);
  }

  void _leave(NavigatorState navigator) {
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      widget.onExit?.call();
    }
  }

  Future<void> _taken(List<DoseEventView> doses) => _act((services) async {
    for (final dose in doses) {
      await services.events.markTaken(dose.doseScheduleId, widget.routineDay);
    }
    // فوراً وقبل أي حاجة تانية: التأكيد بيلغي التذكير في نفس اللحظة.
    await services.scheduler.afterConfirmation(doses.first.scheduledAt);
    // «تمام، سجّلت إن حضرتك أخدته» — بعد الوعد، زي «يومك»؛ بالصوت وبالإيد
    unawaited(services.voice?.speakLine('help_confirm_done'));
  });

  /// «أخدته» / «فكّرني بعدين» بالصوت — **نفس** [_taken] و[_snooze] بتوع
  /// الزرارين، ولا سطر زيادة.
  Future<void> _spoken(DoseAnswer answer, List<DoseEventView> pending) =>
      answer == DoseAnswer.taken ? _taken(pending) : _snooze(pending);

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
        for (final d in doses)
          (name: d.medicationName, amount: d.amountLabel, note: d.mealLabel),
      ]),
      payload: encodePayloadFor(widget.routineDay, widget.scheduleIds),
      now: _now,
    );
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: F.greenDeep,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [F.greenDeep, F.greenDark],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<List<DoseEventView>>(
            stream: _dayEvents,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: F.gold),
                );
              }
              final allDoses = snapshot.data!;
              final doses = [
                for (final dose in allDoses)
                  if (_scheduleIds.contains(dose.doseScheduleId.toString()))
                    dose,
              ];
              if (doses.isEmpty) return const _GonePanel();

              final pending = [
                for (final d in doses)
                  if (!d.isDone) d,
              ];
              final next = allDoses.cast<DoseEventView?>().firstWhere(
                (dose) =>
                    dose != null &&
                    !dose.isDone &&
                    dose.scheduledAt.isAfter(_now) &&
                    !_scheduleIds.contains(dose.doseScheduleId.toString()),
                orElse: () => null,
              );

              return ListView(
                padding: const EdgeInsets.all(F.gap),
                children: [
                  const SizedBox(height: F.s8),
                  // الذهبي هنا في مكانه: ده تذكير.
                  Center(child: Kicker('تنبيه', color: F.gold)),
                  const SizedBox(height: F.s8),
                  Text(
                    pending.isEmpty ? tookItAlreadyLine : 'وقت الدوا',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: F.subtitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.onDark,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: F.gap),
                  _DoseCard(
                    doses: doses,
                    ruleLabelFor: _ruleLabelFor,
                    actions: pending.isEmpty
                        ? _DoneActions(
                            onBack: () => _leave(Navigator.of(context)),
                          )
                        : _PendingActions(
                            enabled: !_busy,
                            onTaken: () => _taken(pending),
                            onSnooze: () => _snooze(pending),
                            onSkipped: () => _skipped(pending),
                            // «قول «أخدته» أو دوس» — المايك كان صعب يتلاقى
                            // (٢٦ سبتمبر ٢٠٢٦)؛ الكلمة بتقول إن الصوت هنا
                            listen: StreamBuilder<DeviceSettings>(
                              stream: _settings,
                              builder: (context, snap) =>
                                  ListenButton<DoseAnswer>(
                                    tag: 'dose',
                                    onDark: true,
                                    elder: snap.data?.elderMode ?? false,
                                    hint: 'قول «أخدته» أو دوس',
                                    gapBelow: F.s10,
                                    parse: parseDoseAnswer,
                                    describe: (a) => a == DoseAnswer.taken
                                        ? 'أخدته'
                                        : 'فكّرني بعدين',
                                    onApply: (a) => _spoken(a, pending),
                                  ),
                            ),
                          ),
                  ),
                  if (next != null) ...[
                    const SizedBox(height: F.gap),
                    _NextDoseCard(dose: next),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String? _ruleLabelFor(int doseScheduleId) =>
      _schedules[doseScheduleId.toString()]?.ruleLabel;
}

/// كارت الدوا — أبيض على الغامق: الأدوية فوق (مجموعة، مش دوا واحد) والأزرار
/// جوّاه تحتها زي التصميم.
class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.doses,
    required this.ruleLabelFor,
    required this.actions,
  });

  final List<DoseEventView> doses;
  final String? Function(int doseScheduleId) ruleLabelFor;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: F.pageGround,
        borderRadius: BorderRadius.circular(F.radiusLarge),
        boxShadow: F.shadowModalDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, dose) in doses.indexed) ...[
            if (i > 0) Divider(color: F.lineSoft, height: F.gap * 2),
            _DoseRow(dose: dose, ruleLabel: ruleLabelFor(dose.doseScheduleId)),
          ],
          Divider(color: F.lineSoft, height: F.gap * 2),
          actions,
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
    final form = MedicineForm.fromWire(dose.form);
    final details = [
      ?dose.amountLabel,
      ?form?.label,
      ?ruleLabel,
      arabicTime(dose.scheduledAt),
    ].join(' — ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // صورته هو أولاً؛ لو مش موجودة/مكسورة فرسمة الشكل، ثم العامة.
            MedPhotoThumb(
              path: dose.photoPath,
              name: dose.medicationName,
              form: form,
              size: 64,
            ),
            const SizedBox(width: F.s12),
            Expanded(
              child: MedName(
                dose.medicationName,
                style: TextStyle(
                  fontSize: F.medicationNameSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.bodyFamily,
                  fontFamilyFallback: F.fontFallback,
                  height: 1.3,
                ),
              ),
            ),
            if (dose.isDone) ...[
              const SizedBox(width: F.s8),
              Icon(Icons.check, color: F.greenOk, size: 28),
            ],
          ],
        ),
        const SizedBox(height: F.s4),
        Text(
          dose.isDone && dose.actedAt != null
              ? takenAtLine(arabicTime(dose.actedAt!))
              : details,
          style: TextStyle(
            fontSize: F.minTextSize,
            color: F.mutedDark,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// الجرعة التالية فقط داخل يوم الروتين نفسه. لا نعرض جرعة انتهت أو جرعة
/// الإشعار المفتوح، ولا نخلط عليها جرعة بكرة.
class _NextDoseCard extends StatelessWidget {
  const _NextDoseCard({required this.dose});

  final DoseEventView dose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(F.s12),
      decoration: BoxDecoration(
        color: F.onDark.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(F.radiusSection),
        border: Border.all(color: F.onDark.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          MedPhotoThumb(
            path: dose.photoPath,
            name: dose.medicationName,
            form: MedicineForm.fromWire(dose.form),
            size: 44,
          ),
          const SizedBox(width: F.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الجرعة الجاية اليوم',
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    fontWeight: FontWeight.w700,
                    color: F.onDark,
                  ),
                ),
                const SizedBox(height: F.s4),
                Text(
                  '${dose.medicationName} — ${arabicTime(dose.scheduledAt)}',
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    color: F.onDark.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// الأزرار: «تم التناول ✅» أخضر ٦٤ — الأساسي الوحيد — و«تأجيل ١٥ د ⏰»
/// و«تخطّي» جنب بعض ٥٦.
///
/// «تخطّي» من غير ❌ عن قصد: الإيموجي أحمر، والأحمر للطوارئ بس — والتخطّي
/// مش غلطة تتزيّن بعلامة رفض. و«لا أذكر» مش موجودة: مفيش حالة ليها في
/// dose_events، ولو مش فاكر فده هو نفسه «تخطّي» مع واحد يسأله.
class _PendingActions extends StatelessWidget {
  const _PendingActions({
    required this.enabled,
    required this.onTaken,
    required this.onSnooze,
    required this.onSkipped,
    required this.listen,
  });

  /// «اتكلم» — فوق الزرارين، على نفس السكّة.
  final Widget listen;
  final bool enabled;
  final VoidCallback onTaken;
  final VoidCallback onSnooze;
  final VoidCallback onSkipped;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // المسافة تحت زرار «اتكلم» جواه (gapBelow) — من غيره الشاشة زي 1.13.1 بالبكسل
        Align(alignment: AlignmentDirectional.centerEnd, child: listen),
        FPrimaryButton(
          label: 'تم التناول ✅',
          onPressed: enabled ? onTaken : null,
        ),
        const SizedBox(height: F.s10),
        Row(
          children: [
            Expanded(
              child: FSecondaryButton(
                label: 'تأجيل ${arabicNumber(snoozeDelay.inMinutes)} د ⏰',
                onPressed: enabled ? onSnooze : null,
              ),
            ),
            const SizedBox(width: F.s10),
            Expanded(
              child: FSecondaryButton(
                label: 'تخطّي',
                onPressed: enabled ? onSkipped : null,
              ),
            ),
          ],
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
          '$thanksLine مفيش حاجة مطلوبة منك دلوقتي.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(label: backToDayLine, onPressed: onBack),
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
              color: F.onDark,
              height: 1.3,
            ),
          ),
          const SizedBox(height: F.gap),
          SizedBox(
            height: F.primaryButtonHeight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(
                backgroundColor: F.pageGround,
                foregroundColor: F.ink,
              ),
              child: Text(backToDayLine),
            ),
          ),
        ],
      ),
    );
  }
}
