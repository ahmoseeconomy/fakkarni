/// **شكل «يومك» الجديد على موبايل الممرض** (المرحلة ٤، ٥ أكتوبر ٢٠٢٦ —
/// قرارات المالك A): نفس التحية بالشمس، نفس الدايرة، نفس كارت «الجرعة
/// الجاية» (بـ[DoseShowcase] نفسه)، ونفس سكة «باقي اليوم» ([DayRail]
/// نفسها) — **بأزرار الممرض هو**: «أكّد إنه أخدها» بس، بشرط
/// `dose_confirmable` زي ما هو، ومن غير «فكّرني بعد ١٥ دقيقة» (الممرض
/// ما بيأجّلش جدول المريض).
///
/// **مفيش جدولة ولا حلّ مراسي هنا**: كل الأوقات هي اللي موبايل المريض
/// حسبها ([CaregiverDoseEvent.scheduledAt]) — المحوّل بيلبّس الصفوف شكل
/// [DoseEventView] للعرض وبس، والرقم المحلي فيه رقم عرض مش جدول.
library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../data/dose_state.dart';
import '../../data/repositories/dose_event_repository.dart' show DoseEventView;
import '../../domain/scheduling/routine_day.dart';
import '../today/dose_actions.dart' show NowLine, groupByMinute, nowGroups;
import '../today/today_progress.dart';
import '../today/widgets/progress_ring.dart';
import '../today/widgets/now_block.dart'
    show
        DoseShowcase,
        nextDoseTitle,
        nextDosePictureSize,
        nextDosePictureCompactSize;
import 'nurse_widgets.dart' show nurseCanConfirmEvent;

/// صف الصورة بلبس [DoseEventView] — **للعرض بس**: الرسمة والشريحة والحالة.
/// الدوا بيتربط بالـuuid ([medicationForDose])، والرقم المحلي رقم عرض
/// (ترتيب الصف) مش مفتاح جدول.
DoseEventView doseViewFromEvent(
  CaregiverDoseEvent e,
  int displayId, {
  required List<CaregiverMedication> medications,
}) {
  final med = medicationForDose(medications, e);
  return DoseEventView(
    doseScheduleId: displayId,
    medicationName: e.medicationName,
    scheduledAt: e.scheduledAt,
    state: DoseState.values.asNameMap()[e.state] ?? DoseState.pending,
    amountLabel: e.amountLabel,
    actedAt: e.actedAt,
    routineDay: e.routineDay,
    form: med?.form,
    purpose: med?.purpose,
  );
}

/// جرعات **يوم الروتين بتاع النهارده** (بداية اليوم ٤:٠٠ — نفس حد المريض)
/// متلبّسة للعرض، مع صفّها الأصلي جنبها عشان التأكيد يمشي على السحابة.
List<({DoseEventView view, CaregiverDoseEvent event})> nurseTodayDoses(
  CaregiverSnapshot snapshot,
  DateTime now,
) {
  final today = routineDayOf(now);
  final rows = <({DoseEventView view, CaregiverDoseEvent event})>[];
  for (final (i, e) in snapshot.events.indexed) {
    final day = e.routineDay ?? routineDayOf(e.scheduledAt);
    if (DateTime(day.year, day.month, day.day) != today) continue;
    rows.add((
      view: doseViewFromEvent(e, i, medications: snapshot.medications),
      event: e,
    ));
  }
  return rows;
}

/// التقسيمة بتاعة المريض نفسها: الكارت = اللي معاده جه ([nowGroups] —
/// ومفيش حاجة، أقرب جاية)، والسكة = الباقي.
({List<List<DoseEventView>> card, List<List<DoseEventView>> rest})
nurseDaySplit(List<DoseEventView> views, DateTime now) {
  final groups = groupByMinute(views);
  final card = nowGroups(groups, now);
  final carded = {for (final g in card) g.first.scheduledAt};
  return (
    card: card,
    rest: [
      for (final g in groups)
        if (!carded.contains(g.first.scheduledAt)) g,
    ],
  );
}

/// التحية والدايرة — نفس شكل «يومك» (الشمس من [isDaytime] اللي الشاشة
/// بتبعته من `DayNight`، والتحية بالوقت الحقيقي مهما كان وضع الشاشة).
class NurseDayHeader extends StatelessWidget {
  const NurseDayHeader({
    required this.progress,
    required this.daytime,
    super.key,
  });

  final TodayProgress progress;
  final bool daytime;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            daytime ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
            key: ValueKey(
              daytime ? 'nurse-greeting-sun' : 'nurse-greeting-moon',
            ),
            size: 30,
            color: F.greetingIconInk,
          ),
          const SizedBox(width: F.s8),
          Flexible(
            child: Text(
              daytime ? 'صباح الخير' : 'مساء الخير',
              key: const ValueKey('nurse-greeting'),
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.subtitleSize,
                fontWeight: FontWeight.w800,
                color: F.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: F.s8),
      TodayProgressRow(progress: progress),
    ],
  );
}

