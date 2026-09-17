import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'emergency_card_screen.dart';

/// بيل «طوارئ» في الشريط العلوي (المخطط ٤) — **أحمر مصمت**.
///
/// عايش في `features/emergency/` عن قصد: الأحمر مسموح هنا وبس
/// (`red_only_in_emergency_test`)، والشِل بيستعمل الودجت — مش بيلوّن بنفسه.
///
/// ده المكان الوحيد اللي الأحمر بيظهر فيه برّه شاشتي الطوارئ، ومعناه بيفضل
/// لأن مفيش حاجة تانية بتاخده: الجرعة الفايتة ذهبي، والكروت ذهبي.
class EmergencyPill extends StatelessWidget {
  const EmergencyPill({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        // أصغر بالشكل مش بالمساحة: الحشو والخط والأيقونة صغروا، والارتفاع
        // فضل ٥٦ لأن «حد اللمس ٥٦» قاعدة مكتوبة لإيد عندها ٧٢ سنة — وده
        // الزرار اللي بيتضغط وقت الخضّة.
        height: F.minTapTarget,
        child: FilledButton.icon(
          key: const ValueKey('emergency-shortcut'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const EmergencyCardScreen()),
          ),
          icon: const Icon(Icons.warning_amber_rounded, size: 20),
          label: const Text('طوارئ'),
          style: FilledButton.styleFrom(
            // الثيم بيدّي الزراير عرض كامل — في الشريط العلوي لأ
            minimumSize: const Size(0, F.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.s10),
            textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
            backgroundColor: F.red,
            foregroundColor: F.onRed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusChip)),
          ),
        ),
      );
}
