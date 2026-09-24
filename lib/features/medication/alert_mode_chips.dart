import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/escalation/alert_mode.dart';

/// **«نوع التنبيه» — صف واحد من شرايح كبيرة، على iPhone SE كمان.**
///
/// نفس الصف في الإعدادات (تلات شرايح: الافتراضي للجهاز) وعلى فورم الدوا
/// (أربع شرايح: «الافتراضي» = زي الجهاز). الشرايح متساوية العرض
/// (`Expanded`) عشان أربعة يقعدوا في ٣٤٣ بكسل، والخط ١٧ — الحد الأدنى
/// اللي القاعدة بتسمح بيه — عشان «مرة واحدة» تدخل من غير ما تتقصّ.
/// الذهبي = المختار، نفس معناه في كل التطبيق. وتحت الصف سطر بيشرح
/// المختار — الاسم لوحده («مستمر») ما بيقولش قد إيه.
class AlertModeChips extends StatelessWidget {
  const AlertModeChips({
    required this.value,
    required this.onChanged,
    this.allowDefault = false,
    this.defaultMode,
    super.key,
  });

  /// null = «الافتراضي» (بس لما [allowDefault]).
  final AlertMode? value;
  final ValueChanged<AlertMode?> onChanged;

  /// شريحة «الافتراضي» في الأول — على فورم الدوا، مش في الإعدادات.
  final bool allowDefault;

  /// إعداد الجهاز — عشان سطر الشرح يقول «الافتراضي» بيعمل إيه دلوقتي.
  final AlertMode? defaultMode;

  static const String defaultLabel = 'الافتراضي';

  @override
  Widget build(BuildContext context) {
    final effective = value ?? defaultMode ?? AlertMode.standard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (allowDefault) ...[
              Expanded(
                child: _ModeChip(
                  key: const ValueKey('alert-mode-default'),
                  label: defaultLabel,
                  selected: value == null,
                  onTap: () => onChanged(null),
                ),
              ),
              const SizedBox(width: F.s6),
            ],
            for (final mode in AlertMode.values) ...[
              Expanded(
                child: _ModeChip(
                  key: ValueKey('alert-mode-${mode.name}'),
                  label: mode.label,
                  selected: value == mode,
                  onTap: () => onChanged(mode),
                ),
              ),
              if (mode != AlertMode.values.last) const SizedBox(width: F.s6),
            ],
          ],
        ),
        const SizedBox(height: F.s8),
        Text(
          value == null && allowDefault
              ? 'زي إعداد الجهاز («${effective.label}»): ${effective.hint}'
              : effective.hint,
          key: const ValueKey('alert-mode-hint'),
          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onTap, super.key});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: Material(
          color: selected ? F.gold : F.railGround,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusChip),
            side: BorderSide(color: selected ? F.gold : F.line, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusChip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: F.s4),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
