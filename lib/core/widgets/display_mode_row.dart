import 'package:flutter/material.dart';

import '../theme/theme_mode_store.dart';
import '../theme/tokens.dart';

/// «وضع الشاشة» — تلقائي / نهاري على طول / ليلي على طول (مراجعة المالك،
/// ٥ أكتوبر ٢٠٢٦). ودجت واحدة للأب ولابنه — نفس منطق زرار القمر: إعداد
/// **الموبايل ده**، مش بيانات حد. الاختيار بيتطبّق فوراً وبيتخزّن
/// ([ThemeModeStore.setMode])؛ «تلقائي» بيتبع الشروق والغروب الحقيقيين
/// عند الفتح والرجوع للمقدمة.
class DisplayModeRow extends StatefulWidget {
  const DisplayModeRow({super.key});

  @override
  State<DisplayModeRow> createState() => _DisplayModeRowState();
}

class _DisplayModeRowState extends State<DisplayModeRow> {
  Future<void> _pick(DisplayMode mode) async {
    await ThemeModeStore.setMode(mode);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'وضع الشاشة',
            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark, height: 1.4),
          ),
          const SizedBox(height: F.s8),
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              for (final mode in DisplayMode.values)
                _ModeChip(
                  key: ValueKey('display-mode-${mode.wire}'),
                  label: mode.label,
                  selected: ThemeModeStore.mode == mode,
                  onTap: () => _pick(mode),
                ),
            ],
          ),
          const SizedBox(height: F.s4),
          Text(
            // الجملة بتقول اللي «تلقائي» بيعمله — والتحية بتمشي مع الوقت
            // الحقيقي دايماً مهما اخترت
            'تلقائي: نهاري من الشروق للغروب، وليلي بالليل.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
        ],
      );
}

/// شريحة هادية بنص حبر وحد أخضر للمختارة — **مش `AnchorChip` الدهبي**:
/// الدهبي معناه «محتاجك دلوقتي»، وإعداد شاشة مش كده؛ والودجت دي بتتحط على
/// شاشة الابن كمان، وحارس تباين الليل عنده بيقيس النص على أرضية الكارت.
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onTap, super.key});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: Material(
          color: selected ? F.green.withValues(alpha: 0.14) : F.railGround,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusChip),
            side: BorderSide(color: selected ? F.green : F.line, width: selected ? 2 : 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusChip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: F.s12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                ),
              ),
            ),
          ),
        ),
      );
}
