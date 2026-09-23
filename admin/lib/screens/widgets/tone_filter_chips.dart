import 'package:flutter/material.dart';

import '../../format/grouped.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'status_cues.dart';

/// فلتر الحالة على الحسابات: «الكل» أو حالة واحدة.
enum ToneFilter {
  all,
  silent,
  alarm,
  warn,
  quiet;

  RowTone? get tone => switch (this) {
        ToneFilter.all => null,
        ToneFilter.silent => RowTone.silent,
        ToneFilter.alarm => RowTone.alarm,
        ToneFilter.warn => RowTone.warn,
        ToneFilter.quiet => RowTone.quiet,
      };

  static ToneFilter of(RowTone tone) => switch (tone) {
        RowTone.silent => ToneFilter.silent,
        RowTone.alarm => ToneFilter.alarm,
        RowTone.warn => ToneFilter.warn,
        RowTone.quiet => ToneFilter.quiet,
      };

  String get label => tone == null ? 'الكل' : toneWord(tone!);
}

/// حبّات الفلتر بعدّاداتها. **العدّادات بتعكس البحث الحالي** عبر كل
/// الحالات — الرقم على «تنبيه» هو تنبيهات اللي اسمهم فيه اللي كتبته.
class ToneFilterChips extends StatelessWidget {
  const ToneFilterChips({
    required this.counts,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final Map<ToneFilter, int> counts;
  final ToneFilter selected;
  final ValueChanged<ToneFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: F.s8,
      runSpacing: F.s8,
      children: [
        for (final filter in ToneFilter.values)
          _Chip(
            filter: filter,
            count: counts[filter] ?? 0,
            selected: filter == selected,
            onTap: () => onSelect(filter),
          ),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({required this.filter, required this.count, required this.selected, required this.onTap});

  final ToneFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tone = widget.filter.tone;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: motionDuration(context, Motion.quick),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: F.s12),
          decoration: BoxDecoration(
            color: widget.selected ? F.greenTint : F.fieldGround,
            border: Border.all(color: widget.selected || _hover ? F.green : F.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tone != null) ...[
                Icon(toneIcon(tone), size: 15, color: toneColour(tone)),
                const SizedBox(width: F.s6),
              ],
              Text(
                widget.filter.label,
                style: TextStyle(
                  fontFamily: F.bodyFamily,
                  fontSize: F.careTextSize,
                  fontWeight: FontWeight.w600,
                  color: F.ink,
                ),
              ),
              const SizedBox(width: F.s6),
              Text(
                arabicGrouped(widget.count),
                style: TextStyle(
                  fontFamily: F.bodyFamily,
                  fontSize: F.careTextSize,
                  fontWeight: FontWeight.w500,
                  color: F.mutedDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
