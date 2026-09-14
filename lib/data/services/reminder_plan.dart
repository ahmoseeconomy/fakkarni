import 'dart:convert';

import '../../core/format/arabic_time.dart';
import '../../domain/escalation/escalation_ladder.dart';
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

/// سقف إشعارات التصعيد المعلّقة — اللي فاضل تحت سقف iOS بعد الجرعات
/// ومكان التأجيل: ٦٤ − ٤٨ − ٢ = ١٤.
///
/// ١٤ ÷ درجتين = أقرب ٧ تذكيرات بس هي اللي بياخدوا سلّم. النافذة دي
/// بتتجدد مع كل تأكيد وكل فتحة زي نافذة الجرعات، فاللي بعدهم بيلحقوا.
const int maxPendingEscalations =
    iosPendingLimit - maxPendingReminders - snoozePendingSlack;

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
const int maxPendingReminders = 48;

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

/// أي رقم بنملكه إحنا وبنعيد جدولته — جرعات وتصعيد. التأجيل برّه عن قصد:
/// هو بيتلغي بالتأكيد بس، مش بإعادة الجدولة.
bool isRescheduledId(int id) => isDoseId(id) || isEscalationId(id);

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
enum NotificationKind { dose, escalation }

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

/// عنوان درجة التصعيد — سؤال، مش لوم.
const String escalationTitle = 'لسه ما أخدتش الدوا؟';

/// نص الدرجة: نفس سطر الجرعة، وقدامه قد إيه عدّى.
String escalationBody(EscalationRung rung, String reminderBody) {
  final elapsed = switch (rung) {
    EscalationRung.first => 'فات ربع ساعة',
    EscalationRung.second => 'فات نص ساعة',
  };
  return '$reminderBody · $elapsed';
}

/// لحد إمتى التذكيرات مغطية فعلاً — آخر تذكير اتجدول، أو null لو مفيش.
///
/// بيوضّح أثر السقف: مع أدوية كتير الرقم ده بيبقى بعد يومين مش سبعة.
DateTime? coverageEnd(List<PlannedNotification> planned) =>
    planned.isEmpty ? null : planned.last.at;

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
