import 'dart:convert';

import '../../core/format/arabic_time.dart';
import '../../domain/escalation/escalation_ladder.dart';
import '../../domain/escalation/repeat_alerts.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';

/// كل الحسابات دي نقية — من غير إشعارات ولا قاعدة بيانات — عشان الجزء اللي
/// لازم يبقى مضبوط (الأرقام والنافذة) يتختبر من غير جهاز.

/// أول رقم في نطاق تذكيرات الجرعات.
///
/// النطاق محجوز عشان تصعيد المرحلة الرابعة يقعد في نطاق تاني ومنلغيش
/// إشعاراته بالغلط وإحنا بنعيد جدولة الجرعات.
const int doseIdBase = 1000000;

/// عدد الأيام اللي بتتكرر بعدها أرقام نفس المريض.
///
/// كانت ٤٠٩٦ يوم — ١١ سنة من المساحة لحاجة عمرها ما بتتجدول لأكتر من أيام
/// معدودة قدام. المساحة الضايعة دي اتحوّلت لبُعد المريض تحت.
const int _dayCycle = 32;

/// مساحة المريض الواحد: ٣٢ يوم × ١٤٤٠ دقيقة.
const int patientIdSpan = _dayCycle * 1440;

/// أقصى عدد مرضى في الحساب الواحد.
///
/// ١٢٨ × ٤٦٠٨٠ = ٥٬٨٩٨٬٢٤٠ — نفس عرض النطاق بالظبط، فالحدود المكتوبة في
/// CLAUDE.md ما اتغيّرتش.
const int maxPatients = 128;

const int doseIdLimit = doseIdBase + maxPatients * patientIdSpan;

/// نطاق «فكّرني بعدين».
///
/// التأجيل بياخد رقم من نطاق تاني مشتق من **خانة الجرعة الأصلية**، مش من
/// وقت التأجيل. لو اتحسب من وقت التأجيل، تأجيل جرعة ٨:٠٠ لـ٨:١٥ كان
/// هيبقى نفس رقم جرعة حقيقية الساعة ٨:١٥ ويمسحها في صمت. ولأنه مشتق من
/// الخانة الأصلية، «أخدته» بتعرف تلغيه من غير ما تخزّن حاجة.
const int snoozeIdBase = 20000000;

const int snoozeIdLimit = snoozeIdBase + maxPatients * patientIdSpan;

/// مدة التأجيل الافتراضية — ربع ساعة.
const Duration snoozeDelay = Duration(minutes: 15);

/// الموبايل هيفكّره إمتى بعد «لاحقًا» — **قراية للي التأجيل عمله، مش قرار
/// تاني**.
///
/// `ReminderScheduler.snooze` بتجدول عند `now + delay`؛ الدالة دي بتحسب
/// نفس اللحظة عشان «يومك» تقولها بالكلام («هيفكّرك ١٠:٣٠ ص»). نسختين من
/// نفس الحساب معناهم شاشة بتقول ميعاد والإشعار بيرن في ميعاد تاني، فـ
/// `snooze_time_mirror_test` بيشغّل الجدولة الحقيقية ويقارن الاتنين.
DateTime snoozeTimeFrom(DateTime now, {Duration delay = snoozeDelay}) =>
    now.add(delay);

/// نطاقات التصعيد — نطاق كامل لكل درجة على السلّم.
///
/// الدرجة بتاخد رقمها من **خانة الجرعة الأصلية** زي التأجيل بالظبط: «أخدته»
/// بتلغي الدرجتين من غير ما تخزّن حاجة، وإعادة الجدولة بتطلّع نفس الأرقام.
/// درجة لكل نطاق لأن عرض النطاق (١٢٨ مريض × ٤٦٬٠٨٠) مش بيسيب مكان
/// لدرجتين جوّه نطاق واحد؛ ١٠ مليون هو المحجوز من الأول، و٣٠ مليون أول
/// حدّ فاضي بعده (٢٠ مليون بتاع التأجيل).
const int escalationFirstIdBase = 10000000;
const int escalationSecondIdBase = 30000000;

/// مكان محجوز للتأجيل تحت سقف iOS.
///
/// «فكّرني بعدين» إشعار زيادة برّه أي نافذة. لو الجرعات والسلّم ملوا الـ٦٤،
/// التأجيل كان هيبقى رقم ٦٥ وiOS يرميه في صمت — أو يرمي حاجة تانية.
const int snoozePendingSlack = 2;

/// مكان محجوز لتذكيرات الصيام (D3.7) تحت سقف iOS — أقصى ٢ في نفس الوقت.
///
/// من غيره كان أول تذكير صيام هو الإشعار رقم ٦٥ (٤٨ + ١٤ + ٢)، وiOS كان
/// هيرميه — أو يرمي حاجة تانية — في صمت. التمن متشاف: نافذة الجرعات ٤٦
/// بدل ٤٨، وبتتجدد مع كل فتحة وكل تأكيد زي ما هي.
const int fastingPendingSlack = 2;

/// نطاق تذكير الصيام — **مستقل عن كل نطاقات الجرعات**. لو اتقاطع، تذكير
/// صيام كان هيلغي تذكير دوا بنفس الرقم في صمت، وده أسوأ باج ممكن. الرقم
/// مشتق من id صف `records`، مش مخزّن. إعادة جدولة الجرعات ما بتلمسوش
/// ([isRescheduledId] مش بتشمله)، وتأكيد جرعة ما بيلمسوش.
const int fastingIdBase = 40000000;
const int fastingIdLimit = fastingIdBase + maxPatients * patientIdSpan;

