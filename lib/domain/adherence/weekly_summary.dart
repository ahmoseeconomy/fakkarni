import '../../core/format/arabic_time.dart';
import 'adherence.dart';

/// **ملخص الأسبوع** (طلب المدير، ٤ أكتوبر ٢٠٢٦) — دارت نقية.
///
/// آخر **٧ أيام كاملة** (من غير النهارده — اليوم لسه ماشي، وعدّه ناقص
/// بيخلّي كل أسبوع يبان مش كامل). أربع حاجات وبس: الجرعات، اللي ما
/// اتأكدش، الدوا اللي قرب يخلص، وأقرب ميعاد. **مفيش حكم ولا نصيحة**: أرقام
/// وأسامي ومواعيد. اللي فات بيتقال «ما اتأكدتش» — هو نسي، ما فشلش.
///
/// نفس الكلام للمريض («ملفّي») وللابن والممرض (فوق «متابعة» / «يومك»):
/// الجمل من غير ضمير، فبتتقري صح من الناحيتين.
class WeeklySummary {
  const WeeklySummary({
    required this.from,
    required this.to,
    required this.due,
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.lowStock,
    required this.nextAppointment,
  });

  /// أول وآخر يوم روتين في الأسبوع (الاتنين داخلين).
  final DateTime from;
  final DateTime to;

  /// كل الجرعات اللي كان معادها في الأسبوع.
  final int due;
  final int taken;
  final int skipped;

  /// اللي ما اتأكدتش — الأحدث الأول.
  final List<MissedDose> missed;
  final List<LowStockItem> lowStock;
  final UpcomingItem? nextAppointment;

  /// «ملخص الأسبوع — ٢٧ سبتمبر لـ٣ أكتوبر».
  String get title => 'ملخص الأسبوع — ${_dayMonth(from)} لـ${_dayMonth(to)}';

  /// «اتاخد ١٨ من ٢١ جرعة — و٢ متخطّية».
  String get dosesLine {
    if (due == 0) return 'مفيش جرعات كان معادها في الأسبوع ده';
    final base = 'اتاخد ${arabicNumber(taken)} من ${arabicNumber(due)} ${due == 1 ? 'جرعة' : 'جرعات'}';
    return skipped == 0 ? base : '$base — و${arabicNumber(skipped)} متخطّية';
  }

  /// «ما اتأكدتش: ٣ — Concor (الاتنين ٩:٠٠ م)، …» — لحد تلاتة وبعدين الباقي بالعدد.
  String get missedLine {
    if (due == 0) return '';
    if (missed.isEmpty) return 'كل الجرعات اتأكّدت أو اتقرر فيها';
    final shown = missed.take(_maxNamed).map((m) => '${m.medicationName} (${_when(m)})').join('، ');
    final rest = missed.length - _maxNamed;
    return 'ما اتأكدتش: ${arabicNumber(missed.length)} — $shown'
        '${rest > 0 ? ' و${arabicNumber(rest)} كمان' : ''}';
  }

  /// «قرب يخلص: Concor (فاضله ٤ أيام)» أو «مفيش دوا قرب يخلص».
  String get lowStockLine {
    if (lowStock.isEmpty) return 'مفيش دوا قرب يخلص';
    return 'قرب يخلص: ${lowStock.map((s) => '${s.name} (${_daysLeft(s.daysLeft)})').join('، ')}';
  }

  /// «أقرب ميعاد: د. حسام — الأحد ١٢ أكتوبر» أو «مفيش مواعيد جاية».
  String get appointmentLine {
    final a = nextAppointment;
    if (a == null) return 'مفيش مواعيد جاية';
    final name = a.title.trim();
    return 'أقرب ميعاد: ${name.isEmpty ? '' : '$name — '}${_dayNames[a.day.weekday]} ${_dayMonth(a.day)}';
  }

  static const _maxNamed = 3;

  static String _when(MissedDose m) => '${_dayNames[m.routineDay.weekday]} ${arabicTime(m.scheduledAt)}';

  static String _daysLeft(int? d) => switch (d) {
        null => 'فاضل قليل',
        0 => 'خلص',
        1 => 'فاضله يوم',
        2 => 'فاضله يومين',
        _ when d <= 10 => 'فاضله ${arabicNumber(d)} أيام',
        _ => 'فاضله ${arabicNumber(d)} يوم',
      };
}

class LowStockItem {
  const LowStockItem(this.name, this.daysLeft);
  final String name;

  /// null = الأيام مش محسوبة (جدول مش يومي).
  final int? daysLeft;
}

class UpcomingItem {
  const UpcomingItem(this.title, this.day);
  final String title;
  final DateTime day;
}

/// الحساب. [today] يوم الروتين بتاع النهارده — الأسبوع هو الـ٧ اللي قبله.
WeeklySummary weeklySummary({
  required List<AdherenceDose> doses,
  required DateTime today,
  List<LowStockItem> lowStock = const [],
  List<UpcomingItem> upcoming = const [],
}) {
  final t = DateTime(today.year, today.month, today.day);
  final from = DateTime(t.year, t.month, t.day - 7);
  final to = DateTime(t.year, t.month, t.day - 1);
  bool inWeek(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  var due = 0, taken = 0, skipped = 0;
  final missed = <MissedDose>[];
  for (final d in doses) {
    if (!inWeek(d.routineDay)) continue;
    due++;
    switch (d.state) {
      case AdherenceState.taken:
        taken++;
      case AdherenceState.skipped:
        skipped++;
      // يوم كامل عدّى — «لسه» ومش متأكدة واحد: ما اتأكدتش
      case AdherenceState.pending || AdherenceState.missed:
        missed.add(MissedDose(
          id: d.id,
          medicationName: d.medicationName,
          routineDay: d.routineDay,
          scheduledAt: d.scheduledAt,
        ));
    }
  }
  missed.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  UpcomingItem? next;
  for (final u in upcoming) {
    final day = DateTime(u.day.year, u.day.month, u.day.day);
    if (day.isBefore(t)) continue;
    if (next == null || day.isBefore(next.day)) next = UpcomingItem(u.title, day);
  }

  return WeeklySummary(
    from: from,
    to: to,
    due: due,
    taken: taken,
    skipped: skipped,
    missed: missed,
    lowStock: lowStock,
    nextAppointment: next,
  );
}

String _dayMonth(DateTime d) => '${arabicNumber(d.day)} ${arabicMonths[d.month - 1]}';

const _dayNames = {
  DateTime.saturday: 'السبت',
  DateTime.sunday: 'الحد',
  DateTime.monday: 'الاتنين',
  DateTime.tuesday: 'التلات',
  DateTime.wednesday: 'الأربع',
  DateTime.thursday: 'الخميس',
  DateTime.friday: 'الجمعة',
};
