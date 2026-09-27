// رد السحابة (أداة + خانات) → نفس [VoiceCommand] بتاع القارئ المحلي —
// **بتحقّق صارم**: خانة غلط الشكل أو أداة ناقصة خانتها الأساسية = مش مفهوم.
// دارت نقية.

import '../../domain/medication/medicine_name.dart';
import '../../ai/command_reader.dart';
import '../../domain/medication/meal_relation.dart';
import '../../domain/voice/answer_parser.dart';
import 'command_parser.dart';

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _clock = RegExp(r'^(\d{1,2}):(\d{2})$');

DateTime? _date(Object? v) {
  if (v is! String) return null;
  final m = _isoDate.firstMatch(v);
  if (m == null) return null;
  final d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  // ٢٠٢٦-٠٢-٣٠ بيلف لمارس — مرفوض
  if (d.month != int.parse(m.group(2)!) || d.day != int.parse(m.group(3)!)) return null;
  return d;
}

SpokenTime? _time(Object? v) {
  if (v is! String) return null;
  final m = _clock.firstMatch(v);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return SpokenTime(h, mi);
}

int? _int(Object? v, {int min = 1, int max = 1000}) {
  if (v is! num || v != v.roundToDouble()) return null;
  final n = v.round();
  return n < min || n > max ? null : n;
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

List<T>? _list<T>(Object? v, T? Function(Object) each) {
  if (v is! List || v.isEmpty) return null;
  final out = <T>[];
  for (final e in v) {
    final x = each(e);
    if (x == null) return null;
    out.add(x);
  }
  return out;
}

/// كلمة الأكل من السحابة → كلمة تعليمات (مش ساعة): الساعة بتتسأل بعدها.
const _mealOf = <String, MealRelation>{
  'before_meal': MealRelation.before,
  'with_meal': MealRelation.with_,
  'after_meal': MealRelation.after,
  'empty_stomach': MealRelation.emptyStomach,
};

/// null = الرد مش صالح — بيتعامل معاه كمش مفهوم، مش كأمر ناقص.
VoiceCommand? commandFromCloudTool(CloudTool t, {required DateTime now}) {
  final a = t.args;
  switch (t.tool) {
    case 'unknown':
      return VoiceCommand.unknown;
    case 'medical_question':
      return VoiceCommand.medical;
    case 'next_dose':
      return const VoiceCommand(CommandIntent.nextDose);
    case 'today_list':
      return const VoiceCommand(CommandIntent.todayList);
    case 'upcoming_appointments':
      return const VoiceCommand(CommandIntent.upcomingAppointments);
    case 'stock_status':
      return const VoiceCommand(CommandIntent.stockStatus);
    case 'mark_taken':
      final name = _str(a['med_name']);
      return VoiceCommand(CommandIntent.markTaken, medWords: name == null ? null : normalizeArabic(name));
    case 'mark_bought':
      final name = _str(a['med_name']);
      if (name == null) return null;
      return VoiceCommand(CommandIntent.markBought, medWords: normalizeArabic(name));
    case 'snooze':
      final minutes = a['minutes'] == null ? null : _int(a['minutes'], min: 1, max: 720);
      if (a['minutes'] != null && minutes == null) return null;
      return VoiceCommand(CommandIntent.snooze, snoozeMinutes: minutes);
    case 'add_doctor_question':
      final text = _str(a['text']);
      if (text == null) return null;
      return VoiceCommand(CommandIntent.addDoctorQuestion, questionText: text);
    case 'add_vital':
      final type = VitalType.values.asNameMap()[_str(a['vital_type']) ?? ''];
      final values = _list<double>(a['values'], (e) => e is num && e > 0 ? e.toDouble() : null);
      if (type == null || values == null) return null;
      return VoiceCommand(CommandIntent.addVital, vital: SpokenVital(type, values));
    case 'add_appointment':
      final kind = AppointmentKind.values.asNameMap()[_str(a['kind']) ?? ''];
      if (kind == null) return null;
      if (a['date'] != null && _date(a['date']) == null) return null;
      if (a['time'] != null && _time(a['time']) == null) return null;
      return VoiceCommand(
        CommandIntent.addAppointment,
        appointment: SpokenAppointment(
          kind: kind,
          withWhom: _str(a['with_whom']),
          date: _date(a['date']),
          time: _time(a['time']),
          place: _str(a['place']),
        ),
      );
    case 'add_medication':
      final name = _str(a['name']);
      // «لا» / «أيوه» من السحابة مش اسم دوا — زي القارئ المحلي بالظبط
      if (name == null || isNotAMedicineName(name)) return null;
      final timings = <SpokenTiming>[];
      if (a['times'] != null) {
        final times = _list<SpokenTime>(a['times'], (e) => _time(e));
        if (times == null) return null;
        timings.addAll(times.map((t) => SpokenTiming(fixed: t)));
      }
      if (a['meal_relation'] != null) {
        final m = _mealOf[_str(a['meal_relation']) ?? ''];
        if (m == null) return null;
        timings.add(SpokenTiming(anchorWord: 'الأكل', relation: m));
      }
      final pattern = _str(a['pattern']);
      if (pattern != null && !const {'daily', 'every_n_hours', 'weekdays', 'once'}.contains(pattern)) return null;
      int? everyHours;
      if (pattern == 'every_n_hours') {
        everyHours = _int(a['every_hours'], min: 1, max: 24);
        if (everyHours == null) return null;
      }
      var weekdays = const <int>[];
      if (pattern == 'weekdays') {
        final w = _list<int>(a['weekdays'], (e) => _int(e, min: 1, max: 7));
        if (w == null) return null;
        weekdays = w;
      }
      if (a['duration_days'] != null && _int(a['duration_days'], min: 1, max: 365) == null) return null;
      if (a['start_date'] != null && _date(a['start_date']) == null) return null;
      return VoiceCommand(
        CommandIntent.addMed,
        medWords: normalizeArabic(name),
        timings: timings,
        everyHours: everyHours,
        once: pattern == 'once',
        durationDays: a['duration_days'] == null ? null : _int(a['duration_days'], min: 1, max: 365),
        startDate: _date(a['start_date']),
        weekdays: weekdays,
      );
    default:
      return null;
  }
}
