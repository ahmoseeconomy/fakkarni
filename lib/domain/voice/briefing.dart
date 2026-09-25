// ملخص اليوم (القسم ١١ من السكريبت) — دارت نقية.
//
// **بيتقال بصوت الموبايل (TTS) بس**: فيه أسماء أدوية وساعات بتتغيّر كل يوم،
// فمفيش تسجيل ليه. القوالب من السكريبت بالحرف، والأرقام اللي بتتحط فيها من
// بيانات الموبايل **المحلية** — مفيش ذكاء ولا سيرفر.
//
// **ولا نصيحة طبية**: عدّ ومواعيد وتشجيع. `voice_banned_words_test` بيمشي
// على كل ناتج من هنا بعيّنات.

import '../../core/format/arabic_time.dart';
import 'voice_time.dart';

/// امبارح — من حساب «إنت ماشي إزاي» نفسه (قواعد الأيام زي ما هي).
enum YesterdayOutcome {
  /// كل جرعة مستحقة اتاخدت — «برافو».
  complete,

  /// جرعة فاتت — «النهارده يوم جديد».
  missed,

  /// مفيش جرعات امبارح، أو لسه أول يوم — مفيش جملة عنه.
  nothing,
}

class BriefingAppointment {
  const BriefingAppointment({required this.kind, required this.at});

  /// «دكتور» / «تحليل» — كلمة الميعاد زي ما بتتقال.
  final String kind;
  final DateTime at;
}

class BriefingInput {
  const BriefingInput({
    required this.now,
    required this.dosesToday,
    this.firstDoseAt,
    this.firstDoseWording,
    this.appointments = const [],
    this.yesterday = YesterdayOutcome.nothing,
    this.streak = 0,
  });

  final DateTime now;

  /// عدد **لحظات** التذكير النهارده (الأدوية اللي في نفس الدقيقة لحظة واحدة).
  final int dosesToday;

  /// أول جرعة النهارده وكلامها («بعد الفطار بنص ساعة») — null لو مفيش.
  final DateTime? firstDoseAt;
  final String? firstDoseWording;

  final List<BriefingAppointment> appointments;
  final YesterdayOutcome yesterday;

  /// الأيام ورا بعض بعد امبارح كامل.
  final int streak;
}

String _greeting(DateTime now) => now.hour >= 4 && now.hour < 12 ? 'صباح الخير' : 'مساء الخير';

/// «٣ أدوية» / «دواين» / «دوا واحد».
String dosesWord(int n) => switch (n) {
      1 => 'دوا واحد',
      2 => 'دواين',
      >= 3 && <= 10 => '${arabicNumber(n)} أدوية',
      _ => '${arabicNumber(n)} دوا',
    };

/// «رابع يوم» — ترتيب بالكلام لحد عشرة، وبعدها بالرقم.
String ordinalDay(int n) => switch (n) {
      1 => 'أول يوم',
      2 => 'تاني يوم',
      3 => 'تالت يوم',
      4 => 'رابع يوم',
      5 => 'خامس يوم',
      6 => 'سادس يوم',
      7 => 'سابع يوم',
      8 => 'تامن يوم',
      9 => 'تاسع يوم',
      10 => 'عاشر يوم',
      _ => 'يوم ${arabicNumber(n)}',
    };

/// الملخص كله، جملة ورا جملة — أو null لو مفيش حاجة تتقال (يوم من غير
/// أدوية ولا مواعيد ولا امبارح): **ما بنتكلمش عشان نتكلم.**
String? briefingText(BriefingInput b) {
  final parts = <String>[];

  if (b.dosesToday > 0) {
    final first = b.firstDoseAt;
    var s = 'النهارده عندك ${dosesWord(b.dosesToday)}';
    if (first != null) {
      s += '، ${b.dosesToday == 1 ? 'معادها' : 'أولها'} الساعة ${voiceTime(first)}';
      if (b.firstDoseWording case final w? when w.isNotEmpty) s += ' $w';
    }
    parts.add('$s.');
  }

  for (final a in b.appointments) {
    parts.add('وعندك ميعاد ${a.kind} الساعة ${voiceTime(a.at)}.');
  }

  switch (b.yesterday) {
    case YesterdayOutcome.complete:
      var s = 'امبارح خدت كل أدويتك في معادها. برافو';
      if (b.streak >= 2) s += '، دي ${ordinalDay(b.streak)} ورا بعض';
      parts.add('$s.');
    case YesterdayOutcome.missed:
      parts.add('النهارده يوم جديد، وأنا معاك.');
    case YesterdayOutcome.nothing:
      break;
  }

  if (parts.isEmpty) return null;
  return '${_greeting(b.now)}. ${parts.join(' ')}';
}