/// رقم تذكير الصيام لسجل الفحص [recordId]. برّه النطاق بيرمي — اللفّ هو
/// بالظبط التصادم اللي النطاق موجود عشان يمنعه.
int fastingIdFor(int recordId) {
  if (recordId < 0 || fastingIdBase + recordId >= fastingIdLimit) {
    throw RangeError.range(recordId, 0, fastingIdLimit - fastingIdBase - 1, 'recordId');
  }
  return fastingIdBase + recordId;
}

bool isFastingId(int id) => id >= fastingIdBase && id < fastingIdLimit;

/// مكان محجوز لمواعيد متابعة التحليل — أقصى ٢ معلّقين في نفس الوقت.
///
/// مرحلة واحدة بس بتبقى «الحالية» في كل متابعة، وتذكير المرحلة اللي فاتت
/// بيتلغي أول ما يبقى بلا معنى ([stageReminderStillUseful])، فمتابعة
/// واحدة = تذكير واحد. الاتنين دول يعني متابعتين شغّالين في وقت واحد،
/// زي تذكيرات الصيام بالظبط.
const int checkupPendingSlack = 2;

/// نطاق مواعيد المتابعة — **نطاق جديد على حد ١٠ مليون، زي القاعدة**.
///
/// الرقم مشتق من (id الصف، المرحلة)، مش متخزّن: نفس الصف ونفس المرحلة
/// بيدّوا نفس الرقم للأبد، فإعادة الضبط بتستبدل التذكير بدل ما تزوّد
/// واحد. تلات مراحل بتسأل عن تاريخ، فكل صف بياخد تلات أرقام متجاورة.
const int checkupIdBase = 50000000;
const int checkupIdLimit = checkupIdBase + maxPatients * patientIdSpan;

/// عدد المراحل اللي بتسأل عن تاريخ — عرض الخانة لكل صف.
const int checkupDatedStages = 3;

/// رقم تذكير المرحلة [stageSlot] (٠..٢) للسجل [recordId].
///
/// برّه النطاق بيرمي — اللفّ هو بالظبط التصادم اللي النطاق موجود عشان
/// يمنعه، وتذكير متابعة بيدوس على تذكير دوا هو أسوأ باج ممكن.
int checkupIdFor(int recordId, int stageSlot) {
  if (stageSlot < 0 || stageSlot >= checkupDatedStages) {
    throw RangeError.range(stageSlot, 0, checkupDatedStages - 1, 'stageSlot');
  }
  final id = checkupIdBase + recordId * checkupDatedStages + stageSlot;
  if (recordId < 0 || id >= checkupIdLimit) {
    throw RangeError.range(
        recordId, 0, (checkupIdLimit - checkupIdBase) ~/ checkupDatedStages - 1, 'recordId');
  }
  return id;
}

bool isCheckupId(int id) => id >= checkupIdBase && id < checkupIdLimit;

// ---------------------------------------------------------- المواعيد
/// **نطاق إشعارات المواعيد — الخانة الجاية على حد ١٠ مليون.**
///
/// ميعاد المتابعة بقى **إشعارين**: واحد هادي امبارح الميعاد، وواحد
/// بيرن الصبح بتاعه. النطاق القديم (`checkupIdBase`) بيدّي رقم واحد لكل
/// (صف، مرحلة)، فالتاني محتاج مكانه.
///
/// **ولازم يكون منفصل تماماً عن كل نطاق تاني**: جدولة إشعار برقم موجود
/// **بتستبدله في صمت** — يعني ميعاد ممكن يمسح تذكير دوا من غير أي خطأ في
/// أي مكان. `appointment_ids_test` بيقارن النطاقات عند **أقصى قيمة** كل
/// واحد فيها يقدر يوصلها، مش عند قيم عيّنة.
const int appointmentIdBase = 60000000;
const int appointmentIdLimit = appointmentIdBase + maxPatients * patientIdSpan;

/// إشعارين لكل **يوم** فيه مواعيد: ٠ = امبارحه، ١ = يومه.
const int appointmentNoticesPerDay = 2;

/// نوع الإشعار: الهادي امبارح، واللي بيرن في اليوم نفسه.
enum AppointmentNotice { dayBefore, dayOf }

