import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/format/name_direction.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/patient_voice.dart';
import '../../../domain/patient/sex.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/dose_state.dart';
import '../dose_actions.dart';
import 'card_type_icon.dart';

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
class NowBlock extends StatefulWidget {
  const NowBlock({
    required this.lines,
    required this.now,
    required this.onConfirmLine,
    required this.onConfirmAll,
    required this.onLater,
    super.key,
  });

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
    final say = PatientVoice.of(context);
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

    return FCard(
      key: const ValueKey('now-block'),
      tone: FCardTone.attention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, line) in due.indexed) ...[
            if (i > 0) const _LineGap(),
            _DoseLine(
              line: line,
              now: widget.now,
              say: say,
              // **الكلمة مرة واحدة لكل حالة.** دواءين في نفس الدقيقة
              // حالتهم واحدة، و«الجاية» مكتوبة مرتين فوق بعض ضوضا.
              showKicker: i == 0 || _kicker(due[i - 1], say, widget.now) != _kicker(line, say, widget.now),
              onConfirm: perLine ? () => widget.onConfirmLine(line) : null,
            ),
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
              _DoseLine(
                line: line,
                now: widget.now,
                say: say,
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
            label: all.length == 1 ? 'تأكيد الجرعة' : 'تأكيد الكل',
            gold: true,
            onPressed: widget.onConfirmAll,
          ),
          // **«لاحقًا» بيأجّل اللي لسه مستني وبس** — اللي اتأجّل خلاص
          // ميعاده متحدّد، وإعادة تأجيله من غير ما يطلب بتزقّه لقدّام.
          if (widget.lines.due.isNotEmpty) ...[
            const SizedBox(height: F.s8),
            FSecondaryButton(
              key: const ValueKey('now-later'),
              label: 'لاحقًا',
              onPressed: widget.onLater,
            ),
          ],
        ],
      ),
    );
  }
}

/// كلمة حالة السطر — «نسيتها؟» / «الجاية»، أو null للمأجّلة.
///
/// **بتاخد [now] المحقونة**، مش `DateTime.now()`: الشاشة كلها بتتبني على
/// وقت واحد، واختبار بيحقن وقته — ساعة تانية هنا معناها سطر بيقول حاجة
/// والكلمة فوقه بتقول غيرها.
String? _kicker(NowLine line, Say say, DateTime now) {
  if (line.postponed) return null;
  final dose = line.dose;
  final overdue = dose.scheduledAt.isBefore(now) || dose.state == DoseState.missed;
  return overdue ? say.forgotIt : 'الجاية';
}

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
    required this.say,
    required this.showKicker,
    required this.onConfirm,
  });

  final NowLine line;
  final DateTime now;
  final Say say;

  /// الكلمة بتتكتب مرة لكل حالة، مش فوق كل سطر.
  final bool showKicker;

  /// null = الكتلة فيها سطر واحد، والزرار الأساسي هو تأكيده.
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final dose = line.dose;
    final at = dose.scheduledAt;
    final overdue = at.isBefore(now) || dose.state == DoseState.missed;
    final status = switch (line.remindAgainAt) {
      // **الإجابة على «أجّلته لإمتى؟»** — نفس اللحظة اللي الإشعار
      // اتجدول عليها، مش حساب تاني.
      final again? => 'هيفكّرك ${arabicTime(again)}',
      _ when overdue => 'لسه ما اتأكدتش — كان معادها ${arabicTime(at)}',
      _ => '${arabicCountdown(at.difference(now))} — ${arabicTime(at)}',
    };
    // كلمة الحالة زي ما كانت على الكارت المثبّت («نسيتها؟» / «الجاية»)،
    // ومتشالة عن المأجّلة: عنوان المجموعة فوقها بيقول «أجّلتها» خلاص.
    final kicker =
        !showKicker || line.postponed ? null : (overdue ? say.forgotIt : 'الجاية');
    final amount = dose.amountLabel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardTypeIcon(icon: Icons.medication_outlined),
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
              Text(
                dose.medicationName,
                textDirection: nameDirection(dose.medicationName),
                style: TextStyle(
                  fontSize: F.medicationNameSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                  height: 1.3,
                ),
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
            side: const BorderSide(color: F.greenDeep, width: 1.5),
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
