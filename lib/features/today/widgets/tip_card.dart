import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../tips/tip_picker.dart';
import '../tips/tips_ar.dart';
import 'card_type_icon.dart';

/// **«معلومة ليك»** — مكان كارت المية على «يومك».
///
/// معلومة واحدة في اليوم عن أدويته هو، من نص مكتوب بإيد إنسان ومراجَع
/// (`tips/tips_ar.dart`) — لا ذكاء ولا شبكة. نفس وزن كارت المية: كارت
/// هادي تحت كتلتي «الآن» و«جدول النهاردة»، مش تنبيه ومش ذهبي. الدوسة
/// بتفتح الدوا اللي المعلومة عنه لو فيه، وإلا ولا حاجة.
class TipCard extends StatelessWidget {
  const TipCard({required this.tip, this.onOpenMedication, super.key});

  final Tip tip;
  final void Function(int medicationId)? onOpenMedication;

  @override
  Widget build(BuildContext context) {
    final medicationId = tip.medicationId;
    final onTap = medicationId == null || onOpenMedication == null ? null : () => onOpenMedication!(medicationId);
    return Semantics(
      button: onTap != null,
      child: Material(
        color: F.cardGround,
        borderRadius: BorderRadius.circular(F.radiusCard),
        child: InkWell(
          key: const ValueKey('tip-card'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(F.s14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardTypeIcon(icon: Icons.lightbulb_outline),
                const SizedBox(width: F.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tipCardTitle,
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                      ),
                      const SizedBox(height: F.s4),
                      Text(
                        tip.text,
                        key: const ValueKey('tip-text'),
                        style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.45),
                      ),
                      if ((tip.instructions ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: F.s8),
                        GoldNote(
                          key: const ValueKey('tip-instructions'),
                          tip.instructions!.trim(),
                        ),
                      ],
                      if (onTap != null) ...[
                        const SizedBox(height: F.s6),
                        Text(
                          'افتح الدوا',
                          style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.green),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
