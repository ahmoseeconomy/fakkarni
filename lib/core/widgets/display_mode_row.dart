import 'package:flutter/material.dart';

import '../theme/theme_mode_store.dart';
import '../theme/tokens.dart';

/// «وضع الشاشة» — صف واحد بالاختيار الحالي وسهم، بيفتح صفحة التلات
/// اختيارات (المالك، ٥ أكتوبر مساءً — كانت تلات شرايح جوّه الإعدادات).
/// ودجت واحدة للأب ولابنه: إعداد **الموبايل ده**، مش بيانات حد.
class DisplayModeRow extends StatefulWidget {
  const DisplayModeRow({super.key});

  @override
  State<DisplayModeRow> createState() => _DisplayModeRowState();
}

class _DisplayModeRowState extends State<DisplayModeRow> {
  Future<void> _open() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const DisplayModeScreen()));
    if (mounted) setState(() {}); // الاختيار اتغيّر جوّه — الصف بيقول الجديد
  }

  @override
  Widget build(BuildContext context) => Material(
    // FCard مش Material — والصف محتاجها للمس
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('display-mode-row'),
      onTap: _open,
      borderRadius: BorderRadius.circular(F.radiusCard),
      child: Container(
        constraints: const BoxConstraints(minHeight: F.minTapTarget),
        padding: const EdgeInsets.symmetric(vertical: F.s8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'وضع الشاشة',
                style: TextStyle(
                  fontSize: F.minBodySize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
            ),
            Text(
              ThemeModeStore.mode.label,
              key: const ValueKey('display-mode-current'),
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
            ),
            const SizedBox(width: F.s6),
            Icon(Icons.chevron_left, size: 24, color: F.muted),
          ],
        ),
      ),
    ),
  );
}

/// صفحة الاختيار — التلات أوضاع تحت بعض، كل واحد بكلمته وجملته، والحالي
/// معلّم ✓. الاختيار بيتطبّق فوراً وبيتخزّن ([ThemeModeStore.setMode])؛
/// «تلقائي» بيتبع الشروق والغروب الحقيقيين عند الفتح والرجوع للمقدمة.
class DisplayModeScreen extends StatefulWidget {
  const DisplayModeScreen({super.key});

  @override
  State<DisplayModeScreen> createState() => _DisplayModeScreenState();
}

class _DisplayModeScreenState extends State<DisplayModeScreen> {
  Future<void> _pick(DisplayMode mode) async {
    await ThemeModeStore.setMode(mode);
    if (mounted) setState(() {});
  }

  String _hint(DisplayMode mode) => switch (mode) {
    DisplayMode.auto => 'نهاري من الشروق للغروب، وليلي بالليل — لوحده.',
    DisplayMode.light => 'الشاشة نهاري دايماً.',
    DisplayMode.dark => 'الشاشة ليلي دايماً.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: F.pageGround,
    appBar: AppBar(title: const Text('وضع الشاشة')),
    body: ListView(
      padding: const EdgeInsets.all(F.gap),
      children: [
        for (final mode in DisplayMode.values) ...[
          _ModeOption(
            key: ValueKey('display-mode-${mode.wire}'),
            label: mode.label,
            hint: _hint(mode),
            selected: ThemeModeStore.mode == mode,
            onTap: () => _pick(mode),
          ),
          const SizedBox(height: F.s12),
        ],
        Text(
          // التحية بتمشي مع الوقت الحقيقي دايماً — مهما اخترت
          'التحية («صباح الخير» و«مساء الخير») بتمشي مع الشمس الحقيقية دايماً.',
          style: TextStyle(
            fontSize: F.minTextSize,
            color: F.mutedDark,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

/// اختيار واحد — كارت بكلمته وجملته، والمختار بحد أخضر و✓ (مش دهبي:
/// إعداد شاشة مش «محتاجك دلوقتي»).
class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? F.green.withValues(alpha: 0.10) : F.cardGround,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(F.radiusCard),
      side: BorderSide(
        color: selected ? F.green : F.line,
        width: selected ? 2 : 1,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(F.radiusCard),
      child: Padding(
        padding: const EdgeInsets.all(F.gap),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: F.minBodySize,
                      fontWeight: FontWeight.w800,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.s4),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: F.minTextSize,
                      color: F.mutedDark,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, size: 28, color: F.green),
          ],
        ),
      ),
    ),
  );
}
