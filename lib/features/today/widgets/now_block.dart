import '../../../domain/escalation/dose_moment.dart';
import '../../../domain/wording/patient_words.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/med_name.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/dose_state.dart';
import '../../../data/repositories/dose_event_repository.dart' show DoseEventView;
import '../dose_actions.dart';
import '../../medication/med_photo.dart';
import '../../../data/services/reminder_plan.dart' show snoozeDelay;
import '../../../domain/medication/medication_purpose.dart';
import '../../../domain/medication/medicine_form.dart';
import '../../medication/med_groups.dart';
import '../../voice/help_button.dart';

/// **كتلة «الآن» — واحدة، بعدّادها.**
///
/// كانت كارت لكل جرعة، مكدّسين. تلات أدوية مأجّلة معناها تلات كروت: الراجل
/// مش عارف هما كام ولا مين فيهم غير لما ينزل ويعدّهم. دلوقتي كتلة واحدة
/// وكل دوا سطر.
///
/// **اللي اتأجّل ليه مجموعته المتسمّية** («أجّلتها — ٢»)، وكل سطر فيها
/// بيقول الموبايل هيفكّره إمتى تاني — ده السؤال الوحيد اللي بيسأله عن دوا
/// أجّله، وكان مالوش إجابة على الشاشة.
///
/// الفايتة **ذهبي ونصّها محايد** («لسه ما اتأكدتش») — الأحمر للطوارئ بس.
/// نسي، ما فشلش.
///
/// **إعادة التصميم (٤ أكتوبر ٢٠٢٦، ومراجعة المالك ٥ أكتوبر)**: الكتلة كارت
/// «الجرعة الجاية» — **العنوان ده دايماً**، مهما كان عدد السطور (المالك شال
/// «الجرعات — ٢»). كل دوا بياخد عرض التصميم نفسه: رسمة نوعه (أو صورته) من
/// غير كلام عليها، اسمه، شريحة الغرض، الجرعة، **والساعة مرة واحدة** — سطر
/// الحالة من غيرها («معادها دلوقتي» مش «معادها دلوقتي — ١٠:٠٠ ص»)، ومفيش
/// كلمة «دلوقتي»/«الجاية» فوق الاسم («نسيتها؟» بعد المهلة فضلت — مش ساعة).
/// التأكيد لكل سطر زرار «أخدتها» أخضر مليان بنفس شكل التصميم (لما فيه أكتر
/// من سطر)، و«أخدتهم كلهم» تحت الكتلة، و«فكّرني بعد ١٥ دقيقة» = التأجيل
/// نفسه. الطيّ («+ دوا كمان») والحافة الدهبي زي ما هم.
class NowBlock extends StatefulWidget {
  const NowBlock({
    required this.lines,
    required this.now,
    required this.onConfirmLine,
    required this.onConfirmAll,
    required this.onLater,
    this.compact = false,
    super.key,
  });

  /// شاشة قصيرة (آيفون SE): رسمة أصغر والساعة وحالتها في صف واحد — عشان
  /// «أخدتها» يفضل في أول شاشة فوق الدوك.
  final bool compact;

  final NowLines lines;
  final DateTime now;

  /// تأكيد دوا واحد — الباقي بيفضل مكانه.
  final ValueChanged<NowLine> onConfirmLine;

  /// «تأكيد الكل» — كل سطر في الكتلة، المأجّل والمستني.
  final VoidCallback onConfirmAll;

  /// «لاحقًا» — نفس التأجيل الحقيقي (ربع ساعة) على اللي لسه مستني.
  final VoidCallback onLater;

  @override
  State<NowBlock> createState() => _NowBlockState();
}

