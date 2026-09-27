/// وقت في اليوم، متخزّن كدقائق من منتصف الليل (0 → 1439).
///
/// ده التمثيل الوحيد لساعة الجرعة: كل جرعة ساعة ثابتة (قرار المالك،
/// ٢٧ سبتمبر ٢٠٢٦ — مفيش روتين ولا مراسي).
class MinuteOfDay implements Comparable<MinuteOfDay> {
  const MinuteOfDay(this.minutes)
      : assert(minutes >= 0 && minutes < 1440, 'لازم تكون بين 0 و 1439');

  /// مُنشئ مريح: `MinuteOfDay.hm(7, 30)` يعني ٧:٣٠. `const` عشان الجداول
  /// الثابتة في الاختبارات والافتراضيات.
  const MinuteOfDay.hm(int hour, [int minute = 0]) : minutes = hour * 60 + minute;

  final int minutes;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  @override
  int compareTo(MinuteOfDay other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) =>
      other is MinuteOfDay && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
