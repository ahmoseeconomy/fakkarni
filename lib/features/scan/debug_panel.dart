import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// نص خام للمطوّر — نسخة التطوير بس (اللي بيندهه بيتحقق من kDebugMode).
///
/// الحد الأدنى للخط بيتطبّق هنا كمان، عشان ما يبقاش في استثناء «مش للمريض»
/// بيتسحب على الشاشات التانية.
class DebugPanel extends StatelessWidget {
  const DebugPanel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: F.railGround,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: SelectableText(
          text,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: F.minTextSize,
            color: F.mutedDark,
            fontFamily: F.monoFamily,
            fontFamilyFallback: F.monoFallback,
            height: 1.5,
          ),
        ),
      );
}
