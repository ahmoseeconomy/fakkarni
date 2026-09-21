import '../../data/care/caregiver_remote.dart';
import '../../data/dose_state.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';

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

// ===========================================================================
// أقسام «متابعة» — الترتيب اللي المالك طلبه، محسوب هنا مش في الودجت.
// ===========================================================================

/// جرعات اليوم متقسّمة زي ما الشاشة بتعرضها.
class CareDoseSections {
  const CareDoseSections({
    required this.missed,
    required this.upcomingToday,
    required this.tomorrow,
    required this.taken,
    required this.skipped,
  });

  /// **فاتت** — عدّى وقتها من غير تأكيد، أو جهاز الأب كتبها «اتنست».
  /// الأقدم الأول: اللي فاتت من ساعتين أهم من اللي فاتت من عشر دقايق.
  final List<CaregiverDoseEvent> missed;

  /// **جاية** — باقي النهارده، **الأقرب الأول**.
  final List<CaregiverDoseEvent> upcomingToday;

  /// وبكرة تحت عنوان يومها، الأقرب الأول برضه.
  final List<CaregiverDoseEvent> tomorrow;

  /// **اتاخدت** النهارده، **الأحدث الأول** — السؤال هو «خد آخر واحدة؟».
  final List<CaregiverDoseEvent> taken;

  /// **قرار إنسان، مش نسيان.** القايمة اللي المالك كتبها فيها تلات أقسام
  /// بس، و«مش هاخده» مش واحد فيهم: هي مش فايتة (حد قرر) ومش اتاخدت. إخفاؤها
  /// كان هيضيّع معلومة كانت بتتعرض قبل كده، وحطّها تحت «اتاخدت» كان
  /// هيخلّي العنوان يكدب. فقسم صغير لوحدها لحد ما المالك يقول.
  final List<CaregiverDoseEvent> skipped;
}

DateTime _actedOrScheduled(CaregiverDoseEvent e) => e.actedAt ?? e.scheduledAt;

CareDoseSections careDoseSections(CaregiverSnapshot snapshot, DateTime now) {
  final today = _day(now);
  final tomorrowDay = today.add(const Duration(days: 1));
  final missed = <CaregiverDoseEvent>[];
  final upcoming = <CaregiverDoseEvent>[];
  final tomorrow = <CaregiverDoseEvent>[];
  final taken = <CaregiverDoseEvent>[];
  final skipped = <CaregiverDoseEvent>[];

  for (final e in snapshot.events) {
    final day = _day(e.scheduledAt);
    if (day == tomorrowDay) {
      tomorrow.add(e);
      continue;
    }
    if (day != today) continue;
    switch (doseLook(e, now)) {
      case DoseLook.unconfirmed:
        missed.add(e);
      case DoseLook.upcoming:
        upcoming.add(e);
      case DoseLook.taken:
        taken.add(e);
      case DoseLook.skipped:
        skipped.add(e);
    }
  }

  missed.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  upcoming.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  tomorrow.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  skipped.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  // الأحدث الأول — بوقت التأكيد الحقيقي، مش بوقت الجدولة.
  taken.sort((a, b) => _actedOrScheduled(b).compareTo(_actedOrScheduled(a)));

  return CareDoseSections(
    missed: missed,
    upcomingToday: upcoming,
    tomorrow: tomorrow,
    taken: taken,
    skipped: skipped,
  );
}

/// متابعة مفتوحة زي ما الابن بيشوفها — **قراية لصف الأب، مش حساب تاني**.
class CareFollowUp {
  const CareFollowUp({
    required this.record,
    required this.kind,
    required this.stage,
    required this.stageDate,
    required this.stalled,
  });

  final CaregiverRecord record;
  final FollowKind kind;
  final FollowStage stage;

  /// ميعاد المرحلة الحالية — null يعني الأب لسه ما حطّهوش.
  final DateTime? stageDate;

  /// واقفة عند مرحلة بتسأل عن ميعاد، ومفيش ميعاد، وعدّى أسبوع.
  final bool stalled;
}

/// **نفس اختيار الأعمدة اللي `CheckupService.stageDateOf` بيعمله** —
/// معاد الزيارة بيقعد في نفس عمود «معاد الدكتور»، والصف نوعه واحد بس.
DateTime? careStageDate(CaregiverRecord r, FollowStage stage) => followStageDate(
      stage,
      labBookingAt: r.labBookingAt,
      resultReadyAt: r.resultReadyAt,
      doctorVisitAt: r.doctorVisitAt,
    );

/// المتابعات المفتوحة — أي صف جهاز الأب حاطط عليه مرحلة.
///
/// الترتيب: اللي ليه ميعاد الأول بالأقرب، وبعدين اللي من غير ميعاد.
/// متابعة من غير ميعاد مش «بعيدة»، هي **مش متحدّدة** — ورميها آخر القايمة
/// أصدق من اختراع تاريخ لها.
List<CareFollowUp> careFollowUps(CaregiverSnapshot snapshot, DateTime now) {
  final out = <CareFollowUp>[];
  for (final r in snapshot.records) {
    final kind = FollowKind.fromStored(r.followKind);
    final stage = kind.stageFromNumber(r.checkupStage);
    if (stage == null) continue;
    final date = careStageDate(r, stage);
    out.add(CareFollowUp(
      record: r,
      kind: kind,
      stage: stage,
      stageDate: date,
      stalled: followIsStalled(
        stage: stage,
        stageSince: r.checkupStageSince,
        stageDate: date,
        now: now,
      ),
    ));
  }
  out.sort((a, b) {
    final x = a.stageDate, y = b.stageDate;
    if (x == null && y == null) return a.record.title.compareTo(b.record.title);
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  });
  return out;
}

/// المتابعات اللي ليها **ميعاد جاي** — النهارده أو بعده، الأقرب الأول.
///
/// دي اللي بتطلع فوق في «متابعة»: الابن عايز يعرف إن فيه حاجة قدّامهم،
/// مش يدوّر عليها في آخر الشاشة.
List<CareFollowUp> careUpcoming(List<CareFollowUp> all, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (final f in all)
      if (f.stageDate case final at?)
        if (!DateTime(at.year, at.month, at.day).isBefore(today)) f,
  ];
}

/// الباقي — من غير ميعاد، أو ميعاده عدّى. **مفيش تكرار**: اللي فوق مش
/// بيتعاد تحت، زي ما شاشة الأب بالظبط بتعمل.
List<CareFollowUp> careRemaining(List<CareFollowUp> all, DateTime now) {
  final upcoming = {for (final f in careUpcoming(all, now)) f.record.uuid};
  return [for (final f in all) if (!upcoming.contains(f.record.uuid)) f];
}