/// رقم اليوم من ١٩٧٠-٠١-٠١ — **بالـUTC عن قصد**.
///
/// الفرق بين تاريخين محليين بيغلط يوم كامل حوالين تغيير الساعة في مصر:
/// يوم بـ٢٣ ساعة بيتقسم على ٢٤ ويطلع صفر. الـUTC مالهاش توقيت صيفي،
/// فالحساب مضبوط دايماً. اللي بيتاخد منه هو (سنة، شهر، يوم) بس.
int epochDayOf(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;

/// عدد الأيام اللي النطاق سايعها — أكتر من ثمن آلاف سنة من ١٩٧٠.
const int appointmentDaySpan = (maxPatients * patientIdSpan) ~/ appointmentNoticesPerDay;

/// رقم إشعار المواعيد — مشتق من (**اليوم**، النوع)، مش متخزّن.
///
/// **الرقم بقى لليوم مش للميعاد** (طلب المالك): كل المواعيد اللي في يوم
/// واحد بيطلعوا في إشعار واحد، فالرقم لازم يبقى مفتاحه اليوم. اللي كان
/// قبل كده مشتق من (الصف، المرحلة، النوع) — فأربع مواعيد في يوم كانوا
/// تمن إشعارات، والراجل بيصحى على أربع رنّات عن نفس الصبح.
///
/// نفس اليوم بيدّي نفس الرقم للأبد، فإعادة الجدولة بتستبدل بدل ما تزوّد.
/// برّه النطاق بيرمي — اللفّ هو بالظبط التصادم اللي النطاق موجود عشان
/// يمنعه، وإشعار ميعاد بيدوس على تذكير دوا هو أسوأ باج ممكن.
int appointmentIdFor(DateTime day, AppointmentNotice notice) =>
    _dayNoticeId(appointmentIdBase, appointmentIdLimit, day, notice, 'appointmentIdFor');

int _dayNoticeId(int base, int limit, DateTime day, AppointmentNotice notice, String what) {
  final epochDay = epochDayOf(day);
  if (epochDay < 0) {
    throw RangeError.value(epochDay, 'day', '$what: يوم قبل ١٩٧٠');
  }
  final id = base + epochDay * appointmentNoticesPerDay + notice.index;
  if (id >= limit) {
    throw RangeError.value(epochDay, 'day', '$what: برّه النطاق');
  }
  return id;
}

bool isAppointmentId(int id) => id >= appointmentIdBase && id < appointmentIdLimit;

/// **نطاق مواعيد الأب على موبايل الابن** — نطاق تاني خالص.
///
/// الابن مالوش `id` محلي للصف (هو بيقرا من السحابة)، فالرقم بيتاخد من
/// **مكان الميعاد في القايمة المرتّبة** بعد ما تتقص عند [caregiverAppointmentCap].
/// ده آمن لأن الجدولة بتتعاد بالكامل مع كل سحبة: الموجود اللي مش في
/// القايمة الجديدة بيتلغي، واللي فيها بيتجدول — فالرقم عمره ما يشير
/// لميعادين في نفس اللحظة.
///
/// **ومش بيلمس نطاق تنبيهات التصعيد بتاعة الابن ولا قناتها** — دي آخر
/// درجة في السلّم، وميعاد دكتور مالوش أي حق يقرّب منها.
const int caregiverAppointmentIdBase = 70000000;
const int caregiverAppointmentIdLimit =
    caregiverAppointmentIdBase + maxPatients * patientIdSpan;

/// أقصى عدد **أيام** فيها مواعيد بتتجدول على موبايل الابن.
///
/// سقف ثابت عن قصد: موبايل الابن مالوش نافذة بتتجدد زي موبايل الأب،
/// والقايمة بتيجي من سحبة السحابة. أربع أيام = تمن إشعارات.
/// **بقى عدّ أيام مش عدّ مواعيد** بعد ما الإشعار بقى واحد لليوم.
const int caregiverAppointmentCap = 4;

/// نفس اشتقاق الأب بالظبط، من نطاق تاني — واليوم هو المفتاح.
///
/// كان مشتق من **مكان** الميعاد في القايمة، وده كان بيخلّي نفس الرقم
/// يشير لميعاد مختلف لما القايمة تتغيّر. اليوم ثابت، فالرقم ثابت.
int caregiverAppointmentIdFor(DateTime day, AppointmentNotice notice) => _dayNoticeId(
      caregiverAppointmentIdBase,
      caregiverAppointmentIdLimit,
      day,
      notice,
      'caregiverAppointmentIdFor',
    );

bool isCaregiverAppointmentId(int id) =>
    id >= caregiverAppointmentIdBase && id < caregiverAppointmentIdLimit;

// ---------------------------------------------------------- إعادة التنبيه
/// **نطاقات إعادة التنبيه — عشر نطاقات على حدود ١٠ مليون: ٨٠ لحد ١٧٠.**
///
/// النطاق الواحد بيشيل رقم واحد بالظبط لكل (مريض، خانة) — زي درجتين
/// السلّم بالظبط، كل إعادة محتاجة نطاق لوحدها، و«مستمر» بيوصل لعشرة.
/// الرقم مشتق من **خانة الجرعة الأصلية** مش من وقت الإعادة: إعادة جرعة
/// ٨:٠٠ الساعة ٨:٠٥ ما تقدرش تمسح تذكير حقيقي الساعة ٨:٠٥، و«أخدته»
/// بتلغي العشرة من غير ما تخزّن حاجة. أعلى رقم (١٧٥٬٨٩٨٬٢٣٩) لسه أقل
/// بكتير من سقف أندرويد.
const int repeatIdBase = 80000000;

/// المسافة بين نطاق إعادة واللي بعده.
const int _repeatBandStride = 10000000;

final int repeatIdLimit =
    repeatIdBase + (maxRepeatsAny - 1) * _repeatBandStride + maxPatients * patientIdSpan;

/// مكان محجوز لإعادات التنبيه تحت سقف iOS — **ميزانية واحدة لكل الأنواع**.
///
/// «مستمر» بعشر إعادات لأقرب تذكيرين، أو «يتكرر» بتلاتة لأقرب ستة. الخطة
/// بتوزّعها بالترتيب على الأقرب فالأقرب، وأي تذكير أبعد بياخد اللي فاضل.
/// **دفعت من نافذة الجرعات، مش من السلّم** (٣٢ ← ٢٤): السلّم آخر وعد
/// للابن ومش بيتقصّ. على قاعدة التطبيق (٣ إشعارات في اليوم) ٢٤ ÷ ٣ =
/// ٨ أيام، أطول من نافذة السبع أيام؛ اللي عدّل أوقاته بإيده على ٩ دقايق
/// في اليوم بيقصر لتلات أيام إلا ربع — والنافذة بتتجدد مع كل تأكيد وكل
/// فتحة زي ما هي.
const int maxPendingRepeats = 20;

int _repeatBase(int index) {
  if (index < 0 || index >= maxRepeatsAny) {
    throw RangeError.range(index, 0, maxRepeatsAny - 1, 'index');
  }
  return repeatIdBase + index * _repeatBandStride;
}

/// رقم الإعادة [index] (٠..٩) لجرعة معادها الأصلي [originalAt].
int repeatIdFor(DateTime originalAt, int index, {int patientIndex = 0}) =>
    _repeatBase(index) + _patientSlot(originalAt, patientIndex);

/// رقم الإعادة اللي الرقم ده بتاعها — أو null لو مش رقم إعادة.
int? repeatIndexOf(int id) {
  for (var i = 0; i < maxRepeatsAny; i++) {
    final base = _repeatBase(i);
    if (id >= base && id < base + maxPatients * patientIdSpan) return i;
  }
  return null;
}

bool isRepeatId(int id) => repeatIndexOf(id) != null;

/// ------------------------------------------------------------------
/// **تذكيرات الممرض** (٢٤ سبتمبر ٢٠٢٦) — على **موبايل الممرض** بس، عن
/// جرعات مريض (أو أكتر) بيتابعه. رقم لكل (مريض، دقيقة) — مشتق من الخانة
/// زي الجرعة بالظبط، و[patientIndex] هنا ترتيب المريض عند الممرض (< ١٢٨).
///
/// **مش** في [isRescheduledId]: إعادة جدولة المريض عمرها ما بتلمسه، ومجدول
/// الممرض بيلغي من النطاق ده بس. على موبايل المريض النطاق ده فاضي دايماً.
const int nurseIdBase = 180000000;
const int nurseIdLimit = nurseIdBase + maxPatients * patientIdSpan;

int nurseIdFor(DateTime at, {required int patientIndex}) => nurseIdBase + _patientSlot(at, patientIndex);

bool isNurseId(int id) => id >= nurseIdBase && id < nurseIdLimit;

/// سقف تذكيرات الممرض المعلّقة. موبايل الممرض مالوش جرعات بتاعته (الجذر
/// بيفتح تطبيق المريض لو فيه مريض محلي)، فالسقف ده + مواعيد المريض عنده
/// (٤ أيام × ٢) تحت ٦٤ بمسافة.
const int maxPendingNurseReminders = 40;

/// **«قرب يخلص»** (٢٥ سبتمبر ٢٠٢٦) — رقم واحد لكل دوا: `base + medicationId`.
/// الإشعار ده **معروض مش متجدول** (`showRefill`)، فما بياخدش خانة من الـ٦٤
/// ومش في [isRescheduledId]. بيرمي برّه النطاق بدل ما يلفّ.
const int refillIdBase = 190000000;
const int refillIdLimit = refillIdBase + maxPatients * patientIdSpan;

int refillIdFor(int medicationId) {
  final id = refillIdBase + medicationId;
  if (medicationId < 0 || id >= refillIdLimit) {
    throw RangeError.range(medicationId, 0, refillIdLimit - refillIdBase - 1, 'medicationId');
  }
  return id;
}

bool isRefillId(int id) => id >= refillIdBase && id < refillIdLimit;

/// سقف إشعارات التصعيد المعلّقة — اللي فاضل تحت سقف iOS بعد الجرعات
/// ومكان التأجيل والصيام والمتابعة وإعادة التنبيه:
/// ٦٤ − ٢٤ − ٢ − ٢ − ٢ − ٢٠ = ١٤.
///
/// ١٤ ÷ درجتين = أقرب ٧ تذكيرات بس هي اللي بياخدوا سلّم. النافذة دي
/// بتتجدد مع كل تأكيد وكل فتحة زي نافذة الجرعات، فاللي بعدهم بيلحقوا.
const int maxPendingEscalations = iosPendingLimit -
    maxPendingReminders -
    snoozePendingSlack -
    fastingPendingSlack -
    checkupPendingSlack -
    maxPendingRepeats;

/// نافذة الجدولة الافتراضية.
const int reminderWindowDays = 7;

/// iOS بيقبل **٦٤ إشعار معلّق للتطبيق كله** وبيرمي أي زيادة في صمت —
/// من غير خطأ ومن غير تحذير.
const int iosPendingLimit = 64;

/// سقفنا لتذكيرات الجرعات.
///
/// بنسيب ١٦ خانة فاضية تحت سقف iOS لتصعيد المرحلة الرابعة وأي حاجة جاية.
/// السقف بيتطبّق على أندرويد كمان عن قصد: نفس السلوك على الجهازين أسهل في
/// التفكير من «شغال عندي على أندرويد».
///
/// كان ٤٨؛ بقى ٤٦ في D3.7 عشان تذكيرين صيام يلاقوا مكان، وبقى ٤٤ مع
/// مواعيد متابعة التحليل (تذكيرين كمان)، وبقى ٣٢ مع إعادة التنبيه، وبقى
/// ٢٤ مع نوع «مستمر» ([maxPendingRepeats] = ٢٠). التمن متشاف ومقصود: أفق
/// الجرعات بيقصر لمريض على أوقات كتير مميّزة في اليوم، وبيتجدد مع كل
/// فتحة وكل تأكيد زي ما هو — والسلّم ما دفعش ولا خانة.
const int maxPendingReminders = 24;

/// رقم الإشعار مشتق من (المريض، اليوم، الدقيقة).
///
/// المحرك بيجمّع أي جرعات في نفس الدقيقة في [Reminder] واحد، يعني الخانة
/// الزمنية دي فريدة لكل مريض. النتيجة إن إعادة الجدولة بترجّع نفس الأرقام
/// بالظبط، فالتكرار مستحيل من أصله — مش «بنحاول نتجنبه».
///
/// [patientIndex] لازم يكون رقم صغير وثابت للمريض (خانة، مش مفتاح الصف).
/// من غيره، اتنين في نفس البيت بياخدوا دواهم الساعة ٨ الصبح كانوا هياخدوا
/// نفس الرقم، وتذكير الواحد فيهم كان بيمسح تذكير التاني في صمت.
int notificationIdFor(DateTime at, {int patientIndex = 0}) =>
    doseIdBase + _patientSlot(at, patientIndex);

/// رقم تذكير التأجيل لجرعة معادها الأصلي [originalAt].
int snoozeIdFor(DateTime originalAt, {int patientIndex = 0}) =>
    snoozeIdBase + _patientSlot(originalAt, patientIndex);

int _patientSlot(DateTime at, int patientIndex) {
  if (patientIndex < 0 || patientIndex >= maxPatients) {
    // بنرمي بدل ما نلف بالباقي: اللف بيرجّع نفس التصادم اللي بنصلحه هنا.
    throw ArgumentError.value(
      patientIndex,
      'patientIndex',
      'لازم يكون بين 0 و ${maxPatients - 1}',
    );
  }

  final epochDay = DateTime.utc(at.year, at.month, at.day)
      .difference(DateTime.utc(1970))
      .inDays;
  final slot = (epochDay % _dayCycle) * 1440 + at.hour * 60 + at.minute;
  return patientIndex * patientIdSpan + slot;
}

bool isDoseId(int id) => id >= doseIdBase && id < doseIdLimit;

bool isSnoozeId(int id) => id >= snoozeIdBase && id < snoozeIdLimit;

int _escalationBase(EscalationRung rung) => switch (rung) {
      EscalationRung.first => escalationFirstIdBase,
      EscalationRung.second => escalationSecondIdBase,
    };

/// رقم درجة تصعيد لجرعة معادها الأصلي [originalAt].
int escalationIdFor(
  DateTime originalAt,
  EscalationRung rung, {
  int patientIndex = 0,
}) =>
    _escalationBase(rung) + _patientSlot(originalAt, patientIndex);

bool isEscalationId(int id) => escalationRungOf(id) != null;

/// الدرجة اللي الرقم ده بتاعها — أو null لو مش رقم تصعيد. بيستعمله فلتر
/// «التنبيهات» (D3.3) عشان يشيل درجة مقفولة من غير ما يلمس السلّم.
EscalationRung? escalationRungOf(int id) {
  for (final rung in EscalationRung.values) {
    final base = _escalationBase(rung);
    if (id >= base && id < base + maxPatients * patientIdSpan) return rung;
  }
  return null;
}

/// أي رقم بنملكه إحنا وبنعيد جدولته — جرعات وتصعيد وإعادة تنبيه.
/// التأجيل برّه عن قصد: هو بيتلغي بالتأكيد بس، مش بإعادة الجدولة.
///
/// الإعادة جوّه عن قصد: هي مشتقة من الخطة زي السلّم، فجرعة اتأكدت
/// (من «يومك»، من شاشة القفل، أو وصلت من أي مكان تاني قبل إعادة الجدولة
/// الجاية) بتختفي من الخطة وإعاداتها المعلّقة بتتلغي كـ«قديمة» في نفس
/// المطابقة.
bool isRescheduledId(int id) => isDoseId(id) || isEscalationId(id) || isRepeatId(id);

/// يوم الروتين اللي إحنا فيه دلوقتي.
///
/// اليوم بيبدأ من الصحيان مش من نص الليل: واحد بيصحى ٧ ص ولسه صاحي الساعة
/// ١ بالليل، لسه في يوم امبارح — وجرعة «قبل النوم» بتاعته لسه مستنياه.
DateTime currentRoutineDay(DayRoutine routine, DateTime now) {
  final wakeToday =
      DateTime(now.year, now.month, now.day, 0, routine.wake.minutes);
  return now.isBefore(wakeToday)
      ? DateTime(now.year, now.month, now.day - 1)
      : DateTime(now.year, now.month, now.day);
}

/// مفتاح «الجرعة دي في اليوم ده» — نفس مفتاح جدول الأحداث.
///
/// بيه بنعرف إيه اللي اتأكد خلاص عشان ما نعيدش جدولته: واحد خد جرعة ٢:٠٠ م
/// الساعة ١:٥٠ لسه «قدام» بالساعة، بس خلاص بالنسبة له.
String doneKey(String scheduleId, DateTime routineDay) =>
    '$scheduleId|${routineDay.year}-${routineDay.month}-${routineDay.day}';

/// نوع الإشعار — بيحدد القناة على الجهاز (التصعيد بيهزّ وبيعلّي).
enum NotificationKind {
  dose,
  escalation,

  /// إعادة تنبيه (+٥/+١٠/+١٥) — نفس قناة الجرعة ونفس أزرارها ونفس نغمتها.
  repeat,

  /// تذكير صيام قبل سحب عينة (D3.7) — قناة لوحدها ومن غير أزرار «أخدته».
  fasting,

  /// ميعاد متابعة (زيارة أو معمل) — قناة لوحدها، ومنبّه **غير دقيق**
  /// على أندرويد. الهادي بيتبعت `silent`، واللي في اليوم نفسه بيرن.
  appointmentQuiet,
  appointmentAlert,
}

/// تذكير جاهز للجدولة على الجهاز.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    this.doses = const [],
    this.kind = NotificationKind.dose,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
  final List<DoseSchedule> doses;
  final NotificationKind kind;

  @override
  String toString() => 'PlannedNotification($id، $at، $body)';
}

