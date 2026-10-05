import 'dart:async';
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/services/reminder_plan.dart';

/// اللي بيتعمل على مجموعة جرعات من «الآن» — الرئيسية ونمط كبار السن
/// الاتنين بيندهوا هنا، فمفيش نسختين من «تأكيد» ولا من «بعد شوية».

/// بتجمّع الأحداث اللي في نفس الدقيقة — نفس تجميع المحرك بالظبط.
List<List<DoseEventView>> groupByMinute(List<DoseEventView> events) {
  final byTime = <DateTime, List<DoseEventView>>{};
  for (final event in events) {
    byTime.putIfAbsent(event.scheduledAt, () => []).add(event);
  }
  final times = byTime.keys.toList()..sort();
  return [for (final time in times) byTime[time]!];
}

/// «الآن»: اللي معاده جه من غير تأكيد (الأقدم الأول) — **ولو مفيش،
/// الجاية لوحدها** (قرار المالك، ٥ أكتوبر ٢٠٢٦).
///
/// كانت بترجّع الفايتة **والجاية معاها**، فجرعة لسه ما جاش معادها كانت
/// بتقعد في كارت «الجرعة الجاية» جنب الفايتة، و«أخدتهم كلهم» كان بيأكّدها
/// بدري في صمت. دلوقتي: فيه جرعة معادها جه (فايتة أو دلوقتي) → الكارت
/// ليها هي بس والجاية في «باقي اليوم»؛ مفيش → أقرب جرعة جاية هي
/// «الجرعة الجاية» زي ما كانت (وتأكيدها بدري قرار واضح من صاحبها، مش
/// عرَض تأكيد جماعي). ده تعريف «الآن» الواحد — الكارت ونمط كبار السن
/// و«كلّمني» بيقروا منه.
List<List<DoseEventView>> nowGroups(List<List<DoseEventView>> groups, DateTime now) {
  final open = [for (final g in groups) if (g.any((d) => !d.isDone)) g];
  final due = [for (final g in open) if (!g.first.scheduledAt.isAfter(now)) g];
  if (due.isNotEmpty) return due;
  final upcoming = [for (final g in open) if (g.first.scheduledAt.isAfter(now)) g];
  return [if (upcoming.isNotEmpty) upcoming.first];
}

/// «تأكيد» — كل جرعة في المجموعة اتاخدت، وبعدها القاعدة ٥: الخانة كلها
/// بتسكت ونافذة الجدولة بتتمد.
Future<void> confirmGroup(AppServices services, DateTime routineDay, List<DoseEventView> group) async {
  for (final dose in group) {
    await services.events.markTaken(dose.doseScheduleId, routineDay);
  }
  await services.scheduler.afterConfirmation(group.first.scheduledAt);
  // المخزون نقص — لو عدّى حد «قرب يخلص» التنبيه بيطلع دلوقتي (بعد الجدولة)
  await services.refreshRefills();
  // «تمام، سجّلت إن حضرتك أخدته» — بعد الوعد، ومن غير ما حد يستناه
  unawaited(services.voice?.speakLine('help_confirm_done'));
}

/// «لاحقًا» / «بعد شوية» = التأجيل الحقيقي (ربع ساعة).
Future<void> snoozeGroup(
  AppServices services,
  DateTime routineDay,
  List<DoseEventView> group, {
  required DateTime now,
}) async {
  await services.scheduler.snooze(
    originalAt: group.first.scheduledAt,
    body: reminderBodyFor([
      for (final d in group) (name: d.medicationName, amount: d.amountLabel, note: d.mealLabel),
    ]),
    payload: encodePayloadFor(
      routineDay,
      [for (final d in group) d.doseScheduleId.toString()],
    ),
    now: now,
  );
  // «هفكّرك تاني بعد شوية» — بعد التأجيل نفسه
  unawaited(services.voice?.speakLine('help_later'));
}

