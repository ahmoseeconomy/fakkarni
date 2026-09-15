import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'emergency_widgets.dart' show notFilled;

/// كارت الطوارئ عند الابن (D5.2): فصيلة الدم والحساسية والأمراض المزمنة.
///
/// **عايش هنا في `features/emergency/` عن قصد**: الأحمر للطوارئ بس، و
/// `red_only_in_emergency_test` بيسمح بيه جوّه المجلد ده وبس. شاشة الابن
/// بتستعمل الكارت، مش بتلوّن بالأحمر بنفسها.
///
/// مفيش أرقام اتصال ولا زرار إسعاف: الأرقام بتفضل على موبايل الأب (مش في
/// السحابة أصلاً — 0012)، والكارت للقراية بس. حقل فاضي = «لسه ما اتملاش»،
/// ومفيش حاجة بتتخمّن.
class EmergencyFactsCard extends StatelessWidget {
  const EmergencyFactsCard({this.bloodType, this.allergies, this.chronicConditions, super.key});

  final String? bloodType;
  final String? allergies;
  final String? chronicConditions;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('emergency-facts'),
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(color: F.redDeep, borderRadius: BorderRadius.circular(F.radiusCard)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'معلومات الطوارئ',
              style: TextStyle(fontSize: F.sectionHeadSize, fontWeight: FontWeight.w700, color: F.onRed),
            ),
            const SizedBox(height: F.s8),
            _Fact(label: 'فصيلة الدم', value: bloodType, ltr: true),
            _Fact(label: 'الحساسية', value: allergies),
            _Fact(label: 'أمراض مزمنة', value: chronicConditions),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.ltr = false});

  final String label;
  final String? value;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: F.s8),
        padding: const EdgeInsets.all(F.s12),
        decoration: BoxDecoration(color: F.redPanel, borderRadius: BorderRadius.circular(F.radiusCard)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.onRedMuted)),
            const SizedBox(height: F.s4),
            Text(
              value ?? notFilled,
              textDirection: value != null && ltr ? TextDirection.ltr : null,
              style: TextStyle(
                fontSize: F.minBodySize,
                fontWeight: value == null ? FontWeight.w500 : FontWeight.w700,
                color: value == null ? F.onRedMuted : F.onRed,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}
