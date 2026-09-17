import 'package:flutter/material.dart';

import '../theme/theme_mode_store.dart';
import '../theme/tokens.dart';

/// مفتاح الوضع الليلي في الشريط العلوي — جنب «طوارئ».
///
/// زرار حقيقي: بيقلب التطبيق كله فوراً وبيتخزّن على الموبايل. الأيقونة
/// بتقول اللي هيحصل لو دست (قمر في النهار، شمس في الليل)، والكلمة في
/// `Semantics` و`tooltip` — مساحة الشريط ما تسعش كلمة مكتوبة جنب «طوارئ».
class DarkModeToggle extends StatelessWidget {
  const DarkModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = F.isDark;
    final label = dark ? 'وضع نهاري' : 'وضع ليلي';
    return Semantics(
      label: label,
      button: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: F.s4),
        child: SizedBox(
          width: F.minTapTarget,
          height: F.minTapTarget,
          child: IconButton(
            key: const ValueKey('dark-mode-toggle'),
            tooltip: label,
            onPressed: () => ThemeModeStore.set(on: !dark),
            icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 24),
            color: F.ink,
          ),
        ),
      ),
    );
  }
}