/// كل التذكيرات في النافذة الجاية، مرتّبة، ومقصوصة عند السقف.
///
/// بنبدأ اللف من امبارح: جرعة «قبل النوم» لواحد بينام ١ ص بتقع بعد منتصف
/// الليل، يعني بتاعة امبارح ممكن تكون لسه جاية النهاردة.
///
/// **النافذة بتقصر لوحدها لما الأدوية تكتر.** مريض بدواء واحد بياخد الـ٧
/// أيام كاملة. مريض بـ٦ أدوية × ٣ جرعات بيملا السقف في يومين ونص، فبناخد
/// **الأقرب** ونسيب الباقي. ده مقصود: iOS بيرمي أي حاجة بعد الـ٦٤ في صمت،
/// يعني من غير القص إحنا مش بنكسب تغطية أطول — إحنا بنخسر جرعات عشوائية
/// من غير ما نعرف. والنافذة بتتمدّ تاني كل مرة التطبيق يتفتح.
List<PlannedNotification> planWindow({
  required DayRoutine routine,
  required List<DoseSchedule> schedules,
  required DateTime from,
  int days = reminderWindowDays,
  int maxPending = maxPendingReminders,
  int patientIndex = 0,

  /// الجرعات اللي اتأكدت خلاص (مفاتيح [doneKey]) — ما بتتجدولش تاني حتى
  /// لو ساعتها لسه ما جاتش.
  Set<String> done = const {},
}) {
  // أرقام المريض بتلف كل [_dayCycle] يوم. نافذة أطول من كده معناها إن أول
  // يوم وآخر يوم ياخدوا نفس الرقم، والتذكير يمسح التاني في صمت.
  assert(days < _dayCycle, 'النافذة لازم تفضل أقصر من $_dayCycle يوم');

  final engine = ScheduleEngine(routine);
  final planned = <PlannedNotification>[];
  final seen = <int>{};

  for (var offset = -1; offset < days; offset++) {
    // DateTime(y, m, d + offset) مش add(Duration) — مصر بتغيّر التوقيت الصيفي
    // والمُنشئ بيحسب بالساعة اللي المستخدم شايفها.
    final day = DateTime(from.year, from.month, from.day + offset);

    for (final full in engine.remindersForDay(schedules, day)) {
      if (!full.at.isAfter(from)) continue;

      // اللي اتأكد بدري بيتشال من التذكير؛ لو التذكير فضي خالص بيسقط.
      final kept = [
        for (final dose in full.doses)
          if (!done.contains(doneKey(dose.id, day))) dose,
      ];
      if (kept.isEmpty) continue;
      final reminder = kept.length == full.doses.length
          ? full
          : Reminder(at: full.at, doses: kept);

      final id = notificationIdFor(reminder.at, patientIndex: patientIndex);
      if (!seen.add(id)) continue;

      planned.add(
        PlannedNotification(
          id: id,
          at: reminder.at,
          title: 'وقت الدوا',
          body: reminderBody(reminder),
          payload: encodePayload(day, reminder),
          doses: reminder.doses,
        ),
      );
    }
  }

  // الترتيب قبل القص هو اللي بيضمن إن اللي بنسيبه هو الأبعد، مش اللي جه
  // آخر واحد في اللفة.
  planned.sort((a, b) => a.at.compareTo(b.at));
  if (planned.length > maxPending) planned.length = maxPending;
  return planned;
}