class _NowBlockState extends State<NowBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = [...widget.lines.due, ...widget.lines.postponed];
    final hidden = _expanded ? 0 : (all.length - maxNowLines).clamp(0, all.length);
    final shown = hidden == 0 ? all : all.take(maxNowLines).toList();
    final due = [
      for (final l in shown)
        if (!l.postponed) l,
    ];
    final postponed = [
      for (final l in shown)
        if (l.postponed) l,
    ];
    // **زرار واحد لما السطر واحد.** التأكيد على مستوى السطر بيبان لما
    // يبقى فيه اختيار فعلاً؛ مع دوا واحد الزرار الأساسي هو هو، وزرار
    // تاني بنفس المعنى بيزوّد ارتفاع ويلخبط.
    final perLine = all.length > 1;

    final single = all.length == 1;
    return FCard(
      key: const ValueKey('now-block'),
      tone: FCardTone.attention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HelpRow(
            id: 'help_next_dose',
            child: Row(
              children: [
                Icon(Icons.schedule, size: 26, color: F.green),
                const SizedBox(width: F.s8),
                Flexible(
                  child: Text(
                    nextDoseTitle,
                    key: const ValueKey('now-title'),
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
          ),
          const SizedBox(height: F.s10),
          for (final (i, line) in due.indexed) ...[
            if (i > 0) const _LineGap(),
            _DoseBig(
              line: line,
              now: widget.now,
              compact: widget.compact,
              // دوا واحد بياخد الرسمة الكاملة؛ مع أكتر الرسمة الوسطانية —
              // لسه رسمة التصميم، بس الكتلة ما تبقاش أطول من يوم الراجل.
              pictureSize: single && !widget.compact ? nextDosePictureSize : nextDosePictureCompactSize,
            ),
            if (perLine) ...[
              const SizedBox(height: F.s8),
              _LineTaken(
                key: ValueKey('confirm-${line.dose.doseScheduleId}'),
                name: line.dose.medicationName,
                onPressed: () => widget.onConfirmLine(line),
              ),
            ],
          ],
          if (postponed.isNotEmpty) ...[
            if (due.isNotEmpty) const _LineGap(),
            Padding(
              padding: const EdgeInsets.only(bottom: F.s8),
              child: Text(
                postponedLabel(widget.lines.postponed.length),
                key: const ValueKey('postponed-head'),
                style: TextStyle(
                  fontSize: F.minTextSize,
                  fontWeight: FontWeight.w700,
                  color: F.mutedDark,
                ),
              ),
            ),
            for (final (i, line) in postponed.indexed) ...[
              if (i > 0) const _LineGap(),
              _DoseBig(
                line: line,
                now: widget.now,
                compact: widget.compact,
                pictureSize: single && !widget.compact ? nextDosePictureSize : nextDosePictureCompactSize,
              ),
              if (perLine) ...[
                const SizedBox(height: F.s8),
                _LineTaken(
                  key: ValueKey('confirm-${line.dose.doseScheduleId}'),
                  name: line.dose.medicationName,
                  onPressed: () => widget.onConfirmLine(line),
                ),
              ],
            ],
          ],
          if (hidden > 0) ...[
            const _LineGap(),
            InkWell(
              key: const ValueKey('now-more'),
              onTap: () => setState(() => _expanded = true),
              child: Container(
                constraints: const BoxConstraints(minHeight: F.minTapTarget),
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  moreDosesLabel(hidden),
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.green,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: F.s12),
          FPrimaryButton(
            key: const ValueKey('confirm-all'),
            // أخضر — الدهبي على حافة الكارت بيقول «محتاجك دلوقتي» خلاص
            label: single ? 'أخدتها' : 'أخدتهم كلهم',
            onPressed: widget.onConfirmAll,
          ),
          // **«فكّرني بعد ١٥ دقيقة» بيأجّل اللي لسه مستني وبس** — اللي اتأجّل
          // خلاص ميعاده متحدّد، وإعادة تأجيله من غير ما يطلب بتزقّه لقدّام.
          if (widget.lines.due.isNotEmpty) ...[
            const SizedBox(height: F.s8),
            FSecondaryButton(
              key: const ValueKey('now-later'),
              label: laterLabel,
              onPressed: widget.onLater,
            ),
          ],
        ],
      ),
    );
  }
}

/// عنوان الكارت — **دايماً «الجرعة الجاية»**، مهما كان عدد السطور (مراجعة
/// المالك، ٥ أكتوبر ٢٠٢٦: «الجرعات — ٢» اتشالت).
const String nextDoseTitle = 'الجرعة الجاية';

/// «فكّرني بعد ١٥ دقيقة» — المدة من [snoozeDelay] نفسها، فالكلمة ما تقدرش
/// تكدب على التأجيل.
String get laterLabel => 'فكّرني بعد ${arabicNumber(snoozeDelay.inMinutes)} دقيقة';

/// مقاس رسمة الدوا الكبيرة في الكارت.
const double nextDosePictureSize = 132;

/// ونفسها على الشاشات القصيرة، ولكل سطر لما الكارت فيه أكتر من دوا.
const double nextDosePictureCompactSize = 96;

/// سطر الجرعة: «قرص واحد بعد الأكل» — الجرعة وكلمة الأكل من غير شَرطة.
String doseAmountLine(DoseEventView dose) => [
      // الجرعة مش معروفة — بهدوء، من غير لوم
      (dose.amountLabel?.trim().isNotEmpty ?? false) ? dose.amountLabel!.trim() : 'الجرعة مش معروفة',
      ?dose.mealLabel,
    ].join(' ');

/// **سطر دوا بعرض التصميم.** الاسم والشريحة والجرعة يمين، والساعة تحت خط،
/// والرسمة (أو صورته) شمال من غير أي كلام عليها.
///
/// **الساعة مكتوبة مرة واحدة** — في صفها الكبير. سطر الحالة تحتها من غيرها
/// (مراجعة المالك ٥ أكتوبر: «دلوقتي» + «١٠:٠٠ ص» + «معادها دلوقتي — ١٠:٠٠ ص»
/// كانوا تلات مرات لنفس اللحظة). «نسيتها؟» فوق الاسم بعد المهلة بس — كلمة
/// حالة مش ساعة، وهي الجملة المكتوبة من زمان.
class _DoseBig extends StatelessWidget {
  const _DoseBig({
    required this.line,
    required this.now,
    required this.pictureSize,
    this.compact = false,
  });

  final NowLine line;
  final DateTime now;
  final bool compact;
  final double pictureSize;

  @override
  Widget build(BuildContext context) {
    final dose = line.dose;
    final at = dose.scheduledAt;
    final moment = _momentOf(dose, now);
    final purpose = MedicationPurpose.fromStorage(dose.purpose);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!line.postponed && moment == DoseMoment.missed)
                Text(
                  forgotItLine,
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark, height: 1.3),
                ),
              MedName(
                dose.medicationName,
                style: TextStyle(
                  fontSize: F.medicationNameSize + 2,
                  fontWeight: FontWeight.w800,
                  color: F.ink,
                  fontFamily: F.bodyFamily,
                  fontFamilyFallback: F.fontFallback,
                  height: 1.3,
                ),
              ),
              if (purpose != null) ...[
                const SizedBox(height: F.s6),
                Align(alignment: AlignmentDirectional.centerStart, child: MedPurposeChip(purpose, neutral: true)),
              ],
              const SizedBox(height: F.s6),
              Text(
                doseAmountLine(dose),
                key: ValueKey('next-dose-amount-${dose.doseScheduleId}'),
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
              ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: F.s8),
                  child: Divider(height: 1, color: F.lineSoft),
                )
              else
                const SizedBox(height: F.s4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 26, color: F.mutedDark),
                  const SizedBox(width: F.s8),
                  Flexible(
                    child: Text(
                      arabicTime(at),
                      key: ValueKey('dose-time-${dose.doseScheduleId}'),
                      style: TextStyle(fontSize: F.medicationNameSize + 4, fontWeight: FontWeight.w800, color: F.ink, height: 1.2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: F.s4),
              Text(
                _statusOf(line, moment, now),
                key: ValueKey('dose-status-${dose.doseScheduleId}'),
                style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(width: F.s8),
        MedPhotoThumb(
          path: dose.photoPath,
          name: dose.medicationName,
          form: MedicineForm.fromWire(dose.form),
          size: pictureSize,
        ),
      ],
    );
  }
}

