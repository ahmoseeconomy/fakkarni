import 'package:flutter/material.dart';

import '../../domain/medication/medicine_form.dart';

/// **رسمة نوع الدوا** — بدل الأيقونة لما مفيش صورة للدوا (الخيار ب، قرار
/// المالك ٤ أكتوبر ٢٠٢٦).
///
/// رسمة واحدة لكل [MedicineForm] (`assets/med_types/`، نسخ متصغّرة من رسومات
/// المالك بـ`tool/make_med_type_art.py`)، و«تاني» أو من غير نوع = `generic`.
///
/// **الرسمة نضيفة زي الأصل، من غير أي كلام عليها** (المالك، بعد ما شافها على
/// الموبايل): لوحة الاسم البيضا كانت بتغطّي الرسمة. الاسم مكتوب كبير جنبها
/// في كل مكان بتظهر فيه. والصور نفسها مفيهاش ولا حرف، فمفيش رسمة بتقول تركيز
/// أو ماركة غير اللي الراجل كتبه.
class MedTypeArt extends StatelessWidget {
  const MedTypeArt({required this.form, required this.size, super.key});

  final MedicineForm? form;
  final double size;

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

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    // زينة — الاسم مكتوب جنبها، فقارئ الشاشة ما يقولش حاجة زيادة
    return ExcludeSemantics(
      child: SizedBox(
        key: ValueKey('med-type-art-${_file(form)}'),
        width: size,
        height: size,
        child: Image.asset(
          assetFor(form),
          fit: BoxFit.contain,
          cacheWidth: (size * dpr).round(),
          // أصل ناقص ما يكسرش الصف — مربع فاضي بنفس المقاس
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
