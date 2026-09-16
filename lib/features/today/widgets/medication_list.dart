import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/repositories/medication_repository.dart';

/// «أدويتك» — صف لكل دوا (المخطط 09): الاسم، والجرعة · القاعدة. الدوسة بتعدّل.
class MedicationList extends StatelessWidget {
  const MedicationList({required this.items, required this.onTap, super.key});

  final List<MedicationSummary> items;
  final void Function(MedicationSummary) onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: F.gap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'أدويتك',
                style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
              ),
            ),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(F.radius),
                    side: const BorderSide(color: F.line),
                  ),
                  child: InkWell(
                    onTap: () => onTap(item),
                    borderRadius: BorderRadius.circular(F.radius),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: F.minTapTarget),
                      padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.medication.name,
                                  style: const TextStyle(
                                    fontSize: F.minBodySize,
                                    fontWeight: FontWeight.w700,
                                    color: F.ink,
                                    fontFamily: F.monoFamily,
                                    fontFamilyFallback: F.monoFallback,
                                  ),
                                ),
                                Text(
                                  [
                                    item.medication.amountLabel ?? 'الجرعة مش معروفة',
                                    item.schedules.map((s) => s.ruleLabel).join(' + '),
                                  ].join(' — '),
                                  style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'عدّل',
                            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
