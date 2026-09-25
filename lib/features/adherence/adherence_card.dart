import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/adherence/adherence.dart';
import 'adherence_dots.dart';

/// كارت «إنت ماشي إزاي» — للمريض (عادي ونمط كبار السن) وللممرض. **قراية
/// بس**: ولا زرار هنا بيكتب حاجة؛ الدوسة بتفتح التفاصيل.
///
/// تشجيع وبس: الرقم الكبير («٥ أيام ورا بعض»)، سطر تحته، ونقط الأسبوع.
/// صفر = «النهارده بداية جديدة». مفيش أحمر، ومفيش «فشلت».
class AdherenceCard extends StatelessWidget {
  const AdherenceCard({
    required this.adherence,
    required this.title,
    this.onOpen,
    this.elder = false,
    super.key,
  });

  final Adherence adherence;
  final String title;
  final VoidCallback? onOpen;
  final bool elder;

  @override
  Widget build(BuildContext context) {
    final a = adherence;
    return Material(
      key: const ValueKey('adherence-card'),
      color: F.cardGround,
      borderRadius: BorderRadius.circular(F.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(F.radiusLarge),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(F.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: elder ? F.elderTextSize : F.subtitleSize,
                  fontWeight: FontWeight.w800,
                  color: F.ink,
                ),
              ),
              const SizedBox(height: F.s8),
              Text(
                streakLine(a.currentStreak, atLeast: a.currentAtLeast),
                key: const ValueKey('adherence-streak'),
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: elder ? F.elderTitleSize + 4 : F.screenTitleSize + 5,
                  fontWeight: FontWeight.w800,
                  color: a.currentStreak > 0 ? F.green : F.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: F.s4),
              Text(
                streakCheer(a.currentStreak),
                style: TextStyle(
                  fontSize: elder ? F.elderTextSize : F.minBodySize,
                  color: F.mutedDark,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: F.s14),
              AdherenceDots(
                week: a.week,
                today: a.today,
                dotSize: elder ? 36 : 28,
                labelSize: F.minTextSize,
              ),
              if (onOpen != null) ...[
                const SizedBox(height: F.s12),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: F.minTapTarget),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'شوف التفاصيل',
                          style: TextStyle(
                            fontSize: elder ? F.elderTextSize : F.minBodySize,
                            fontWeight: FontWeight.w700,
                            color: F.ink,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_left, color: F.mutedDark, size: 28),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
