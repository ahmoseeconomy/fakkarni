// دورة الفحص (D3.7) — دارت نقية.
//
// سبع مراحل، والمستخدم بس اللي بيحرّكها. مفيش «المتوقع ٢٤ ساعة» ولا قاعدة
// بتحكم على التأخير: ده رقم ماحدش قاله لنا.

enum CheckupStage {
  doctorOrder('طلب الطبيب'),
  labBooking('حجز المعمل'),
  preparation('التحضير'),
  sampleDraw('سحب العينة'),
  waitingResult('انتظار النتيجة'),
  resultArrived('النتيجة وصلت'),
  doctorReview('مراجعة الطبيب');

  const CheckupStage(this.label);

  final String label;

  /// ١..٧ — زي ما بيتخزّن في `records.checkup_stage`.
  int get number => index + 1;

  static CheckupStage? fromNumber(int? n) =>
      n == null || n < 1 || n > values.length ? null : values[n - 1];

  CheckupStage? get next => index + 1 < values.length ? values[index + 1] : null;
  CheckupStage? get previous => index > 0 ? values[index - 1] : null;
}

/// تذكير الصيام بيعيش لحد «سحب العينة» بس — بعدها بقى زنّ على حاجة اتعملت.
bool fastingReminderStillUseful(CheckupStage stage) => stage.number <= CheckupStage.sampleDraw.number;

/// لحظة التذكير: ميعاد السحب ناقص عدد الساعات **اللي المعمل قالها**. التقويم
/// بالـconstructor مش Duration (التوقيت الصيفي).
DateTime fastingReminderTime(DateTime draw, int hours) =>
    DateTime(draw.year, draw.month, draw.day, draw.hour - hours, draw.minute);

/// الساعات اللي بتتكتب بإيد: رقم صحيح من ١ لـ٧٢. برّه كده غلطة كتابة —
/// مش حكم طبي، والمدة نفسها عمرها ما بتيجي مننا.
bool isTypedFastingHours(int hours) => hours >= 1 && hours <= 72;