/// سلّم التصعيد لأقرب التذكيرات.
///
/// [reminders] هي تذكيرات الجرعات اللي هنبني عليها — تتحسب بـ[planWindow]
/// من **قبل [from] بمهلة** ([graceWindow])، مش من [from]: جرعة رنّت ٨:٠٠
/// والتطبيق اتفتح ٨:١٠ لسه سلّمها شغّال، ولو حسبناها من ٨:١٠ كانت هتختفي
/// من الخطة وإعادة الجدولة تلغي درجاتها المعلّقة كأنها اتأكدت.
/// الدرجات اللي معادها فات بتتشال؛ الجايّة بس هي اللي بتتجدول.
///
/// نفس الحمولة بتاعة الجرعة: الدوسة أو «أخدته» على درجة التصعيد بتتعامل
/// كأنها على التذكير الأصلي — وده اللي بيخلي القاعدة الخامسة تشتغل من
/// الإشعار نفسه.
List<PlannedNotification> planEscalations(
  List<PlannedNotification> reminders, {
  required DateTime from,
  int maxPending = maxPendingEscalations,
  int patientIndex = 0,
}) {
  final rungs = EscalationRung.values.length;
  final planned = <PlannedNotification>[];

  for (final reminder in reminders.take(maxPending ~/ rungs)) {
    for (final step in ladderFor(reminder.at)) {
      if (!step.at.isAfter(from)) continue;
      planned.add(
        PlannedNotification(
          id: escalationIdFor(reminder.at, step.rung, patientIndex: patientIndex),
          at: step.at,
          title: escalationTitle,
          body: escalationBody(step.rung, reminder.body),
          payload: reminder.payload,
          doses: reminder.doses,
          kind: NotificationKind.escalation,
        ),
      );
    }
  }

  planned.sort((a, b) => a.at.compareTo(b.at));
  return planned;
}

