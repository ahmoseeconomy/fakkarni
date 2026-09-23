import 'package:flutter/material.dart';

import '../../theme/theme_mode_store.dart';
import '../../theme/tokens.dart';

/// زرار الوضع الليلي في الشريط العلوي — أيقونة **وكلمة**، والكلمة بتقول
/// هيعمل إيه لما تدوس («ليلي» وإنت في النهار).
class DarkModeToggle extends StatelessWidget {
  const DarkModeToggle({super.key});

  static const toggleKey = Key('dark-mode-toggle');

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.maybeOf(context);
    final dark = F.isDark;
    return TextButton.icon(
      key: toggleKey,
      onPressed: controller == null ? null : () => controller.toggle(),
      style: TextButton.styleFrom(
        foregroundColor: F.onDark,
        minimumSize: const Size(0, F.careTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: F.s12),
      ),
      icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 18),
      label: Text(
        dark ? 'نهاري' : 'ليلي',
        style: const TextStyle(
          fontFamily: F.bodyFamily,
          fontSize: F.careTextSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
