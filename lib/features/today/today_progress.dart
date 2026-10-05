import '../../data/dose_state.dart';
import '../../data/repositories/dose_event_repository.dart' show DoseEventView;
import '../../domain/escalation/dose_moment.dart';

/// **دايرة «X من Y» على «يومك»** (إعادة التصميم، ٤ أكتوبر ٢٠٢٦) — حساب بس.
///
/// اليوم يوم الروتين (بيبدأ ٤:٠٠ — نفس اليوم اللي «يومك» بتقراه)، فالدايرة
/// بتبدأ من صفر مع اليوم الجديد لوحدها.
///
/// - **Y** جرعات النهارده **من غير «مش هاخده»**، و**X** اللي اتاخد. قرار
///   إنسان إنه ما ياخدش جرعة ما بيملاش الدايرة ولا بيفضّيها (المالك).
/// - **السطر**: مفيش جرعة فاتت → «إنت ماشي كويس النهارده»؛ فاتت وفاضل →
///   «فاضل لك جرعات النهارده»؛ فاتت ومفيش فاضل → مفيش سطر والدايرة فاضلة.
///   **عمره ما يلوم**: الفايتة «ما اتأكدتش»، مش «فاتت».
/// - مفيش جرعات خالص → مفيش دايرة، والسطر «مفيش أدوية النهارده».
class TodayProgress {
  const TodayProgress({required this.taken, required this.total, required this.line});

  final int taken;
  final int total;

  /// null = مفيش سطر (فاتت ومفيش فاضل).
  final String? line;

  /// الدايرة بتظهر لو فيه جرعة محسوبة.
  bool get showsRing => total > 0;
}

const goingWellLine = 'إنت ماشي كويس النهارده';
const dosesLeftLine = 'فاضل لك جرعات النهارده';
const noDosesTodayLine = 'مفيش أدوية النهارده';

TodayProgress todayProgress(List<DoseEventView> today, DateTime now) =>
    todayProgressOf([for (final d in today) (scheduledAt: d.scheduledAt, state: d.state)], now);

/// نفس الحساب على (الميعاد، الحالة) بس — موبايل الممرض بيغذّيه من صفوف
/// الصورة (المرحلة ٤، ٥ أكتوبر ٢٠٢٦): حساب واحد للدايرة عند الاتنين.
TodayProgress todayProgressOf(List<({DateTime scheduledAt, DoseState state})> today, DateTime now) {
  if (today.isEmpty) return const TodayProgress(taken: 0, total: 0, line: noDosesTodayLine);
  final counted = [for (final d in today) if (d.state != DoseState.skipped) d];
  final taken = counted.where((d) => d.state == DoseState.taken).length;
  final open = [for (final d in counted) if (d.state != DoseState.taken) d];
  bool missed(({DateTime scheduledAt, DoseState state}) d) =>
      doseMomentOf(scheduledAt: d.scheduledAt, now: now, markedMissed: d.state == DoseState.missed) == DoseMoment.missed;
  final anyMissed = open.any(missed);
  final anyLeft = open.any((d) => !missed(d));
  final line = !anyMissed ? goingWellLine : (anyLeft ? dosesLeftLine : null);
  return TodayProgress(taken: taken, total: counted.length, line: line);
}
