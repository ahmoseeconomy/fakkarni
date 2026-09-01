import 'package:drift/drift.dart';

import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../dose_state.dart';
import 'converters.dart';

// ملاحظة على الأسماء: كلاسات drift المولّدة بتاخد اسم الجدول بالمفرد، وده
// كان هيصطدم بـDayRoutine و DoseSchedule بتوع الدومين. عشان كده الصفوف
// كلها بلاحقة Row، والدومين بيفضل هو صاحب الاسم الأصلي.

@DataClassName('PatientRow')
class Patients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// خانة المريض في نطاق أرقام الإشعارات (0 → maxPatients-1).
  ///
  /// **مش هي `id`.** الـ`id` بيعدّ لفوق على طول وعمره ما بيرجع، فبعد ١٢٨
  /// صف بيخرج برّه النطاق. الخانة دي بتترد لما المريض يتشال، وبتفضل
  /// صغيرة وثابتة طول عمر المريض.
  IntColumn get notificationSlot =>
      integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// مينفعش مريضين ياخدوا نفس الخانة — ده بالظبط التصادم اللي بنمنعه.
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {notificationSlot},
      ];
}

@DataClassName('DayRoutineRow')
class DayRoutines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patientId =>
      integer().references(Patients, #id, onDelete: KeyAction.cascade)();

  /// دقايق من منتصف الليل (0 → 1439) — نفس تمثيل [MinuteOfDay].
  IntColumn get wakeMinutes => integer()();
  IntColumn get breakfastMinutes => integer()();
  IntColumn get lunchMinutes => integer()();
  IntColumn get dinnerMinutes => integer()();
  IntColumn get sleepMinutes => integer()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// روتين واحد للمريض الواحد.
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {patientId},
      ];
}

@DataClassName('MedicationRow')
class Medications extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patientId =>
      integer().references(Patients, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get amountLabel => text().nullable()();

  /// الورقة ما قالتش الجرعة. مسجّل عشان نسأل عنه بعدين — مجهول اتكتب
  /// ونقدر نتابعه كويس؛ مجهول اتنسي في صمت لأ.
  BoolColumn get amountUnknown =>
      boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();

  /// null معناها الدوا لسه شغّال.
  ///
  /// العمود ده ما بيتكتبش غير من `stopMedication` — يعني بإيد إنسان. مفيش
  /// أي مسار في التطبيق بيوقف دوا من نفسه.
  DateTimeColumn get stoppedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// نوع توقيت الجرعة — العمود اللي بيقول الصف ده مرساة ولا ساعة ثابتة.
enum DoseTimingKind {
  /// الافتراضي: مرساة + إزاحة.
  anchor,

  /// الاستثناء الموثّق: ساعة ثابتة، محفوظة في [FixedTimings].
  fixed,
}

/// جدول الجرعات — **مفيش فيه عمود ساعة**.
///
/// الصف بيقول نوعه في [timingKind]. لو مرساة، الساعة بتتحسب وقت العرض من
/// روتين المريض. لو ساعة ثابتة، الدقيقة عايشة في جدول [FixedTimings]
/// المنفصل — عمود الساعة بيخص النوع ده لوحده، مش كل جرعة. لو حد ضاف عمود
/// وقت هنا، اختبار `مفيش ولا عمود ساعة في جدول الجرعات` بيقع فوراً.
@DataClassName('DoseScheduleRow')
class DoseSchedules extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get medicationId =>
      integer().references(Medications, #id, onDelete: KeyAction.cascade)();

  /// الافتراضي مرساة — وده اللي الصفوف القديمة بتاخده في الترحيل.
  TextColumn get timingKind => textEnum<DoseTimingKind>()
      .withDefault(Constant(DoseTimingKind.anchor.name))();

  /// المرساة — null بس لو [timingKind] ساعة ثابتة.
  TextColumn get anchor => textEnum<DayAnchor>().nullable()();

  /// بالسالب = قبل المرساة، بالموجب = بعدها. null لو ساعة ثابتة.
  IntColumn get offsetMinutes => integer().nullable()();

  TextColumn get repeat => textEnum<DoseRepeat>()();

  TextColumn get startDate => text().map(const DateOnlyConverter())();

  /// null = مدة مفتوحة. ما بيتحطّش تخميناً أبداً.
  IntColumn get durationDays => integer().nullable()();
}

/// الساعة الثابتة لجرعة — صف واحد لكل جرعة نوعها `fixed`.
///
/// جدول منفصل عن قصد: الساعة بتخص النوع ده بس، فمفيش عمود وقت بيقعد فاضي
/// على كل جرعة مرساة ويغري حد يكتب فيه.
@DataClassName('FixedTimingRow')
class FixedTimings extends Table {
  IntColumn get doseScheduleId =>
      integer().references(DoseSchedules, #id, onDelete: KeyAction.cascade)();

  /// دقايق من منتصف الليل (0 → 1439) — نفس تمثيل [MinuteOfDay].
  IntColumn get minuteOfDay => integer()();

  @override
  Set<Column<Object>> get primaryKey => {doseScheduleId};
}

/// حدث جرعة في يوم روتين معيّن.
///
/// مفتاح الحدث هو (الجرعة، يوم الروتين) — **مش الساعة**. يعني لو المريض
/// غيّر معاد فطاره النهاردة، الحدث بيفضل هو هو وساعته بس هي اللي بتتحرك.
/// [scheduledAt] تسجيل لواقعة حصلت، مش مصدر للجدولة.
@DataClassName('DoseEventRow')
class DoseEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get doseScheduleId =>
      integer().references(DoseSchedules, #id, onDelete: KeyAction.cascade)();

  TextColumn get routineDay => text().map(const DateOnlyConverter())();

  /// الساعة اللي كانت مستحقة فيها وقت ما الحدث اتسجّل.
  DateTimeColumn get scheduledAt => dateTime()();

  TextColumn get state => textEnum<DoseState>()();
  DateTimeColumn get actedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {doseScheduleId, routineDay},
      ];
}