// ---------------------------------------------------------- كتلة «الآن»
//
// **كتلة واحدة، مش كارت لكل جرعة.** تلات أدوية مأجّلة كانت بتبقى تلات
// كروت مكدّسة: الراجل مش عارف هما كام ولا مين فيهم من غير ما ينزل ويعدّ.
// الداتا هي هي — اللي اتغيّر إنها بتتعرض كسطور في كتلة بعدّادها.

/// سطر واحد في «الآن» — دوا واحد، ومجموعة دقيقته اللي بيتأجّل معاها.
class NowLine {
  const NowLine({required this.dose, required this.group, this.remindAgainAt});

  final DoseEventView dose;

  /// مجموعة الدقيقة بتاعته — **التأجيل بيشتغل على الدقيقة**، زي ما هو.
  final List<DoseEventView> group;

  /// الموبايل هيفكّره إمتى تاني — null يعني لسه ما اتأجّلتش من الشاشة دي.
  final DateTime? remindAgainAt;

  bool get postponed => remindAgainAt != null;
}

/// سطور «الآن» متقسّمة: اللي مستنية دلوقتي، واللي هو أجّلها.
typedef NowLines = ({List<NowLine> due, List<NowLine> postponed});

/// بتفرد مجموعات [nowGroups] لسطور، وبتفصل اللي اتأجّل.
///
/// الترتيب جاي من [nowGroups] زي ما هو (الأقدم الأول)، والمأجّلة بتترتّب
/// بميعاد التذكير الجاي — ده اللي الراجل بيسأل عنه فيها.
NowLines nowLines(
  List<List<DoseEventView>> groups,
  Map<DateTime, DateTime> snoozedUntil,
) {
  final due = <NowLine>[];
  final postponed = <NowLine>[];
  for (final group in groups) {
    final again = snoozedUntil[group.first.scheduledAt];
    for (final dose in group) {
      if (dose.isDone) continue;
      final line = NowLine(dose: dose, group: group, remindAgainAt: again);
      (again == null ? due : postponed).add(line);
    }
  }
  postponed.sort((a, b) => a.remindAgainAt!.compareTo(b.remindAgainAt!));
  return (due: due, postponed: postponed);
}

/// أقصى عدد سطور بتتعرض قبل ما الباقي يتطوى.
///
/// تلاتة مش رقم مخترع: الكتلة فوق «جدول النهاردة» وتحت الترويسة، وزرار
/// «تأكيد الكل» لازم يفضل كامل فوق الدوك على أصغر آيفون — وده اللي
/// بيحدّد السقف، مش الذوق.
const int maxNowLines = 3;

/// «+ دوا كمان» / «+ دواين كمان» / «+ ٣ أدوية كمان».
///
/// بالكلام مش برقم لوحده: «+٢» جنب كتلة ذهبية بتتقري كأنها زينة، والدوا
/// المطوي بيعدّي. والعربي بيعدّ تلات صيغ، فالمفرد والمثنى مكتوبين بالإيد.
String moreDosesLabel(int rest) => switch (rest) {
      1 => '+ دوا كمان',
      2 => '+ دواين كمان',
      _ => '+ ${arabicNumber(rest)} أدوية كمان',
    };

/// «٣ أدوية» — عدّاد ترويسة «الآن».
///
/// **مفيش «·» في أي جملة بيقراها** (قاعدة مكتوبة واختبار بيقرا كل نص في
/// `lib/`): «٠» العربية هي نقطة، فالنقطة الوسطية جنب رقم عربي بتتقري رقم.
/// الفاصل « — ».
String nowCountLabel(int doses) => switch (doses) {
      // صفر كمان: «الآن» بتظهر لقياس سكر برّه المعتاد من غير أي جرعة.
      <= 1 => 'الآن',
      2 => 'الآن — دوايين',
      _ => 'الآن — ${arabicNumber(doses)} أدوية',
    };

/// «أجّلتها — ٢».
String postponedLabel(int count) =>
    count == 1 ? 'أجّلتها' : 'أجّلتها — ${arabicNumber(count)}';