/// نوع تنبيه تذكير مجمّع: الأقوى بين أدويته، وأي دوا من غير نوع بياخد
/// [fallback] (إعداد الجهاز).
AlertMode alertModeOf(PlannedNotification reminder, {required AlertMode fallback}) =>
    AlertMode.strongest([for (final d in reminder.doses) d.alertMode ?? fallback]);

/// إعادات التنبيه لأقرب التذكيرات.
///
/// نفس شكل [planEscalations] ونفس مدخله: [reminders] محسوبة من **قبل
/// [from] بمهلة** — جرعة رنّت ٨:٠٠ والتطبيق اتفتح ٨:٠٧ لسه إعادتها ٨:١٠
/// قدام، ولو حسبناها من ٨:٠٧ كانت هتختفي من الخطة وتتلغي كأنها اتأكدت.
/// الإعادات اللي معادها فات بتتشال؛ الجايّة بس هي اللي بتتجدول.
///
/// **إعادة على دقيقة درجة شغّالة بتتشال.** الإعادة التالتة عند +١٥ هي
/// نفس دقيقة الدرجة الأولى من السلّم؛ إشعارين بنغمة ٢٤ ثانية في نفس
/// اللحظة مش «أعلى»، ده لخبطة. الدرجة هي اللي بتكسب (بتهزّ وبتسأل). لو
/// المستخدم قفل درجة +١٥ من «التنبيهات»، الإعادة التالتة بترجع تملا
/// مكانها — [enabledRungs] هي اللي بتقول.
///
/// **والميزانية خانات، مش تذكيرات**: كل تذكير بياخد إعاداته من اللي فاضل
/// بالترتيب — الأقرب الأول — لحد ما الخانات تخلص. «مستمر» بعشرة بيغطّي
/// تذكيرين، «يتكرر» بتلاتة بيغطّي ستة. تذكير رنّ من نص ساعة إعاداته
/// كلها فاتت وما بياخدش خانة.
///
/// [modeOf] بيقول نوع كل تذكير — الأقوى بين أدويته، وإلا إعداد الجهاز.
///
/// نفس الحمولة بتاعة الجرعة: الدوسة أو «أخدته» على الإعادة بتتعامل
/// كأنها على التذكير الأصلي — القاعدة الخامسة بتشتغل من الإشعار نفسه.
List<PlannedNotification> planRepeats(
  List<PlannedNotification> reminders, {
  required DateTime from,
  int maxPending = maxPendingRepeats,
  int patientIndex = 0,
  Set<EscalationRung> enabledRungs = const {EscalationRung.first, EscalationRung.second},
  AlertMode Function(PlannedNotification reminder)? modeOf,
}) {
  final taken = {for (final rung in enabledRungs) rung.delay};
  final planned = <PlannedNotification>[];
  var left = maxPending;

  for (final reminder in reminders) {
    if (left <= 0) break;
    final mode = modeOf?.call(reminder) ?? AlertMode.standard;
    final steps = [
      for (final step in repeatsFor(reminder.at, mode: mode))
        if (step.at.isAfter(from) && !taken.contains(step.delay)) step,
    ].take(left).toList();
    if (steps.isEmpty) continue;
    left -= steps.length;
    for (final step in steps) {
      planned.add(
        PlannedNotification(
          id: repeatIdFor(reminder.at, step.index, patientIndex: patientIndex),
          at: step.at,
          title: reminder.title,
          body: repeatBody(step, reminder.body),
          payload: reminder.payload,
          doses: reminder.doses,
          kind: NotificationKind.repeat,
        ),
      );
    }
  }

  planned.sort((a, b) => a.at.compareTo(b.at));
  return planned;
}

