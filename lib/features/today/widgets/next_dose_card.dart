import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/format/name_direction.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/patient_voice.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/dose_state.dart';
import '../../../data/repositories/dose_event_repository.dart';

/// الجرعة الجاية — مثبّتة فوق السكة (المخطط 24).
///
/// دي الحاجة الوحيدة اللي المريض محتاج يعملها دلوقتي، فهي الحاجة الوحيدة
/// اللي بتاخد أرضية غامقة وزرار ذهبي ٦٤ — والزرار الأساسي الوحيد في الشاشة.
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
      padding: const EdgeInsets.all(F.s18),
      decoration: BoxDecoration(
        color: F.greenDeep,
        borderRadius: BorderRadius.circular(F.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            missed ? PatientVoice.of(context).forgotIt : 'الجاية',
            style: const TextStyle(
              fontSize: F.minTextSize,
              fontWeight: FontWeight.w600,
              color: F.goldText,
            ),
          ),
          const SizedBox(height: F.s8),
          for (final dose in doses) ...[
            // اسم الدوا mono؛ لاتيني → LTR على الشمال زي التصميم، عربي → يمين
            Text(
              dose.medicationName,
              textDirection: nameDirection(dose.medicationName),
              textAlign: TextAlign.start,
              style: const TextStyle(
                fontSize: F.medicationNameSize,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: F.monoFamily,
                fontFamilyFallback: F.monoFallback,
                height: 1.35,
              ),
            ),
            if (dose.amountLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: F.s4),
                child: Text(
                  dose.amountLabel!,
                  style: const TextStyle(fontSize: F.minBodySize, color: F.ivory),
                ),
              ),
          ],
          const SizedBox(height: F.s6),
          Text(
            '${arabicCountdown(at.difference(now))} · ${arabicTime(at)}',
            style: const TextStyle(fontSize: F.minBodySize, color: F.ivory),
          ),
          const SizedBox(height: F.gap),
          FPrimaryButton(label: 'أخدته', gold: true, onPressed: onTaken),
          SizedBox(
            height: F.minTapTarget,
            child: TextButton(
              onPressed: onSkipped,
              style: TextButton.styleFrom(foregroundColor: F.ivory),
              child: const Text(
                'مش هاخده دلوقتي',
                style: TextStyle(fontSize: F.minTextSize),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
