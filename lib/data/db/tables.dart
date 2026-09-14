import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../dose_state.dart';
import 'converters.dart';

/// هوية الصف للمزامنة — الجهاز هو اللي بيولّدها، عمرها ما تيجي من سيرفر.
///
/// الـid الرقمي تسلسل محلي: جهازين بيطلّعوا 1، 2، 3 لصفوف مختلفة، وأول
/// مزامنة في جدول مشترك بتخلط صفوف الغرباء في صمت. الـuuid هو الهوية
/// للمزامنة؛ الـid الرقمي سباكة داخلية لـSQLite والمفاتيح الأجنبية بتفضل
/// عليه. `clientDefault` عشان ولا نقطة إدخال تقدر تنسى — اللي لازم حد
/// يفتكره هيتنسي في يوم.
const _uuid = Uuid();

/// عام عشان الكود المولّد (part من app_database) يشوفه.
String newSyncUuid() => _uuid.v4();

/// ساعة المزامنة بالملّي ثانية — أعمدة int عادية مش dateTime عن قصد:
/// دقّة drift الافتراضية بالثواني، وتعديل في نفس ثانية الدفع كان هيبان
/// «نضيف» ويضيع. القاعدة: الصف متوسّخ لما synced_at_ms IS NULL أو أقدم
/// من updated_at_ms.
int nowMs() => DateTime.now().millisecondsSinceEpoch;

mixin SyncIdentity on Table {
  TextColumn get uuid => text().clientDefault(newSyncUuid).unique()();

  /// بتتصان من قاعدة البيانات نفسها (تريجرات في beforeOpen) — مش من نقاط
  /// النداء: اللي لازم حد يفتكره هيتنسي، والصف ده كان هيبطل يتزامن في صمت.
  IntColumn get updatedAtMs => integer().clientDefault(nowMs)();

  /// آخر updated_at_ms اتدفع للسحابة — null يعني عمره ما اتدفع.
  IntColumn get syncedAtMs => integer().nullable()();
}

// ملاحظة على الأسماء: كلاسات drift المولّدة بتاخد اسم الجدول بالمفرد، وده
// كان هيصطدم بـDayRoutine و DoseSchedule بتوع الدومين. عشان كده الصفوف
// كلها بلاحقة Row، والدومين بيفضل هو صاحب الاسم الأصلي.

@DataClassName('PatientRow')
class Patients extends Table with SyncIdentity {
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

  /// نسخة ٨ — الجنس (m/f) عشان الكلام يخاطبه صح. **محلي**: مش بيتدفع
  /// للسحابة (SyncService بيبعت uuid والاسم والخانة بس). null = ما اتسألش.
  TextColumn get sex => textEnum<Sex>().nullable()();

  /// نسخة ٨ — السن بالسنين. محلي، وnull = ما اتسألش.
  IntColumn get age => integer().nullable()();

  /// مينفعش مريضين ياخدوا نفس الخانة — ده بالظبط التصادم اللي بنمنعه.
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {notificationSlot},
      ];
}

