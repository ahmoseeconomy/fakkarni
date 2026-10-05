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
/// مش عارف هما كام ولا مين فيهم غير لما ينزل ويعدّهم. دلوقتي كتلة واحدة،
/// العدد في عنوانها، وكل دوا سطر.
///
/// **اللي اتأجّل ليه مجموعته المتسمّية** («أجّلتها — ٢»)، وكل سطر فيها
/// بيقول الموبايل هيفكّره إمتى تاني — ده السؤال الوحيد اللي بيسأله عن دوا
/// أجّله، وكان مالوش إجابة على الشاشة.
///
/// الفايتة **ذهبي ونصّها محايد** («لسه ما اتأكدتش») — الأحمر للطوارئ بس.
/// نسي، ما فشلش.
///
/// **إعادة التصميم (٤ أكتوبر ٢٠٢٦)**: الكتلة بقت كارت «الجرعة الجاية» —
/// العنوان جوّه الكارت («الجرعة الجاية»، أو «الجرعات — ٣» لأكتر من دوا)،
/// ودوا واحد بيتعرض كبير: رسمة نوعه (أو صورته) من غير كلام عليها، اسمه،
/// شريحة الغرض، الجرعة، والساعة. الزرار «أخدتها» أخضر (أو «أخدتهم كلهم»)،
/// و«فكّرني بعد ١٥ دقيقة» = التأجيل نفسه. السطور والتأكيد لكل سطر و«نسيتها؟»
/// والحافة الدهبي زي ما هم.
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
                    nextDoseTitle(all.length),
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
          if (single)
            _SingleDose(line: all.single, now: widget.now, compact: widget.compact)
          else
            for (final (i, line) in due.indexed) ...[
              if (i > 0) const _LineGap(),
              _DoseLine(
                line: line,
                now: widget.now,
                // **الكلمة مرة واحدة لكل حالة.** دواءين في نفس الدقيقة
                // حالتهم واحدة، و«الجاية» مكتوبة مرتين فوق بعض ضوضا.
                showKicker: i == 0 || _kicker(due[i - 1], widget.now) != _kicker(line, widget.now),
                onConfirm: perLine ? () => widget.onConfirmLine(line) : null,
              ),
            ],
          if (!single && postponed.isNotEmpty) ...[
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
              _DoseLine(
                line: line,
                now: widget.now,
                // المأجّلة عنوان مجموعتها بيسمّيها — مفيش كلمة فوق كل سطر.
                showKicker: false,
                onConfirm: perLine ? () => widget.onConfirmLine(line) : null,
              ),
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

/// عنوان الكارت: «الجرعة الجاية» لدوا واحد، «الجرعات — ٣» لأكتر.
String nextDoseTitle(int doses) => doses <= 1 ? 'الجرعة الجاية' : 'الجرعات — ${arabicNumber(doses)}';

/// «فكّرني بعد ١٥ دقيقة» — المدة من [snoozeDelay] نفسها، فالكلمة ما تقدرش
/// تكدب على التأجيل.
String get laterLabel => 'فكّرني بعد ${arabicNumber(snoozeDelay.inMinutes)} دقيقة';

/// مقاس رسمة الدوا الكبيرة في الكارت.
const double nextDosePictureSize = 132;

/// ونفسها على الشاشات القصيرة.
const double nextDosePictureCompactSize = 96;

/// سطر الجرعة: «قرص واحد بعد الأكل» — الجرعة وكلمة الأكل من غير شَرطة.
String doseAmountLine(DoseEventView dose) => [
      // الجرعة مش معروفة — بهدوء، من غير لوم
      (dose.amountLabel?.trim().isNotEmpty ?? false) ? dose.amountLabel!.trim() : 'الجرعة مش معروفة',
      ?dose.mealLabel,
    ].join(' ');

/// **دوا واحد في الكارت — كبير زي التصميم.** الاسم والشريحة والجرعة يمين،
/// والساعة تحت خط، والرسمة (أو صورته) شمال من غير أي كلام عليها.
class _SingleDose extends StatelessWidget {
  const _SingleDose({required this.line, required this.now, this.compact = false});

  final NowLine line;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dose = line.dose;
    final at = dose.scheduledAt;
    final moment = _momentOf(dose, now);
    final kicker = line.postponed ? null : _kickerFor(moment);
    final purpose = MedicationPurpose.fromStorage(dose.purpose);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kicker != null && moment != DoseMoment.upcoming)
                Text(
                  kicker,
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
          size: compact ? nextDosePictureCompactSize : nextDosePictureSize,
        ),
      ],
    );
  }
}

/// سطر الحالة تحت الساعة — نفس الكلام اللي السطور الكتير بتقوله.
String _statusOf(NowLine line, DoseMoment moment, DateTime now) {
  final at = line.dose.scheduledAt;
  return switch (line.remindAgainAt) {
    // **الإجابة على «أجّلته لإمتى؟»** — نفس اللحظة اللي الإشعار اتجدول عليها
    final again? => 'هيفكّرك ${arabicTime(again)}',
    _ => switch (moment) {
        DoseMoment.missed => 'لسه ما اتأكدتش — كان معادها ${arabicTime(at)}',
        DoseMoment.dueNow => 'معادها دلوقتي — ${arabicTime(at)}',
        DoseMoment.upcoming => '${arabicCountdown(at.difference(now))} — ${arabicTime(at)}',
      },
  };
}

