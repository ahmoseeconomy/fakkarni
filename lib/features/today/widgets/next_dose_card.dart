import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/dose_state.dart';
import '../../../data/repositories/dose_event_repository.dart';

/// الجرعة الجاية — مثبّتة فوق وكبيرة.
///
/// دي الحاجة الوحيدة اللي المريض محتاج يعملها دلوقتي، فهي الحاجة الوحيدة
/// اللي بتاخد لون غامق وزرار ذهبي عريض.
class NextDoseCard extends StatelessWidget {
  const NextDoseCard({
    required this.doses,
    required this.now,
    required this.onTaken,
    required this.onSkipped,
    super.key,
  });

  /// كل الأدوية اللي في نفس الدقيقة — تذكير واحد، مش تذكيرين.
  final List<DoseEventView> doses;
  final DateTime now;
  final VoidCallback onTaken;
  final VoidCallback onSkipped;

  @override
  Widget build(BuildContext context) {
    final at = doses.first.scheduledAt;
    // المهلة خلصت — سؤال هادي، مش لوم. الكارت نفسه والزرار نفسه.
    final missed = doses.any((d) => d.state == DoseState.missed);

    return Container(
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: F.greenDeep,
        borderRadius: BorderRadius.circular(F.radius + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            missed ? 'نسيتها؟' : 'الجاية',
            style: TextStyle(
              fontSize: F.minTextSize,
              fontWeight: FontWeight.w600,
              color: F.ivory.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            arabicTime(at),
            style: const TextStyle(
              fontSize: F.bigTimeSize,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          for (final dose in doses)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                dose.amountLabel == null
                    ? dose.medicationName
                    : '${dose.medicationName} — ${dose.amountLabel}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            arabicCountdown(at.difference(now)),
            style: TextStyle(
              fontSize: F.minBodySize,
              color: F.ivory.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: F.gap),
          SizedBox(
            height: F.primaryButtonHeight,
            child: FilledButton(
              onPressed: onTaken,
              style: FilledButton.styleFrom(
                backgroundColor: F.gold,
                foregroundColor: F.ink,
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('أخدته'),
            ),
          ),
          SizedBox(
            height: F.minTapTarget,
            child: TextButton(
              onPressed: onSkipped,
              child: Text(
                'مش هاخده دلوقتي',
                style: TextStyle(
                  fontSize: F.minTextSize,
                  color: F.ivory.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