@DataClassName('DayRoutineRow')
class DayRoutines extends Table with SyncIdentity {
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

/// الروتين الأصلي وقت ما اتفتح وضع رمضان — بيرجع بالحرف لما يتقفل.
///
/// وجود الصف هو «رمضان شغّال»؛ مفيش عمود boolean يقدر يختلف مع الصف.
/// **مش بيتزامن** عن قصد (مفيش SyncIdentity): الابن بيشوف الروتين
/// الساري، مش النسخة الاحتياطية بتاعة جهاز أبوه. والفطار والسحور محفوظين
/// هنا عشان يتحطّوا مرة واحدة.
@DataClassName('RoutineBackupRow')
class RoutineBackups extends Table {
  IntColumn get patientId =>
      integer().references(Patients, #id, onDelete: KeyAction.cascade)();

  /// الخمس مواعيد الأصلية زي ما كانت في day_routines بالظبط.
  IntColumn get wakeMinutes => integer()();
  IntColumn get breakfastMinutes => integer()();
  IntColumn get lunchMinutes => integer()();
  IntColumn get dinnerMinutes => integer()();
  IntColumn get sleepMinutes => integer()();

  IntColumn get iftarMinutes => integer()();
  IntColumn get suhoorMinutes => integer()();

  @override
  Set<Column<Object>> get primaryKey => {patientId};
}

/// تفضيلات الجهاز ده (D3.3): نمط كبار السن ودرجتين السلّم اللي بيتقفلوا.
///
/// صف واحد (`id = 1`)؛ من غير صف = الافتراضي (النمط العادي، والدرجات كلها
/// شغّالة). **مش بيتزامن** (مفيش SyncIdentity): الإعدادات دي تخص الموبايل
/// ده بس. في drift مش shared_preferences لأن عزلة الخلفية بتاعة «أخدته»
/// بتعيد الجدولة ولازم تقرا نفس القيم.
///
/// الدرجة الإلزامية (التذكير نفسه، وإشعار الابن من السيرفر) مالهاش عمود —
/// اللي مالوش مفتاح ما يتقفلش بالغلط.
@DataClassName('DevicePreferencesRow')
class DevicePreferences extends Table {
  IntColumn get id => integer()();
  BoolColumn get elderMode => boolean().withDefault(const Constant(false))();
  BoolColumn get rungFirstOn => boolean().withDefault(const Constant(true))();
  BoolColumn get rungSecondOn => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// بيانات الطوارئ (D3.4، المخطط ١٩ و٣٢) — اللي المريض أو أهله كتبوه بإيدهم.
///
/// **ولا عمود هنا بيتملا لوحده ولا بيتخمّن**: null = «لسه ما اتملاش». حد
/// عنده حساسية بنسلين وبطاقته بتقول حاجة تانية ده مش باج واجهة. الأدوية
/// الحالية مش هنا — بتتقرا من medications عشان ما يبقاش فيه نسختين تختلفوا.
///
/// SyncIdentity من الأول (قاعدة PHASE_D3) بس **مش بيتزامن**: SyncService
/// ما بيقراهوش. أرقام جهات الاتصال على الموبايل ده بس.
@DataClassName('EmergencyProfileRow')
class EmergencyProfile extends Table with SyncIdentity {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patientId =>
      integer().references(Patients, #id, onDelete: KeyAction.cascade).unique()();

  /// «O+» … «AB-» بالحرف اللاتيني زي ما بيتكتب في التحليل.
  TextColumn get bloodType => text().nullable()();
  TextColumn get allergies => text().nullable()();
  TextColumn get chronicConditions => text().nullable()();

  /// `[{name, phone, relation}]` — عمود JSON في نفس الجدول.
  TextColumn get contactsJson => text().withDefault(const Constant('[]'))();

  @override
  String get tableName => 'emergency_profile';
}

/// نوع السجل في الملف الصحي (D3.5).
enum RecordKind { imaging, visit, lab, prescription, booking }

/// الملف الصحي (D3.5، المخطط ٢٨ و١٣ و٢٩) — أشعة، زيارات، تحاليل، روشتات، حجوزات.
///
/// محلي بس، بأعمدة SyncIdentity من الأول (PHASE_D3) — SyncService ما بيقراهوش.
///
/// **الحذف ناعم**: `deletedAt` بيتحط والصف بيفضل باين مشطوب لحد ما يعدّي
/// ٣٠ يوم، وبعدها تنظيف فتح التطبيق بيمسحه نهائي. الوعد ده مكتوب
/// للمستخدم، فالتنظيف مش اختياري.
@DataClassName('RecordRow')
class Records extends Table with SyncIdentity {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get patientId =>
      integer().references(Patients, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<RecordKind>()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get happenedAt => dateTime()();
  TextColumn get doctor => text().nullable()();

  /// المركز، المعمل، أو العيادة — تلات استمارات من خمسة محتاجاه.
  TextColumn get place => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// محجوز للمرفقات (D3.6) — مفيش واجهة بتكتبه لسه.
  TextColumn get attachmentPath => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

@DataClassName('MedicationRow')
class Medications extends Table with SyncIdentity {
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
class DoseSchedules extends Table with SyncIdentity {
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
class FixedTimings extends Table with SyncIdentity {
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
class DoseEvents extends Table with SyncIdentity {
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