/// كارت «الجرعة الجاية» عند الممرض — [DoseShowcase] نفسه، وزرار واحد بس:
/// «أكّد إنه أخدها»، بنفس بوابة النهارده (`canConfirm` + `dose_confirmable`).
/// الجرعة المتأكّدة نيابةً بتقول «أكّدتها ✓ — مستنية موبايله يوصله».
class NurseNowCard extends StatelessWidget {
  const NurseNowCard({
    required this.groups,
    required this.events,
    required this.now,
    required this.canConfirm,
    required this.proxied,
    required this.busy,
    required this.onConfirm,
    this.compact = false,
    super.key,
  });

  final List<List<DoseEventView>> groups;

  /// الصفوف الأصلية بالترتيب اللي المحوّل رقّمه — التأكيد بيمشي عليها.
  final List<({DoseEventView view, CaregiverDoseEvent event})> events;
  final DateTime now;
  final bool canConfirm;
  final Set<String> proxied;
  final Set<String> busy;
  final Future<void> Function(CaregiverDoseEvent event) onConfirm;
  final bool compact;

  CaregiverDoseEvent _eventOf(DoseEventView v) =>
      events.firstWhere((r) => r.view.doseScheduleId == v.doseScheduleId).event;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final g in groups)
        for (final d in g) NowLine(dose: d, group: g),
    ];
    final single = lines.length == 1;
    return FCard(
      key: const ValueKey('nurse-now-card'),
      tone: FCardTone.attention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // من غير «ساعدني»: مفيش صوت على جهاز الممرض خالص (قاعدة صلبة) —
          // زرار «ساعدني» صوت، وحارس أماكن الجمل بيثبّت help_next_dose
          // على شاشات المريض بس.
          Row(
            children: [
              Icon(Icons.schedule, size: 26, color: F.green),
              const SizedBox(width: F.s8),
              Flexible(
                child: Text(
                  nextDoseTitle,
                  key: const ValueKey('nurse-now-title'),
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.sectionHeadSize + 2,
                    fontWeight: FontWeight.w800,
                    color: F.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s10),
          for (final (i, line) in lines.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: F.s10),
                child: Divider(height: 1, color: F.lineSoft),
              ),
            DoseShowcase(
              line: line,
              now: now,
              compact: compact,
              pictureSize: single && !compact
                  ? nextDosePictureSize
                  : nextDosePictureCompactSize,
            ),
            ..._action(_eventOf(line.dose), perLine: !single),
          ],
        ],
      ),
    );
  }

  /// زرار السطر — **«أكّد إنه أخدها» بس** (قرار المالك 3A): مفيش تأجيل،
  /// ومفيش «أخدتهم كلهم» (كل تأكيد نيابةً قرار لوحده على جرعة بعينها).
  /// الجرعة اللي لسه ما جاش وقتها (الجاية) من غير زرار — السيرفر بيرفض
  /// التأكيد البدري (`dose_confirmable`).
  List<Widget> _action(CaregiverDoseEvent event, {required bool perLine}) {
    if (proxied.contains(event.uuid)) {
      return [
        const SizedBox(height: F.s8),
        Text(
          'أكّدتها ✓ — مستنية موبايله يوصله',
          key: ValueKey('nurse-proxied-${event.uuid}'),
          style: TextStyle(
            fontSize: F.minTextSize,
            fontWeight: FontWeight.w700,
            color: F.green,
            height: 1.4,
          ),
        ),
      ];
    }
    if (!canConfirm || !nurseCanConfirmEvent(event, now)) return const [];
    final waiting = busy.contains(event.uuid);
    final button = perLine
        ? SizedBox(
            height: F.minTapTarget,
            child: OutlinedButton(
              key: ValueKey('nurse-confirm-${event.uuid}'),
              onPressed: waiting ? null : () => onConfirm(event),
              style: OutlinedButton.styleFrom(
                foregroundColor: F.green,
                side: BorderSide(color: F.green, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(F.radiusCard),
                ),
                textStyle: const TextStyle(
                  fontSize: F.minTextSize,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(waiting ? 'ثواني…' : 'أكّد إنه أخدها'),
            ),
          )
        : FPrimaryButton(
            key: ValueKey('nurse-confirm-${event.uuid}'),
            label: waiting ? 'ثواني…' : 'أكّد إنه أخدها',
            onPressed: waiting ? null : () => onConfirm(event),
          );
    return [const SizedBox(height: F.s8), button];
  }
}
