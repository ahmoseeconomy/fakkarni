// عرض المتابعة — **دارت نقية، ومصدر واحد للناحيتين**.
//
// العطل اللي عمل الملف ده، من جهاز حقيقي: زيارة محجوزة **بكرة** كانت
// بتتعرض «زيارة — ١٣ سبتمبر ٢٠٢٣» عند الأب وعند الابن. التاريخ ده تاريخ
// **الورقة اللي المتابعة اتبدت منها**، مش تاريخ أي حاجة جاية. الكارت
// الجديد لوحده كان بيقول «بكرة» — لأنه الوحيد اللي بيقرا ميعاد المرحلة.
//
// **فالقاعدة بقت: متابعة مفتوحة بتتعرض بميعاد مرحلتها الحالية، وبس.**
// و`happenedAt` بتاعة صف المتابعة مابقاش لها أي دور في العرض.
//
// والملف هنا عشان الناحيتين يقروا **نفس الدالة**: نسختين من نفس الكلام
// معناها شاشتين ممكن يختلفوا في صمت — ودي نفس القاعدة اللي خلّت
// `rule_wording` مشتركة من الأول.

import '../../core/format/arabic_time.dart';
import 'checkup.dart';
import 'follow_up.dart';

/// «بكرة» / «بعد بكرة» / «بعد ٣ أيام» / «النهارده» — بأيام تقويمية.
///
/// مصر بتغيّر الساعة، والعدّ بالأيام لازم يمشي بساعة الحيطة مش بالضرب
/// في ٢٤ ساعة.
String countdownWord(DateTime now, DateTime at) {
  final days = DateTime(at.year, at.month, at.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days < 0) return arabicDate(at);
  if (days == 0) return 'النهارده';
  if (days == 1) return 'بكرة';
  if (days == 2) return 'بعد بكرة';
  if (days <= 10) return 'بعد ${arabicNumber(days)} أيام';
  return arabicDate(at);
}

/// الجملة اللي بتتكتب على **كل** شاشة بتعرض متابعة مفتوحة.
///
/// null = الإنسان لسه ما حطّش ميعاد. **وده بيتقال بالحرف** بدل ما
/// نرجع لتاريخ تاني — تاريخ غلط أوحش من «لسه ما اتحددش».
const String noFollowDateText = 'لسه ما اتحددش ميعاد';

String followDateLine(DateTime? stageDate, DateTime now) =>
    stageDate == null ? noFollowDateText : countdownWord(now, stageDate);

/// عنوان تقرير تحليل زي ما التطبيق بيكتبه: «تقرير تحليل — …».
final RegExp _labReportTitle = RegExp(r'^تقرير تحليل — (.+)$');

/// «— ٦ نتايج» / «— نتيجتين»: عدد، مش اسم تحليل.
final RegExp _countTail = RegExp(r'^[0-9٠-٩]+ نتايج$');

/// ما بنسمّيش المتابعة باسم الورقة اللي اتبدت منها.
///
/// «تقرير تحليل — ٦ نتايج» بيوصف **ورقة قديمة**، مش الحاجة اللي بنتابعها.
/// الاسم بقى باللي بنتابعه: اسم التحليل لو معروف، وإلا «متابعة تحليل»؛
/// والدكتور، وإلا «متابعة زيارة». الورقة نفسها بتتقال في سطر تاني
/// ([followOriginLine]).
///
/// **إصلاح وقت العرض، من غير ما نلمس صف متخزّن** — الصفوف القديمة
/// بتتعرض صح من غير هجرة.
String followDisplayTitle(FollowKind kind, String stored) {
  final generic = kind == FollowKind.lab ? 'متابعة تحليل' : 'متابعة زيارة';
  final title = stored.trim();
  if (title.isEmpty || title == 'من غير اسم دكتور') return generic;

  final report = _labReportTitle.firstMatch(title);
  if (report != null) {
    final tail = report.group(1)!.trim();
    // «٦ نتايج» / «نتيجتين» = عدّاد؛ أي حاجة تانية = اسم التحليل نفسه
    if (_countTail.hasMatch(tail) || tail == 'نتيجتين') return generic;
    return 'متابعة $tail';
  }
  return title;
}

/// «من روشتة ١٣ سبتمبر ٢٠٢٣» — الورقة اللي المتابعة طلعت منها.
///
/// **سطر ثانوي، ومكان تاريخ الورقة الوحيد.** التاريخ ده بتاع الورقة،
/// فبيتقال كأصل مش كميعاد.
String followOriginLine(FollowKind kind, DateTime paperDate) =>
    '${kind == FollowKind.lab ? 'من تقرير' : 'من روشتة'} ${arabicDate(paperDate)}';

/// المتابعة دي لسه مفتوحة؟
///
/// مفتوحة = واقفة عند مرحلة **قبل** الأخيرة. اللي وصلت آخر مرحلة حاجة
/// حصلت وخلصت، فبتتعرض زي أي سجل في الملف — بتاريخها، مش بميعاد جاي.
bool followIsOpen(FollowKind kind, FollowStage? stage) =>
    stage != null && stage.number < kind.stages.length;

/// ميعاد المرحلة من أعمدة الصف — **تعريف واحد للناحيتين**.
///
/// جهاز الأب بيقراها من `RecordRow` والابن من صف السحابة، والاتنين نفس
/// الأعمدة بنفس المعنى. [CheckupService.stageDateOf] بتعدّي على الدالة
/// دي، فمفيش نسختين يختلفوا لما يتزوّد عمود.
///
/// **ميعاد الزيارة في نفس عمود «معاد الدكتور»**: المعنى واحد، والصف نوعه
/// واحد بس، فمستحيل الاتنين يتلاقوا.
DateTime? followStageDate(
  FollowStage stage, {
  DateTime? labBookingAt,
  DateTime? resultReadyAt,
  DateTime? doctorVisitAt,
}) =>
    switch (stage) {
      CheckupStage.labBooking => labBookingAt,
      CheckupStage.waitingResult => resultReadyAt,
      CheckupStage.resultArrived => doctorVisitAt,
      VisitStage.booked => doctorVisitAt,
      _ => null,
    };

/// السطر الكامل: الكلمة القريبة والتاريخ جنبها — «بكرة — ٢٣ سبتمبر».
///
/// لما الميعاد بعيد، [countdownWord] بترجّع التاريخ نفسه، فالتكرار
/// بيتشال ويفضل التاريخ لوحده. من غير ميعاد: [noFollowDateText].
String followDateFull(DateTime? at, DateTime now) {
  if (at == null) return noFollowDateText;
  final word = countdownWord(now, at);
  final date = arabicDate(at);
  return word == date ? date : '$word — $date';
}

/// اسم المتابعة في سطر جوّه جملة — «متابعة تحليل صورة دم كاملة».
///
/// [followDisplayTitle] بترجّع «متابعة CBC» لما الاسم جه من ورقة، وبترجّع
/// اللي الإنسان كتبه زي ما هو غير كده. السطور اللي بتقول «… واقفة عند …»
/// محتاجة النوع يتسمّى في الحالتين، من غير «متابعة متابعة».
String followRowName(FollowKind kind, String stored) {
  final title = followDisplayTitle(kind, stored);
  return title.startsWith('متابعة') ? title : 'متابعة ${kind.word} $title';
}
