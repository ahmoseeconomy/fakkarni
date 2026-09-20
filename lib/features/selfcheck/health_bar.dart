import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/health/health_watcher.dart';
import '../../domain/health/health_report.dart';
import 'health_check_screen.dart';

/// شريط على «يومك» لما يبقى فيه حاجة مكسورة — **ومفيش حاجة لما كله تمام**.
///
/// شريط بيقول «كله تمام» كل يوم بيتحوّل لخلفية، وبعدين بيتعدّى عليه لما
/// يقول حاجة مهمة. فالغياب هو الرسالة العادية، والوجود هو اللي بيلفت.
///
/// ذهبي مش أحمر: الراجل اللي بيقرا ده مش في خطر — فيه حاجة محتاجة
/// انتباهه دلوقتي، وده معنى الذهبي في التطبيق كله.
class HealthBar extends StatelessWidget {
  const HealthBar({super.key});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<HealthReport?>(
        valueListenable: HealthWatcher.latest,
        builder: (context, report, _) {
          final first = report?.broken.firstOrNull;
          if (first == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: F.s12),
            child: Material(
              color: F.cardGround,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(F.radiusCard),
                side: BorderSide(color: F.gold, width: 2),
              ),
              child: InkWell(
                key: const ValueKey('health-bar'),
                borderRadius: BorderRadius.circular(F.radiusCard),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const HealthCheckScreen()),
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: F.minTapTarget),
                  padding: const EdgeInsets.symmetric(
                      horizontal: F.s14, vertical: F.s12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              first.title,
                              style: TextStyle(
                                fontSize: F.minBodySize,
                                fontWeight: FontWeight.w700,
                                color: F.ink,
                                height: 1.4,
                              ),
                            ),
                            Text(
                              'اضغط تشوف التفاصيل',
                              style: TextStyle(
                                  fontSize: F.minTextSize, color: F.mutedDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
