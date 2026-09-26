import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/routine_day.dart';
import '../voice/cloud_command_budget.dart';

/// الحد اليومي لسؤال السحابة عن طلب مسموع: [limit] مرة لكل موبايل في يوم
/// **الروتين** (بيبدأ من الصحيان، مش من نص الليل — واحد بيقول «كلّمني»
/// الساعة ١ بالليل لسه في يوم امبارح). عدّاد محلي في `shared_preferences`؛
/// لما يخلص: «كفاية كده النهارده»، والطلبات المحلية شغّالة عادي.
///
/// عايش في `data/services/` مش `data/voice/`: بيقرا يوم الروتين (نقي) وحارس
/// «ملفات الصوت ما بتستوردش الجدولة» بيمشي على مجلد الصوت بالحرف.
///
/// الروتين بيتقرا مرة عند التحميل — تعديل ساعة الصحيان بعدها بيحرّك حدّ
/// اليوم بساعة أو اتنين لحد الفتحة الجاية، ومفيش أخطر من كده.
class DailyCloudBudget implements CloudCommandBudget {
  DailyCloudBudget({
    this.limit = 20,
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
  })  : _clock = clock ?? DateTime.now,
        _prefs = prefs ?? SharedPreferences.getInstance;

  static const dayKey = 'voice.cloudDay';
  static const countKey = 'voice.cloudCount';

  final int limit;
  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefs;

  DayRoutine routine = DayRoutine.fallback;
  String _day = '';
  int _count = 0;
  bool _loaded = false;

  /// بيقرا العدّاد المحفوظ — بيتنده مرة من `buildServices`.
  Future<void> load({DayRoutine? routine}) async {
    if (routine != null) this.routine = routine;
    try {
      final p = await _prefs();
      _day = p.getString(dayKey) ?? '';
      _count = p.getInt(countKey) ?? 0;
    } catch (e) {
      diag('Cmd: قراية عدّاد السحابة وقعت ($e)');
    }
    _loaded = true;
  }

  String _today() {
    final d = routineDayOf(routine, _clock());
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _roll() {
    final today = _today();
    if (today != _day) {
      _day = today;
      _count = 0;
    }
  }

  /// النهارده اتسألت كام.
  int get usedToday {
    _roll();
    return _count;
  }

  @override
  bool allowed() {
    if (!_loaded) return true; // لسه ما اتقراش — ما نحبسوش على شك
    _roll();
    return _count < limit;
  }

  @override
  void used() {
    _roll();
    _count++;
    diag('Cmd: cloud used=$_count/$limit day=$_day');
    _put();
  }

  Future<void> _put() async {
    try {
      final p = await _prefs();
      await p.setString(dayKey, _day);
      await p.setInt(countKey, _count);
    } catch (e) {
      diag('Cmd: حفظ عدّاد السحابة وقع ($e)');
    }
  }
}