/// كلمة حالة السطر — «نسيتها؟» / «الجاية»، أو null للمأجّلة.
///
/// **بتاخد [now] المحقونة**، مش `DateTime.now()`: الشاشة كلها بتتبني على
/// وقت واحد، واختبار بيحقن وقته — ساعة تانية هنا معناها سطر بيقول حاجة
/// والكلمة فوقه بتقول غيرها.
String? _kicker(NowLine line, DateTime now) {
  if (line.postponed) return null;
  final dose = line.dose;
  return _kickerFor(_momentOf(dose, now));
}

DoseMoment _momentOf(DoseEventView dose, DateTime now) =>
    doseMomentOf(scheduledAt: dose.scheduledAt, now: now, markedMissed: dose.state == DoseState.missed);

/// «نسيتها؟» بعد المهلة بس — في معادها «دلوقتي».
String _kickerFor(DoseMoment m) => switch (m) {
      DoseMoment.missed => forgotItLine,
      DoseMoment.dueNow => 'دلوقتي',
      DoseMoment.upcoming => 'الجاية',
    };

class _LineGap extends StatelessWidget {
  const _LineGap();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: F.s10),
    child: Divider(height: 1, color: F.lineSoft),
  );
}

/// سطر دوا واحد: الاسم وجرعته، وحالته، وزرار تأكيده.
class _DoseLine extends StatelessWidget {
  const _DoseLine({
    required this.line,
    required this.now,
    required this.showKicker,
    required this.onConfirm,
  });

  final NowLine line;
  final DateTime now;

  /// الكلمة بتتكتب مرة لكل حالة، مش فوق كل سطر.
  final bool showKicker;

  /// null = الكتلة فيها سطر واحد، والزرار الأساسي هو تأكيده.
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final dose = line.dose;
    final at = dose.scheduledAt;
    final moment = _momentOf(dose, now);
    final status = _statusOf(line, moment, now);
    // كلمة الحالة («نسيتها؟» بعد المهلة / «دلوقتي» / «الجاية»)، ومتشالة عن
    // المأجّلة: عنوان المجموعة فوقها بيقول «أجّلتها» خلاص.
    final kicker = !showKicker || line.postponed ? null : _kickerFor(moment);
    final amount = dose.amountLabel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // صورة الحباية لو موجودة — الأيقونة لو لأ
        MedPhotoThumb(
          path: dose.photoPath,
          name: dose.medicationName,
          form: MedicineForm.fromWire(dose.form),
          size: 56,
        ),
        const SizedBox(width: F.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kicker != null)
                Text(
                  kicker,
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    fontWeight: FontWeight.w700,
                    color: F.mutedDark,
                    height: 1.3,
                  ),
                ),
              // الاسم يمين وساعته شمال — نفس الصف
              NameTimeRow(
                name: dose.medicationName,
                time: arabicTime(at),
                timeKey: ValueKey('dose-time-${dose.doseScheduleId}'),
                nameStyle: TextStyle(
                  fontSize: F.medicationNameSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.bodyFamily,
                  fontFamilyFallback: F.fontFallback,
                  height: 1.3,
                ),
                timeStyle: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink, height: 1.7),
              ),
              if (amount != null && amount.isNotEmpty)
                Text(
                  amount,
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                ),
              Text(
                status,
                key: ValueKey('dose-status-${dose.doseScheduleId}'),
                style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4),
              ),
            ],
          ),
        ),
        if (onConfirm case final confirm?) ...[
          const SizedBox(width: F.s8),
          _LineConfirm(
            key: ValueKey('confirm-${dose.doseScheduleId}'),
            name: dose.medicationName,
            onPressed: confirm,
          ),
        ],
      ],
    );
  }
}

/// زرار تأكيد سطر واحد — **بكلمته**، وهدف لمسه كامل.
///
/// مش أيقونة لوحدها: «مفيش زرار أيقونة من غير كلمة» قاعدة مكتوبة، وراجل
/// عنده ٧٢ سنة مش هيخمّن معنى علامة صح جنب اسم دوا. و`Semantics` بتسمّي
/// الدوا للقارئ عشان «تأكيد» × ٣ ما تبقاش تلات أزرار بنفس الاسم.
class _LineConfirm extends StatelessWidget {
  const _LineConfirm({required this.name, required this.onPressed, super.key});

  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'تأكيد $name',
    button: true,
    excludeSemantics: true,
    // **`IntrinsicWidth` مش زينة**: الزرار جوّه `Row` من غير `Expanded`،
    // يعني عرضه بيوصله لانهاية — و`SizedBox` بارتفاع ثابت بتمرّرها
    // لجوّه فبتوقع وقت التخطيط. ده بيخلّي العرض من النص نفسه، فالكلمة
    // بتكبر مع تكبير الخط من غير ما تتقص.
    child: IntrinsicWidth(
      child: SizedBox(
        height: F.minTapTarget,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: F.ink,
            side: BorderSide(color: F.buttonEdge, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: F.s12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
            textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
          ),
          child: const Text('تأكيد'),
        ),
      ),
    ),
  );
}
