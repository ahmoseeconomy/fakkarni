import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/medication/medication_purpose.dart';

/// **مجموعات «أدويتك»** — الأدوية متجمّعة بالغرض زي التصميم (٤ أكتوبر ٢٠٢٦).
///
/// التلاتة اللي في التصميم بألوانه بالظبط: «للقلب والضغط» وردي بقلب أحمر
/// (استثناء المالك من «الأحمر للطوارئ» — الملف ده بس)، «للسكر» أزرق بنقطة،
/// «للعين والجلد» أخضر بعين. الباقي بأيقونة مناسبة وأرضية هادية. اللي
/// ما اتقالش لإيه في «من غير تصنيف»، والموقوف في «موقوفة» آخر الشاشة.
///
/// النص فوق الأرضية `ink` في كل المجموعات — اللون للأيقونة والأرضية بس.
enum MedGroup {
  heartPressure('للقلب والضغط', Icons.favorite),
  sugar('للسكر', Icons.water_drop),
  eyeSkin('للعين والجلد', Icons.visibility_outlined),
  cholesterol('للكوليسترول', Icons.bubble_chart_outlined),
  stomach('للمعدة والقولون', Icons.restaurant_outlined),
  vitamins('فيتامينات', Icons.eco_outlined),
  antibiotic('مضاد حيوي', Icons.shield_outlined),
  other('حاجة تانية', Icons.medication_outlined),
  unclassified('من غير تصنيف', Icons.category_outlined),
  stopped('موقوفة', Icons.pause_circle_outline);

  const MedGroup(this.label, this.icon);

  final String label;
  final IconData icon;

  /// المجموعة بتاعة غرض — null = «من غير تصنيف».
  static MedGroup of(MedicationPurpose? purpose) => switch (purpose) {
        MedicationPurpose.heart || MedicationPurpose.pressure => heartPressure,
        MedicationPurpose.sugar => sugar,
        MedicationPurpose.eye || MedicationPurpose.skin => eyeSkin,
        MedicationPurpose.cholesterol => cholesterol,
        MedicationPurpose.stomach => stomach,
        MedicationPurpose.vitamins => vitamins,
        MedicationPurpose.antibiotic => antibiotic,
        MedicationPurpose.other => other,
        null => unclassified,
      };

  /// لون الأيقونة.
  Color get ink => switch (this) {
        heartPressure => F.medGroupHeartInk,
        sugar => F.medGroupSugarInk,
        eyeSkin => F.green,
        cholesterol => F.medGroupCholesterolInk,
        stomach => F.medGroupStomachInk,
        vitamins => F.medGroupVitaminsInk,
        antibiotic => F.medGroupAntibioticInk,
        other || unclassified || stopped => F.mutedDark,
      };

  /// أرضية العنوان.
  Color get tint => switch (this) {
        heartPressure => F.medGroupHeartTint,
        sugar => F.medGroupSugarTint,
        eyeSkin => F.medGroupEyeSkinTint,
        cholesterol => F.medGroupCholesterolTint,
        stomach => F.medGroupStomachTint,
        vitamins => F.medGroupVitaminsTint,
        antibiotic => F.medGroupAntibioticTint,
        other || unclassified => F.cardGround,
        stopped => F.railGround,
      };
}

/// عنوان المجموعة: شريط بأرضية المجموعة، الكلمة والأيقونة.
class MedGroupHead extends StatelessWidget {
  const MedGroupHead(this.group, {super.key});

  final MedGroup group;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: ValueKey('med-group-${group.name}'),
        decoration: BoxDecoration(
          color: group.tint,
          borderRadius: BorderRadius.circular(F.radiusCard * 2),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: F.s18, vertical: F.s12),
          child: Row(
            children: [
              Icon(group.icon, color: group.ink, size: 30),
              const SizedBox(width: F.s12),
              Expanded(
                child: Text(
                  group.label,
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.sectionHeadSize + 3,
                    fontWeight: FontWeight.w800,
                    color: F.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// شريحة الغرض على صف الدوا — «للضغط» بأيقونة مجموعته. **مش دهبي**: الدهبي
/// لـ«محتاجك دلوقتي» بس؛ الشريحة أرضية المجموعة الهادية وحد خفيف.
class MedPurposeChip extends StatelessWidget {
  const MedPurposeChip(this.purpose, {this.neutral = false, super.key});

  final MedicationPurpose purpose;

  /// برّه «أدويتك» (كارت «الجرعة الجاية»): أيقونة وأرضية هاديين — استثناء
  /// القلب الأحمر للمجموعات على «أدويتك» بس (المالك).
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final group = MedGroup.of(purpose);
    return DecoratedBox(
      key: ValueKey('purpose-chip-${purpose.name}'),
      decoration: BoxDecoration(
        color: neutral ? F.railGround : group.tint,
        borderRadius: BorderRadius.circular(F.radiusCard * 2),
        border: Border.all(color: F.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(group.icon, size: 20, color: neutral ? F.mutedDark : group.ink),
            const SizedBox(width: F.s6),
            Flexible(
              child: Text(
                purpose.label,
                style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
