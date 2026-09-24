import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/sync/medication_change_pull.dart';

/// «سارة ضافت دوا Concor» — اللي الممرض غيّره واتطبّق على الموبايل ده
/// (المرحلة ب). سطر لكل تغيير و«تمام» بتمسحهم. مفيش حاجة لما مفيش.
class CircleNotices extends StatelessWidget {
  const CircleNotices({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
        valueListenable: MedicationChangePuller.notices,
        builder: (context, lines, _) {
          if (lines.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: F.s12),
            child: Container(
              key: const ValueKey('circle-notices'),
              padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
              decoration: BoxDecoration(
                color: F.cardGround,
                borderRadius: BorderRadius.circular(F.radiusCard),
                border: const BorderDirectional(start: BorderSide(color: F.gold, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: F.s4),
                      child: Text(
                        line,
                        style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.4),
                      ),
                    ),
                  const SizedBox(height: F.s4),
                  FSecondaryButton(
                    key: const ValueKey('circle-notices-ok'),
                    label: 'تمام',
                    onPressed: MedicationChangePuller.clearNotices,
                  ),
                ],
              ),
            ),
          );
        },
      );
}
