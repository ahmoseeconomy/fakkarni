import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/medication/stock.dart';

/// **«باقي كام قرص؟» — كارت لوحده** (طلب المالك، ٢٩ سبتمبر ٢٠٢٦). كان سطر
/// «عندك كام وحدة؟» محدش فاهمه. السؤال بوحدة الدوا نفسه؛ ولو الجرعة ما
/// بتقولش هو إيه، الكارت بيسأل الأول «ده إيه؟» — مش بنفترض إنه أقراص.
/// العجلة **ما بتكتبش حاجة لحد ما تتحرّك**: الرقم ده بتاع الإنسان.
class StockLeftCard extends StatelessWidget {
  const StockLeftCard({
    required this.unit,
    required this.value,
    required this.onUnit,
    required this.onChanged,
    this.unitChosen = false,
    this.wheelKey = const ValueKey('stock-wheel'),
    this.trailing,
    super.key,
  });

  /// null = لسه ما نعرفش هو إيه — بنسأل.
  final String? unit;

  /// اللي فاضل لو متسجّل — null = العجلة واقفة مكانها ومش بتكتب.
  final int? value;

  /// الوحدة اتختارت هنا (مش من الجرعة) — فبيبان «غيّر».
  final bool unitChosen;
  final ValueChanged<String?> onUnit;
  final ValueChanged<int> onChanged;
  final Key wheelKey;

  /// زرار تحت العجلة («تمام»).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final u = unit;
    return FCard(
      key: const ValueKey('stock-left-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            u == null ? 'باقي كام؟' : stockLeftQuestion(u),
            key: const ValueKey('stock-left-question'),
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.subtitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          const SizedBox(height: F.s4),
          Text(
            'عشان نفكّرك قبل ما يخلص — لو حابب.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.s10),
          if (u == null) ...[
            Text('ده إيه؟', style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
            const SizedBox(height: F.s8),
            Wrap(
              spacing: F.s8,
              runSpacing: F.s8,
              children: [
                for (final c in stockUnitChoices)
                  AnchorChip(key: ValueKey('stock-unit-$c'), label: c, selected: false, onTap: () => onUnit(c)),
              ],
            ),
          ] else ...[
            FNumberWheel(
              key: wheelKey,
              value: value,
              rest: 30,
              min: 0,
              max: 500,
              unit: u,
              semanticsLabel: 'المخزون',
              onChanged: onChanged,
            ),
            if (unitChosen)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  height: F.minTapTarget,
                  child: TextButton(
                    key: const ValueKey('stock-unit-change'),
                    onPressed: () => onUnit(null),
                    child: Text('مش $u؟ غيّر',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
                  ),
                ),
              ),
          ],
          if (trailing case final t?) ...[const SizedBox(height: F.s8), t],
        ],
      ),
    );
  }
}
