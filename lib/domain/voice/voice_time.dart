// الساعة زي ما بتتقال بالصوت — دارت نقية، **للرفيق الصوتي بس**.
//
// `spokenTime` في `core/format/arabic_time.dart` بتقول «٥:٠٠ بالليل» للساعة
// ٥ العصر، وهي على الشاشات وممكن في نصوص الإشعارات — ما تتلمسش. دي صيغة
// تانية للكلام المسموع: أجزاء اليوم المصرية، والدقايق بالربع والنص.

import '../../core/format/arabic_time.dart';

/// «الصبح» / «الضهر» / «العصر» / «المغرب» / «بالليل» — بالساعة (٠–٢٣).
String voiceDayPart(int hour) => switch (hour) {
      >= 4 && <= 11 => 'الصبح',
      >= 12 && <= 14 => 'الضهر',
      >= 15 && <= 17 => 'العصر',
      >= 18 && <= 19 => 'المغرب',
      _ => 'بالليل',
    };

/// «٥ العصر» / «٥ ونص العصر» / «٥ وربع العصر» / «٦ إلا ربع المغرب» /
/// «٥ و٢٠ دقيقة العصر». في «إلا ربع» الساعة المنطوقة هي الجاية، وجزء
/// اليوم بيتبعها — ١٧:٤٥ بتتقال «٦ إلا ربع المغرب»، مش «٦ إلا ربع العصر».
String voiceTime(DateTime t) {
  var hour = t.hour;
  final minute = t.minute;
  String suffix;
  if (minute == 0) {
    suffix = '';
  } else if (minute == 15) {
    suffix = ' وربع';
  } else if (minute == 30) {
    suffix = ' ونص';
  } else if (minute == 45) {
    suffix = ' إلا ربع';
    hour = (hour + 1) % 24;
  } else {
    suffix = ' و${arabicNumber(minute)} دقيقة';
  }
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '${arabicNumber(h12)}$suffix ${voiceDayPart(hour)}';
}
