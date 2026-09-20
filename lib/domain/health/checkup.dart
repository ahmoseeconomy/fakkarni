// متابعة التحليل (D3.7) — دارت نقية.
//
// سبع مراحل، والمستخدم بس اللي بيحرّكها. مفيش «المتوقع ٢٤ ساعة» ولا قاعدة
// بتحكم على التأخير: ده رقم ماحدش قاله لنا.
//
// **الاسم للمستخدم بقى «تابع تحليل» / «متابعة التحليل»، مش «دورة فحص».**
// الأسماء في الكود (`CheckupStage`، `records.checkup_stage`) زي ما هي —
// دي لغة الكود، والجولة دي كانت عن اللي الراجل بيقراه.

import 'follow_up.dart';

enum CheckupStage implements FollowStage {
  doctorOrder('طلب الطبيب'),
  labBooking('حجز المعمل', dateQuestion: 'حجزت إمتى؟'),
  preparation('التحضير'),
  sampleDraw('سحب العينة'),
  waitingResult('انتظار النتيجة', dateQuestion: 'النتيجة هتجهز إمتى؟'),
  resultArrived('النتيجة وصلت', dateQuestion: 'معاد الدكتور؟'),
  doctorReview('مراجعة الطبيب');

  const CheckupStage(this.label, {this.dateQuestion});

  @override
  final String label;

  /// المرحلة دي بتسأل عن تاريخ؟ والسؤال نفسه.
  ///
  /// **إحنا ما بنفترضش المرحلة بتاخد قد إيه** — ده رقم ماحدش قاله لنا.
  /// بدل ما نخمّن، الإنسان بيقول لنا، وساعتها بس بيبقى فيه تذكير.
  /// null = المرحلة دي مالهاش ميعاد نسأل عنه.
  @override
  final String? dateQuestion;

  @override
  bool get asksForDate => dateQuestion != null;

  /// ١..٧ — زي ما بيتخزّن في `records.checkup_stage`.
  @override
  int get number => index + 1;

  static CheckupStage? fromNumber(int? n) =>
      n == null || n < 1 || n > values.length ? null : values[n - 1];

  CheckupStage? get next => index + 1 < values.length ? values[index + 1] : null;
  CheckupStage? get previous => index > 0 ? values[index - 1] : null;

  /// المراحل اللي بتسأل عن تاريخ، بترتيبها.
  static List<CheckupStage> get dated => [for (final s in values) if (s.asksForDate) s];
}

/// تذكير الصيام بيعيش لحد «سحب العينة» بس — بعدها بقى زنّ على حاجة اتعملت.
bool fastingReminderStillUseful(CheckupStage stage) => stage.number <= CheckupStage.sampleDraw.number;

/// تذكير مرحلة [owner] لسه له لازمة والمتابعة واقفة عند [current]؟
///
/// كل تذكير بيعيش لحد المرحلة اللي بتخلّيه بلا معنى، مش لحد ما تسيب مرحلته:
///   * «حجزت إمتى؟» ميعاد المعمل — بيفضل لحد ما العينة تتسحب. الواحد
///     بيعدّي على «التحضير» **قبل** ما يروح، فإلغاؤه هناك كان هيضيّع
///     الميعاد نفسه.
///   * «النتيجة هتجهز إمتى؟» — بيفضل لحد ما النتيجة توصل.
///   * «معاد الدكتور؟» — آخر مرحلة أصلاً، فبيفضل لحد ما المتابعة تتوقف.
bool stageReminderStillUseful(CheckupStage owner, CheckupStage current) => switch (owner) {
      CheckupStage.labBooking => current.number <= CheckupStage.sampleDraw.number,
      CheckupStage.waitingResult => current.number <= CheckupStage.resultArrived.number,
      _ => true,
    };

/// لحظة التذكير: ميعاد السحب ناقص عدد الساعات **اللي المعمل قالها**. التقويم
/// بالـconstructor مش Duration (التوقيت الصيفي).
DateTime fastingReminderTime(DateTime draw, int hours) =>
    DateTime(draw.year, draw.month, draw.day, draw.hour - hours, draw.minute);

/// الساعات اللي بتتكتب بإيد: رقم صحيح من ١ لـ٧٢. برّه كده غلطة كتابة —
/// مش حكم طبي، والمدة نفسها عمرها ما بتيجي مننا.
bool isTypedFastingHours(int hours) => hours >= 1 && hours <= 72;

/// بعد قد إيه من غير ميعاد نقول على الشاشة إن المتابعة واقفة.
///
/// **ده حد عرض، مش حكم على المعمل.** إحنا مش بنقول إن التحليل المفروض
/// يخلص في أسبوع — ما حدش قال لنا كده وما بنخترعش (القاعدة ٦). اللي
/// بنقوله حرفياً: «المتابعة دي واقفة عند المرحلة دي من أسبوع ومفيش ميعاد
/// متحطّ» — واقعة عن الشاشة، مش عن الجسم. والسطر بيفتح الشاشة عشان
/// الإنسان يحطّ الميعاد أو يكمّل، مش عشان يتوبّخ.
const Duration checkupStalledAfter = Duration(days: 7);

/// المتابعة واقفة: المرحلة الحالية بتسأل عن تاريخ، والتاريخ فاضي، وعدّى
/// عليها [checkupStalledAfter] من غير حركة.
bool checkupIsStalled({
  required CheckupStage stage,
  required DateTime? stageSince,
  required DateTime? stageDate,
  required DateTime now,
}) {
  if (!stage.asksForDate || stageDate != null || stageSince == null) return false;
  return !now.isBefore(stageSince.add(checkupStalledAfter));
}
