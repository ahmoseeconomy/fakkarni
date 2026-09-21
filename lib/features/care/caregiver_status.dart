import '../../data/care/caregiver_remote.dart';
import '../../data/dose_state.dart';

/// **الحساب اللي شاشة الابن بتبدأ بيه — دوال نقية، من غير أي ودجت.**
///
/// الابن بيفتح التطبيق تلات ثواني وعايز إجابة سؤال واحد: «بابا كويس؟».
/// الملف ده بيطلع الإجابة من نفس الصورة اللي الشاشة بتقراها — **من غير أي
/// استعلام جديد ومن غير أي عمود جديد**. اللي مش موجود في الصورة مش
/// بيتخترع هنا.
///
/// نقي عشان يتختبر من غير ما نرسم شاشة: الحالات الحدّية (يوم فاضي، جرعة
/// جاية، جرعة فاتت، أسبوع ناقص) أسهل تتكتب كأرقام من إنها تتلقّط بالعين.

/// إجابة السؤال، في كلمة.
enum CareState {
  /// مفيش حاجة مفتوحة — ولا تنبيه ولا جرعة عدّى وقتها.
  allGood,

  /// فيه تنبيه مفتوح، أو جرعة عدّى وقتها من غير تأكيد.
  needsAttention,

  /// مفيش ولا صف من موبايل الأب — مش «تمام» ومش «مش تمام».
  noData,
}

/// حالة الجرعة زي ما الشاشة بتعرضها — **أيقونة وكلمة، مش لون لوحده**.
enum DoseLook { taken, skipped, unconfirmed, upcoming }

/// هل الحالة دي «لسه محتاجة حد»؟ بتمرّ على نفس التعريف الشامل بتاع
/// [isOpenDoseState] عشان الشاشة والسيرفر يقولوا نفس الحاجة.
bool _openWire(String wire) {
  final state = DoseState.values.asNameMap()[wire];
  // حالة مش معروفة = **مش** مفتوحة: نفس قاعدة `alert.open`.
  return state != null && isOpenDoseState(state);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// شكل الجرعة على الشاشة — بيتحسب مرة واحدة هنا، والصف والملخّص بيقروه.
DoseLook doseLook(CaregiverDoseEvent event, DateTime now) => switch (event.state) {
      'taken' => DoseLook.taken,
      'skipped' => DoseLook.skipped,
      'missed' => DoseLook.unconfirmed,
      _ when event.scheduledAt.isBefore(now) => DoseLook.unconfirmed,
      _ => DoseLook.upcoming,
    };

/// ملخّص أعلى الشاشة.
class CareStatus {
  const CareStatus({
    required this.state,
    required this.openAlerts,
    required this.unconfirmedToday,
    required this.takenToday,
    required this.dosesToday,
    required this.lastTaken,
    required this.completeDays,
    required this.daysWithDoses,
  });

  final CareState state;

  /// تنبيهات السيرفر المفتوحة — دي أعجل حاجة على الشاشة.
  final int openAlerts;

  /// جرعات النهارده اللي عدّى وقتها من غير تأكيد (أو الجهاز كتبها «اتنست»).
  final int unconfirmedToday;

  final int takenToday;
  final int dosesToday;

  /// آخر جرعة **اتأكّدت** — النهارده أو قبلها. null يعني مفيش في الصورة.
  final CaregiverDoseEvent? lastTaken;

  /// أيام كل جرعاتها اتقفلت، من آخر [daysWithDoses] يوم **قبل النهارده**.
  final int completeDays;

  /// كام يوم من السبعة اللي فاتوا فيه جرعات أصلاً. صفر = مفيش كلام نقوله.
  final int daysWithDoses;
}

/// آخر كام يوم بنقيس عليهم الالتزام. الصورة نفسها بتجيب ٧ أيام من
/// `dose_events`، فالرقم ده حد الداتا مش اختيار.
const int adherenceDays = 7;

CareStatus careStatus(CaregiverSnapshot snapshot, DateTime now) {
  final today = _day(now);
  final events = snapshot.events;
  final openAlerts = snapshot.alerts.where((a) => a.open).length;

  var unconfirmed = 0, taken = 0, todayCount = 0;
  CaregiverDoseEvent? lastTaken;
  for (final e in events) {
    if (_day(e.scheduledAt) == today) {
      todayCount++;
      switch (doseLook(e, now)) {
        case DoseLook.unconfirmed:
          unconfirmed++;
        case DoseLook.taken:
          taken++;
        case DoseLook.skipped:
        case DoseLook.upcoming:
          break;
      }
    }
    if (e.state == 'taken') {
      final at = e.actedAt ?? e.scheduledAt;
      final best = lastTaken == null ? null : (lastTaken.actedAt ?? lastTaken.scheduledAt);
      if (best == null || at.isAfter(best)) lastTaken = e;
    }
  }

  // **الالتزام على الأيام اللي خلصت بس.** النهارده لسه ماشي — عدّه ناقص
  // بيخلّي كل يوم يبان «مش كامل» لحد آخره، وده رقم بيكدب.
  var complete = 0, withDoses = 0;
  for (var back = 1; back <= adherenceDays; back++) {
    final day = today.subtract(Duration(days: back));
    final ofDay = [for (final e in events) if (_day(e.scheduledAt) == day) e];
    if (ofDay.isEmpty) continue;
    withDoses++;
    if (!ofDay.any((e) => _openWire(e.state))) complete++;
  }

  final state = events.isEmpty && snapshot.alerts.isEmpty
      ? CareState.noData
      : (openAlerts > 0 || unconfirmed > 0 ? CareState.needsAttention : CareState.allGood);

  return CareStatus(
    state: state,
    openAlerts: openAlerts,
    unconfirmedToday: unconfirmed,
    takenToday: taken,
    dosesToday: todayCount,
    lastTaken: lastTaken,
    completeDays: complete,
    daysWithDoses: withDoses,
  );
}
