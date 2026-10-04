import 'package:flutter/material.dart';

import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../domain/medication/medicine_form.dart';

/// **رسمة نوع الدوا** — بدل الأيقونة لما مفيش صورة للدوا (الخيار ب، قرار
/// المالك ٤ أكتوبر ٢٠٢٦).
///
/// رسمة واحدة لكل [MedicineForm] (`assets/med_types/`، نسخ متصغّرة من رسومات
/// المالك بـ`tool/make_med_type_art.py`)، و«تاني» أو من غير نوع = `generic`.
/// **مفيش ولا حرف جوّه الصورة**: الاسم بيرسمه التطبيق فوقها، فمفيش رسمة
/// بتقول تركيز أو ماركة غير اللي الراجل كتبه.
///
/// الاسم بيترسم على **الرسومات الكبيرة بس** ([nameMinSize]): على رسمة ٥٦
/// كان هيبقى ٧ بكسل، والقاعدة إن مفيش نص تحت ١٧. والاسم كامل مكتوب جنب
/// الرسمة في كل مكان، فهنا ممكن يلفّ سطرين أو ينتهي بـ«…».
class MedTypeArt extends StatelessWidget {
  const MedTypeArt({required this.form, required this.size, this.name, super.key});

  final MedicineForm? form;
  final double size;

  /// الاسم زي ما هو متخزّن («Concor 5 mg») — بيتكتب بس لو [size] ≥ [nameMinSize].
  final String? name;

  /// أصغر رسمة بيتكتب عليها الاسم: لوحة الاسم ٧٤٪ من العرض، فده أقل مقاس
  /// بيشيل «Concor 5 mg» بخط ١٧ في سطر.
  static const nameMinSize = 150.0;

  /// عرض لوحة الاسم من عرض الرسمة.
  static const labelWidthFraction = 0.74;

  static String assetFor(MedicineForm? form) => 'assets/med_types/${_file(form)}.png';

  static String _file(MedicineForm? form) => switch (form) {
        MedicineForm.tablet => 'tablet',
        MedicineForm.capsule => 'capsule',
        MedicineForm.injection => 'injection',
        MedicineForm.ointment => 'ointment',
        MedicineForm.syrup => 'syrup',
        MedicineForm.drops => 'drops',
        MedicineForm.inhaler => 'inhaler',
        MedicineForm.suppository => 'suppository',
        MedicineForm.other || null => 'generic',
      };

  /// نص لوحة الاسم (كسر من المربع، من الشمال ومن فوق) — على وش العلبة أو
  /// جسم الإزازة، متقاس على الرسومات بعد التأطير.
  static Offset labelCenterFor(MedicineForm? form) => switch (form) {
        MedicineForm.tablet => const Offset(0.50, 0.43),
        MedicineForm.capsule => const Offset(0.56, 0.42),
        MedicineForm.injection => const Offset(0.51, 0.44),
        MedicineForm.ointment => const Offset(0.50, 0.50),
        MedicineForm.syrup => const Offset(0.45, 0.55),
        MedicineForm.drops => const Offset(0.50, 0.56),
        MedicineForm.inhaler => const Offset(0.42, 0.46),
        MedicineForm.suppository => const Offset(0.50, 0.38),
        MedicineForm.other || null => const Offset(0.55, 0.56),
      };

  bool get showsName => name != null && name!.trim().isNotEmpty && size >= nameMinSize;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    final center = labelCenterFor(form);
    final labelWidth = size * labelWidthFraction;
    final left = (center.dx * size - labelWidth / 2).clamp(0.0, size - labelWidth);
    return ExcludeSemantics(
      child: SizedBox(
        key: ValueKey('med-type-art-${_file(form)}'),
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Image.asset(
                assetFor(form),
                fit: BoxFit.contain,
                cacheWidth: (size * dpr).round(),
                // أصل ناقص ما يكسرش الصف — مربع فاضي بنفس المقاس
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (showsName)
              Positioned(
                left: left,
                width: labelWidth,
                top: center.dy * size,
                child: FractionalTranslation(
                  translation: const Offset(0, -0.5),
                  child: _NameLabel(name!.trim()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NameLabel extends StatelessWidget {
  const _NameLabel(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: const ValueKey('med-type-art-name'),
        decoration: BoxDecoration(
          color: F.medArtLabelGround,
          borderRadius: BorderRadius.circular(F.radiusChip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: F.s8, vertical: F.s6),
          child: Text(
            name,
            textDirection: nameDirection(name),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: F.minTextSize,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: F.medArtLabelInk,
            ),
          ),
        ),
      );
}
