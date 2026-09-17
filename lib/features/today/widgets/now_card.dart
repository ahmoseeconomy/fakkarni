import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/format/name_direction.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/patient_voice.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/dose_state.dart';
import '../../../data/repositories/dose_event_repository.dart';

/// كارت في «الآن» (المخطط 4): مجموعة جرعات في نفس الدقيقة مستنية تأكيد —
/// الجاية، أو اللي فات معادها من غير تأكيد.
///
/// الفايتة **ذهبي ونصّها محايد** («لسه ما اتأكدتش») — التصميم بيلوّنها أحمر،
/// والأحمر عندنا للطوارئ بس. نسي، ما فشلش.
///
/// الزرار الأساسي («تأكيد الجرعة») على **أول كارت بس** — حد الشاشة زرارين
/// أساسيين. الكروت التانية بـ«افتح» (شاشة التذكير بتاعتها). «لاحقًا» في كل
/// كارت هو التأجيل الحقيقي — ربع ساعة — مش إخفاء للكارت.
class NowCard extends StatelessWidget {
  const NowCard({
    required this.doses,
    required this.now,
    required this.primary,
    required this.onConfirm,
    required this.onOpen,
    required this.onLater,
    this.snoozed = false,
    super.key,
  });

  final List<DoseEventView> doses;
  final DateTime now;

  /// الكارت ده صاحب الزرار الأساسي الوحيد.
  final bool primary;
  final VoidCallback onConfirm;
  final VoidCallback onOpen;
  final VoidCallback onLater;

  /// اتأجّل من الشاشة دي — بنقول ده بالكلام تحته.
  final bool snoozed;

  @override
  Widget build(BuildContext context) {
    final say = PatientVoice.of(context);
    final at = doses.first.scheduledAt;
    final overdue = at.isBefore(now) || doses.any((d) => d.state == DoseState.missed);

    return FCard(
      tone: FCardTone.attention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // أيقونة النوع على اليمين زي التصميم — الكارت بيتعرف من بصّة
          Row(
            children: [
              const CardTypeIcon(icon: Icons.medication_outlined),
              const SizedBox(width: F.s8),
              Expanded(
                child: Text(
                  overdue ? say.forgotIt : 'الجاية',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s4),
          for (final dose in doses)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                dose.medicationName,
                textDirection: nameDirection(dose.medicationName),
                style: TextStyle(
                  fontSize: F.medicationNameSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: F.s4),
          Text(
            overdue
                ? 'لسه ما اتأكدتش — كان معادها ${arabicTime(at)}'
                : '${arabicCountdown(at.difference(now))} — ${arabicTime(at)}',
            style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
          ),
          if (snoozed) ...[
            const SizedBox(height: F.s4),
            Text(
              'هنفكّرك تاني بعد ربع ساعة',
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.greenOk),
            ),
          ],
          const SizedBox(height: F.s12),
          if (primary) ...[
            FPrimaryButton(
              label: doses.length == 1 ? 'تأكيد الجرعة' : 'تأكيد الجرعات',
              gold: true,
              onPressed: onConfirm,
            ),
            const SizedBox(height: F.s8),
            FSecondaryButton(label: 'لاحقًا', onPressed: onLater),
          ] else
            Row(
              children: [
                Expanded(child: FSecondaryButton(label: 'افتح', onPressed: onOpen)),
                const SizedBox(width: F.s10),
                Expanded(child: FSecondaryButton(label: 'لاحقًا', onPressed: onLater)),
              ],
            ),
        ],
      ),
    );
  }
}

/// أيقونة نوع الكارت (المخطط ٤): جرعة، قياس سكر، تقرير تحليل، مرحلة فحص.
/// مربّع هادي على يمين الكارت — بيقول نوعه من غير ما ياخد انتباه من الذهبي.
class CardTypeIcon extends StatelessWidget {
  const CardTypeIcon({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusTile)),
        child: Icon(icon, size: 22, color: F.green),
      );
}
