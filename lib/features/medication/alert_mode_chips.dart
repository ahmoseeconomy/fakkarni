import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/escalation/alert_mode.dart';

/// **«نوع التنبيه» — شرايح كبيرة، اتنين في الصف، على iPhone SE كمان.**
///
/// نفس الشرايح في الإعدادات (تلاتة: الافتراضي للجهاز) وعلى فورم الدوا
/// (أربعة: «الافتراضي» = زي الجهاز). كانت صف واحد متساوي العرض والخط ١٧
/// «عشان «مرة واحدة» تدخل من غير ما تتقصّ» — **وما دخلتش**: أربع شرايح
/// في ٣٤٣ بكسل بتدّي ~٧٨ للواحدة، و«مرة واحدة» بخط ١٧ w700 أعرض،
/// والفيض `visible` كان بيترسم تحت الشريحة الجنبية فأول حرف بيتقصّ
/// (مراجعة المالك على الجهاز، ٥ أكتوبر ٢٠٢٦ مساءً). الحل نفس سابقة شبكة
/// الأكل: **اتنين في الصف** (٤ ← ٢×٢، ٣ ← ٢+١ بنفس العرض)، فالكلمة
/// واسعة حتى بخط ×١٫٣ — واختبار هندسي بيقيس عرض الكلمة ضد عرض شريحتها.
/// الذهبي = المختار، نفس معناه في كل التطبيق. وتحت الشرايح سطر بيشرح
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
    final chips = <Widget>[
      if (allowDefault)
        _ModeChip(
          key: const ValueKey('alert-mode-default'),
          label: defaultLabel,
          selected: value == null,
          onTap: () => onChanged(null),
        ),
      for (final mode in AlertMode.values)
        _ModeChip(
          key: ValueKey('alert-mode-${mode.name}'),
          label: mode.label,
          selected: value == mode,
          onTap: () => onChanged(mode),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // اتنين في الصف — والعدد الفردي آخره شريحة بنص العرض (مش بالعرض
        // كله): نفس إيقاع الشبكة، والفراغ الجنبي بيقول إنها آخر واحدة.
        for (var i = 0; i < chips.length; i += 2) ...[
          if (i > 0) const SizedBox(height: F.s6),
          Row(
            children: [
              Expanded(child: chips[i]),
              const SizedBox(width: F.s6),
              Expanded(child: i + 1 < chips.length ? chips[i + 1] : const SizedBox.shrink()),
            ],
          ),
        ],
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
                  // «visible» كان بيرسم الفايض تحت الشريحة الجنبية فأول حرف
                  // يتقصّ في صمت — «…» بيقول فيه مشكلة، والاختبار الهندسي
                  // بيمنع توصل أصلاً.
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    fontWeight: FontWeight.w700,
                    color: selected ? F.onGold : F.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