/// نص الإعادة: نفس سطر الجرعة، وقدامه قد إيه عدّى — بنفس لهجة السلّم.
String repeatBody(RepeatStep step, String reminderBody) =>
    '$reminderBody — ${elapsedWords(step.delay.inMinutes)}';

/// «فات ٥ دقايق» / «فات ربع ساعة» / «فات نص ساعة» / «فات ٢١ دقيقة».
String elapsedWords(int minutes) => switch (minutes) {
      15 => 'فات ربع ساعة',
      30 => 'فات نص ساعة',
      >= 3 && <= 10 => 'فات ${arabicNumber(minutes)} دقايق',
      _ => 'فات ${arabicNumber(minutes)} دقيقة',
    };

/// عنوان درجة التصعيد — سؤال، مش لوم.
const String escalationTitle = 'لسه ما أخدتش الدوا؟';

/// نص الدرجة: نفس سطر الجرعة، وقدامه قد إيه عدّى.
String escalationBody(EscalationRung rung, String reminderBody) {
  final elapsed = switch (rung) {
    EscalationRung.first => 'فات ربع ساعة',
    EscalationRung.second => 'فات نص ساعة',
  };
  return '$reminderBody — $elapsed';
}

/// لحد إمتى التذكيرات مغطية فعلاً — آخر تذكير اتجدول، أو null لو مفيش.
///
/// بيوضّح أثر السقف: مع أدوية كتير الرقم ده بيبقى بعد يومين مش سبعة.
DateTime? coverageEnd(List<PlannedNotification> planned) =>
    planned.isEmpty ? null : planned.last.at;

