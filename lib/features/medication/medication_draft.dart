import '../../domain/escalation/alert_mode.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/scheduling/dose_schedule.dart';

/// دوا زي ما الإنسان ظبّطه — **ولسه ما اتحفظش**.
///
/// ده اللي [AddMedicationScreen] بترجّعه في وضع المسوّدة: شاشة مراجعة
/// الروشتة بتعدّل سطورها في الذاكرة، والكتابة كلها بتحصل مرة واحدة عند
/// «تمام، ظبّطهم». في وضع الحفظ العادي بترجّع نفس الشكل **بعد** ما تكتب،
/// عشان اللي نادى يبقى عنده نوع واحد يتعامل معاه (null = رجع من غير حفظ).
class MedicationDraft {
  const MedicationDraft({
    required this.name,
    required this.timings,
    this.amountLabel,
    this.amountUnknown = false,
    this.durationDays,
    this.alertMode,
    this.purpose,
    this.instructions,
    this.startDate,
    this.once = false,
  });

  final String name;

  /// جرعة واحدة على الأقل — الشاشة بتفرض الأرضية دي.
  final List<DoseTiming> timings;

  /// null + [amountUnknown] = الورقة ما قالتش الجرعة. **مش بنخترع قيمة.**
  final String? amountLabel;
  final bool amountUnknown;

  /// null = مفتوحة، زي ما الورقة سابتها.
  final int? durationDays;

  /// نوع التنبيه — null = «الافتراضي» (إعداد الجهاز).
  final AlertMode? alertMode;

  /// «الدوا ده لإيه؟» — null = ما قالش.
  final MedicationPurpose? purpose;

  /// «تعليمات» حرّة — null = مفيش.
  final String? instructions;

  /// «هتبدأ الدوا من إمتى؟» — null = النهارده (يوم الحفظ).
  final DateTime? startDate;

  /// «مرة واحدة» (`DoseRepeat.once`) — المدة ساعتها null.
  final bool once;
}
