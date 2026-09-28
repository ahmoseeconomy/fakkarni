import '../../domain/escalation/alert_mode.dart';
import '../../domain/medication/meal_relation.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/scheduling/day_pattern.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../files/med_photos.dart';
import '../repositories/medication_repository.dart';
import 'reminder_scheduler.dart';

/// **الطريق الوحيد اللي بيكتب دوا أو مواعيده — وبعده الجدولة، في نفس المكان.**
///
/// قبل كده كل شاشة كانت بتكتب في المستودع بنفسها وبعدين تنده `rescheduleAll`
/// بنفسها: «ضيف دوا»، مراجعة الروشتة، صورة العلبة، التعديل (ساعة، إضافة
/// جرعة، شيل جرعة، «كل كام ساعة»، الأيام، الإيقاف، الرجوع، الشيل)، وقايمة
/// «الأدوية». اتناشر مكان كل واحد لازم يفتكر الخطوة التانية لوحده. هنا:
/// الكتابة ← إعادة الجدولة، دايماً، ومن غير ما حد يفتكر.
///
/// **الإلغاء هو فرق الخطة**: أرقام الإشعارات مشتقة من الخانة (الدقيقة)، ودوائين
/// في نفس الدقيقة بيشاركوا رقم واحد — فإلغاء «أرقام الدوا ده» بإيدينا كان هيسكّت
/// الدوا التاني. `rescheduleAll` بيحسب الخطة من القاعدة وبيلغي كل رقم في نطاق
/// الجرعات مش في الخطة (الساعة القديمة بعد التعديل، الدوا الموقوف)، وبيجدول
/// الخطة كلها — ودلوقتي متسلسل، فجولتين ما بيدخلوش في بعض.
///
/// `test/app/medication_writes_guard_test.dart` بيوقّع لو أي ملف في
/// `lib/features` كتب في الأدوية أو المواعيد من غير الخدمة دي.
class MedicationSaveService {
  MedicationSaveService({required this.medications, required this.scheduler, this.clock});

  final MedicationRepository medications;
  final ReminderScheduler scheduler;

  /// «دلوقتي» للجدولة — سحبة تغييرات الممرض بتدّي ساعتها (الاختبارات بتثبّتها).
  final DateTime Function()? clock;

  Future<T> _thenSchedule<T>(Future<T> Function() write) async {
    final result = await write();
    await scheduler.rescheduleAll(now: clock?.call());
    return result;
  }

  /// دوا جديد بكل جرعاته — «ضيف دوا» (بالإيد، من صورة العلبة، من «كلّمني»).
  Future<int> add({
    required int patientId,
    required String name,
    required List<FixedTiming> timings,
    required DateTime startDate,
    String? amountLabel,
    bool amountUnknown = false,
    DoseRepeat repeat = DoseRepeat.daily,
    int? durationDays,
    String? activeIngredient,
    AlertMode? alertMode,
    MedicationPurpose? purpose,
    String? instructions,
    DayPattern days = DayPattern.everyDay,
    MealRelation? mealRelation,
  }) =>
      _thenSchedule(() => medications.addMedicationWithDoses(
          patientId: patientId,
          name: name,
          timings: timings,
          startDate: startDate,
          amountLabel: amountLabel,
          amountUnknown: amountUnknown,
          repeat: repeat,
          durationDays: durationDays,
          activeIngredient: activeIngredient,
          alertMode: alertMode,
          purpose: purpose,
          instructions: instructions,
          days: days,
          mealRelation: mealRelation,
        ));

  /// روشتة كاملة في معاملة واحدة — مراجعة الروشتة.
  Future<List<int>> addAll({
    required int patientId,
    required List<MedicationWrite> list,
    required DateTime startDate,
    Set<int> onceAt = const {},
  }) =>
      _thenSchedule(() => medications.addMedicationsWithDoses(
            patientId: patientId,
            medications: list,
            startDate: startDate,
            onceAt: onceAt,
          ));

  /// ساعة جرعة موجودة اتغيّرت — نفس الصف.
  Future<void> updateTiming(int scheduleId, FixedTiming timing) =>
      _thenSchedule(() => medications.updateTiming(scheduleId, timing));

  /// «أضف جرعة» لدوا موجود.
  Future<void> addDose(int medicationId, {required FixedTiming timing, required DateTime startDate, int? durationDays}) =>
      _thenSchedule(() => medications.addDoseSchedule(medicationId, timing: timing, startDate: startDate, durationDays: durationDays));

  /// «شيل» جرعة — إيقاف ناعم.
  Future<void> stopDose(int scheduleId) => _thenSchedule(() => medications.stopDoseSchedule(scheduleId));

  /// «كل كام ساعة» / «غيّر الأيام»: الجديد يتكتب الأول وبعدين القديم يتوقف —
  /// مفيش لحظة الدوا فيها من غير جرعة — وجدولة واحدة في الآخر.
  Future<void> replaceDoses(
    int medicationId, {
    required List<({FixedTiming timing, DateTime startDate, int? durationDays, DayPattern days})> add,
    required List<int> stop,
  }) =>
      _thenSchedule(() async {
        for (final d in add) {
          await medications.addDoseSchedule(medicationId,
              timing: d.timing, startDate: d.startDate, durationDays: d.durationDays, days: d.days);
        }
        for (final id in stop) {
          await medications.stopDoseSchedule(id);
        }
      });

  /// الجرعة والتعليمات والمدة — «احفظ» في التعديل. نص التذكير فيه الجرعة.
  Future<void> updateDetails(int medicationId, {required String amount, required String? instructions, required int? durationDays}) =>
      _thenSchedule(() async {
        await medications.updateAmount(medicationId, amount);
        await medications.updateDetails(medicationId, instructions: instructions, durationDays: durationDays);
      });

  /// الجرعة بس — تغيير من ممرض أو «تراجع» عليه (0035). نص التذكير فيه الجرعة.
  Future<void> updateAmount(int medicationId, String amount) =>
      _thenSchedule(() => medications.updateAmount(medicationId, amount));

  Future<void> setAlertMode(int medicationId, AlertMode? mode) =>
      _thenSchedule(() => medications.setAlertMode(medicationId, mode));

  /// كلمة الأكل — في متن الإشعار، فبيتعاد بناؤه.
  Future<void> setMealRelation(int medicationId, MealRelation? relation) =>
      _thenSchedule(() => medications.updateMealRelation(medicationId, relation));

  Future<void> stop(int medicationId) => _thenSchedule(() => medications.stopMedication(medicationId));

  Future<void> resume(int medicationId) => _thenSchedule(() => medications.resumeMedication(medicationId));

  /// «شيله خالص» — ومعاه صورته.
  Future<void> remove(int medicationId, MedPhotos photos) =>
      _thenSchedule(() => photos.removeMedication(medications, medicationId));

  /// شيل من غير صور (صحوة ما عندهاش مكان الصور) — نفس الشيل الناعم.
  Future<void> removePlain(int medicationId) => _thenSchedule(() => medications.removeMedication(medicationId));

  /// «تراجع» على شيل جاي من ممرض (0035): الدوا بيرجع لقوايمه — الجرعات
  /// اللي اتعلّمت `superseded` بترجع `pending` مع أول `materializeDay`.
  Future<void> unremove(int medicationId) => _thenSchedule(() => medications.unremoveMedication(medicationId));
}