/// آخر تذكير جرعة **الجهاز ماسكه فعلاً** — من `pending()`، مش من الخطة.
///
/// الفرق بين الاتنين هو كل الحكاية: [planWindow] هو اللي احنا فاكرينه،
/// والـpending هو اللي iOS وافق يمسكه — وiOS بيرمي اللي زيادة عن ٦٤ من
/// غير خطأ ومن غير تحذير. فحص السلامة بيقرا من هنا عن قصد.
///
/// الرقم بيترجّع لوقته: الخانة جوّه الرقم هي `(epochDay % 32)*1440 +
/// دقيقة اليوم`، ودورة الـ٣٢ يوم أطول بكتير من نافذة السبع أيام، فأول
/// يوم جاي بيوافق الباقي هو اليوم الصح. اللي طلع معاده بيتشال.
DateTime? horizonFromPendingDoseIds(
  Iterable<int> pendingIds, {
  required DateTime now,
  int patientIndex = 0,
}) {
  DateTime? furthest;
  final todayEpoch =
      DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(1970)).inDays;

  for (final id in pendingIds) {
    if (!isDoseId(id)) continue;
    final slot = id - doseIdBase - patientIndex * patientIdSpan;
    if (slot < 0 || slot >= patientIdSpan) continue;

    final dayMod = slot ~/ 1440;
    final minuteOfDay = slot % 1440;
    final ahead = (dayMod - todayEpoch % _dayCycle + _dayCycle) % _dayCycle;
    final day = DateTime.utc(1970).add(Duration(days: todayEpoch + ahead));
    // بالمُنشئ مش بـadd: مصر بتغيّر الساعة، والمُنشئ بيشتغل بساعة الحيطة
    final at = DateTime(day.year, day.month, day.day, 0, minuteOfDay);

    if (at.isBefore(now)) continue;
    if (furthest == null || at.isAfter(furthest)) furthest = at;
  }
  return furthest;
}

/// نص التذكير — اسم الدوا والجرعة، أو عددهم لو أكتر من واحد.
String reminderBody(Reminder reminder) => reminderBodyFor([
      for (final d in reminder.doses) (name: d.medicationName, amount: d.amountLabel),
    ]);

/// نفس النص بس من أسماء وجرعات جاهزة — شاشة التذكير عندها أحداث اليوم مش
/// جداول، وبتحتاج تكتب نفس الجملة لتذكير التأجيل.
String reminderBodyFor(List<({String name, String? amount})> doses) {
  if (doses.length == 1) {
    final dose = doses.single;
    final amount = dose.amount;
    return amount == null ? dose.name : '${dose.name} — $amount';
  }

  final names = doses.map((d) => d.name).join(' + ');
  return '${arabicNumber(doses.length)} أدوية دلوقتي: $names';
}

String encodePayload(DateTime routineDay, Reminder reminder) =>
    encodePayloadFor(routineDay, [for (final d in reminder.doses) d.id]);

String encodePayloadFor(DateTime routineDay, List<String> scheduleIds) =>
    jsonEncode({
      'v': 1,
      'day': '${routineDay.year.toString().padLeft(4, '0')}-'
          '${routineDay.month.toString().padLeft(2, '0')}-'
          '${routineDay.day.toString().padLeft(2, '0')}',
      'scheduleIds': scheduleIds,
    });

/// اللي جوّه الإشعار: يوم الروتين وأرقام الجداول اللي رنّ عشانها.
///
/// بنخزّن أرقام الجداول مش الساعة: لو الروتين اتعدّل بين الجدولة والدوسة،
/// الساعة بتبقى غلط، لكن الجرعة هي هي.
class ReminderPayload {
  const ReminderPayload({required this.routineDay, required this.scheduleIds});

  final DateTime routineDay;
  final List<String> scheduleIds;
}

/// بيفكّ الـpayload، أو null لو مش بتاعنا — إشعار قديم، أو نسخة أحدث.
ReminderPayload? decodePayload(String? payload) {
  if (payload == null) return null;
  try {
    final json = jsonDecode(payload);
    if (json is! Map || json['v'] != 1) return null;
    final day = DateTime.parse(json['day'] as String);
    final ids = (json['scheduleIds'] as List).cast<String>();
    if (ids.isEmpty) return null;
    return ReminderPayload(
      routineDay: DateTime(day.year, day.month, day.day),
      scheduleIds: ids,
    );
  } on Object {
    return null;
  }
}

/// الفرق بين اللي المفروض يكون متجدول واللي متجدول فعلاً.
typedef Reconciliation = ({Set<int> toCancel, List<PlannedNotification> toSchedule});

/// بنلغي اللي بقى مش مطلوب **جوّه نطاقاتنا بس** ([inBand]).
///
/// عمداً مش بنستخدم cancelAll: أي نطاق مش بتاعنا — التأجيل، أو أي حاجة
/// جاية — بيعدّي من هنا سليم.
Reconciliation reconcile(
  List<PlannedNotification> planned,
  Set<int> pendingIds, {
  bool Function(int id) inBand = isDoseId,
}) {
  final desired = {for (final p in planned) p.id};
  final stale = pendingIds.where(inBand).toSet().difference(desired);
  return (toCancel: stale, toSchedule: planned);
}