/// سطر الحالة تحت الساعة — **من غير الساعة**: هي مكتوبة فوقه خلاص، وكتابتها
/// تاني هي «الساعة تلات مرات» اللي المالك شالها. «هيفكّرك ١٠:٣٠ ص» بتفضل
/// بساعتها لأنها لحظة **تانية** (ميعاد التذكير)، مش تكرار.
String _statusOf(NowLine line, DoseMoment moment, DateTime now) {
  final at = line.dose.scheduledAt;
  return switch (line.remindAgainAt) {
    // **الإجابة على «أجّلته لإمتى؟»** — نفس اللحظة اللي الإشعار اتجدول عليها
    final again? => 'هيفكّرك ${arabicTime(again)}',
    _ => switch (moment) {
        DoseMoment.missed => 'لسه ما اتأكدتش',
        DoseMoment.dueNow => 'معادها دلوقتي',
        DoseMoment.upcoming => arabicCountdown(at.difference(now)),
      },
  };
}

DoseMoment _momentOf(DoseEventView dose, DateTime now) =>
    doseMomentOf(scheduledAt: dose.scheduledAt, now: now, markedMissed: dose.state == DoseState.missed);

class _LineGap extends StatelessWidget {
  const _LineGap();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: F.s10),
    child: Divider(height: 1, color: F.lineSoft),
  );
}

/// زرار تأكيد سطر واحد — **«أخدتها» محدّد أخضر، مش مليان** (المالك،
/// ٥ أكتوبر ٢٠٢٦): «زرارين أساسيين في الشاشة كحد أقصى» قاعدة بتفضل،
/// فالمليان الوحيد في الكتلة هو «أخدتهم كلهم». بعرض الكارت وبكلمة
/// التصميم، وأقصر من زرار الكل (هدف اللمس ٥٦ مش ٦٤). و`Semantics`
/// بتسمّي الدوا للقارئ عشان «أخدتها» × ٣ ما تبقاش تلات أزرار بنفس الاسم.
class _LineTaken extends StatelessWidget {
  const _LineTaken({required this.name, required this.onPressed, super.key});

  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'أخدتها — $name',
    button: true,
    excludeSemantics: true,
    child: SizedBox(
      height: F.minTapTarget,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: F.green,
          side: BorderSide(color: F.green, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
          textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w800),
        ),
        child: const Text('أخدتها'),
      ),
    ),
  );
}
