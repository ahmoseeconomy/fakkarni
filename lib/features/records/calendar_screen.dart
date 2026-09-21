import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/services/checkup_service.dart';
import '../../domain/health/follow_display.dart';
import '../../data/dose_state.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/repositories/readings_repository.dart';
import '../../data/repositories/records_repository.dart';
import '../health/usual_words.dart' show GlucoseContextWords;

/// الأنواع اللي بتتفلتر في التقويم.
enum CalendarKind {
  dose('دوا'),
  visit('زيارة'),
  lab('تحليل'),
  imaging('أشعة'),
  booking('حجز'),
  glucose('سكر');

  const CalendarKind(this.label);
  final String label;
}

/// حاجة واحدة في يوم.
class CalendarEntry {
  const CalendarEntry({
    required this.kind,
    required this.at,
    required this.title,
    required this.detail,
    this.attention = false,
  });

  final CalendarKind kind;
  final DateTime at;
  final String title;
  final String detail;

  /// جرعة لسه ما اتأكدتش ومعادها عدّى — الذهبي بس هنا.
  final bool attention;
}

/// بيجمع الجرعات والسجلات والقياسات في مدخلات يوم — دالة من غير واجهة
/// عشان تتختبر لوحدها.
List<CalendarEntry> calendarEntries({
  required List<DoseEventView> doses,
  required List<RecordRow> records,
  required List<ReadingRow> readings,
  required DateTime now,
}) {
  CalendarKind? recordKind(RecordKind k) => switch (k) {
        // الروشتة ورقة أدوية — بتتفلتر مع «دوا»
        RecordKind.prescription => CalendarKind.dose,
        RecordKind.visit => CalendarKind.visit,
        RecordKind.lab => CalendarKind.lab,
        RecordKind.imaging => CalendarKind.imaging,
        RecordKind.booking => CalendarKind.booking,
      };
  return [
    for (final d in doses)
      CalendarEntry(
        kind: CalendarKind.dose,
        at: d.scheduledAt,
        title: d.medicationName,
        detail: switch (d.state) {
          DoseState.taken => 'اتاخدت ✓',
          DoseState.skipped => 'اتخطّت',
          _ when d.scheduledAt.isBefore(now) => 'لسه ما اتأكدتش',
          _ => 'معادها ${arabicTime(d.scheduledAt)}',
        },
        attention: !d.isDone && d.scheduledAt.isBefore(now),
      ),
    // **المتابعة المفتوحة بتقع على ميعاد مرحلتها، مش على `happenedAt`.**
    // `happenedAt` بتاعة صف متابعة هو يوم ما بدأت (أو تاريخ الورقة)، ولو
    // اتحط على التقويم بيقرا كأنه ميعاد — وده بالظبط العطل اللي الجولة
    // دي عن. ومتابعة مالهاش ميعاد لسه مالهاش يوم على التقويم أصلاً.
    for (final r in records)
      if (r.deletedAt == null)
        if (_followStageDate(r) case (final DateTime at, final String stage))
          CalendarEntry(
            kind: recordKind(r.kind)!,
            at: at,
            title: followDisplayTitle(CheckupService.kindOf(r), r.title),
            detail: stage,
          )
        else if (!followIsOpen(CheckupService.kindOf(r), CheckupService.stageOf(r)))
          CalendarEntry(
            kind: recordKind(r.kind)!,
            at: r.happenedAt,
            title: r.title,
            detail: [?r.doctor, ?r.place].join(' — '),
          ),
    for (final g in readings)
      CalendarEntry(
        kind: CalendarKind.glucose,
        at: g.measuredAt,
        title: 'سكر ${arabicNumber(g.valueMgDl)}',
        detail: '${g.context.label} — ${arabicTime(g.measuredAt)}',
      ),
  ]..sort((a, b) => a.at.compareTo(b.at));
}

/// ميعاد المرحلة الحالية لمتابعة مفتوحة، مع اسم المرحلة — أو null.
(DateTime, String)? _followStageDate(RecordRow r) {
  final kind = CheckupService.kindOf(r);
  final stage = CheckupService.stageOf(r);
  if (!followIsOpen(kind, stage)) return null;
  final at = CheckupService.stageDateOf(r, stage!);
  return at == null ? null : (at, stage.label);
}

/// «التقويم» (المخطط ١٢): شهر أو أسبوع، من dose_events وrecords وقياسات
/// السكر مع بعض. اليوم اللي عليه حاجات متعلّم بنقط هادية؛ ذهبي بس لو فيه
/// جرعة لسه ما اتأكدتش. اللمس بيفتح تفاصيل اليوم تحت.
///
/// **الجرعات من اللي اتنزّل فعلاً** (امبارح والنهارده وبكرة عند كل فتحة) —
/// الأيام اللي بعد كده مالهاش صفوف، والشاشة بتقول كده بدل ما تحسبها.
/// الأسبوع بيبدأ السبت. مفيش جدول جديد.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({this.today, super.key});

  /// للاختبارات.
  final DateTime? today;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  bool _month = true;
  late DateTime _selected = _dateOnly(widget.today ?? DateTime.now());
  final Set<CalendarKind> _filters = {};

  StreamSubscription<List<DoseEventView>>? _dosesSub;
  StreamSubscription<List<RecordRow>>? _recordsSub;
  StreamSubscription<List<ReadingRow>>? _readingsSub;
  List<DoseEventView> _doses = const [];
  List<RecordRow> _records = const [];
  List<ReadingRow> _readings = const [];
  (DateTime, DateTime)? _range;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _now => widget.today ?? DateTime.now();

  /// السبت اللي قبل [d] أو هو.
  static DateTime _weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday + 1) % 7);

  (DateTime, DateTime) get _visible {
    if (_month) {
      final first = DateTime(_selected.year, _selected.month, 1);
      final start = _weekStart(first);
      final nextMonth = DateTime(_selected.year, _selected.month + 1, 1);
      final end = DateTime(nextMonth.year, nextMonth.month, nextMonth.day + (7 - (nextMonth.weekday + 1) % 7) % 7);
      return (start, end);
    }
    final start = _weekStart(_selected);
    return (start, DateTime(start.year, start.month, start.day + 7));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_recordsSub != null) return;
    final services = AppScope.of(context);
    _recordsSub = RecordsRepository(services.db).watchAll(services.patientId).listen((v) {
      if (mounted) setState(() => _records = v);
    });
    _readingsSub = ReadingsRepository(services.db).watchRecent(services.patientId, limit: 1000).listen((v) {
      if (mounted) setState(() => _readings = v);
    });
    _listenDoses();
  }

  void _listenDoses() {
    final range = _visible;
    if (range == _range) return;
    _range = range;
    _dosesSub?.cancel();
    _dosesSub = AppScope.of(context).events.watchBetween(range.$1, range.$2).listen((v) {
      if (mounted) setState(() => _doses = v);
    });
  }

  @override
  void dispose() {
    _dosesSub?.cancel();
    _recordsSub?.cancel();
    _readingsSub?.cancel();
    super.dispose();
  }

  void _move(int direction) {
    setState(() {
      _selected = _month
          ? DateTime(_selected.year, _selected.month + direction, 1)
          : DateTime(_selected.year, _selected.month, _selected.day + 7 * direction);
    });
    _listenDoses();
  }

  @override
  Widget build(BuildContext context) {
    final all = calendarEntries(doses: _doses, records: _records, readings: _readings, now: _now);
    final shown = [for (final e in all) if (_filters.isEmpty || _filters.contains(e.kind)) e];
    final byDay = <DateTime, List<CalendarEntry>>{};
    for (final e in shown) {
      byDay.putIfAbsent(_dateOnly(e.at), () => []).add(e);
    }
    final (start, end) = _visible;
    final days = [
      for (var d = start; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];
    final today = _dateOnly(_now);
    final selectedEntries = byDay[_selected] ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('التقويم')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.s8, F.s4, F.s8, F.s30),
        children: [
          Row(
            children: [
              for (final (label, month) in [('شهر', true), ('أسبوع', false)]) ...[
                Expanded(
                  child: AnchorChip(
                    key: ValueKey('view-$label'),
                    label: label,
                    selected: _month == month,
                    onTap: () {
                      setState(() => _month = month);
                      _listenDoses();
                    },
                  ),
                ),
                if (month) const SizedBox(width: F.s8),
              ],
            ],
          ),
          const SizedBox(height: F.s10),
          Wrap(
            spacing: F.s6,
            runSpacing: F.s6,
            children: [
              AnchorChip(label: 'الكل', selected: _filters.isEmpty, onTap: () => setState(_filters.clear)),
              for (final k in CalendarKind.values)
                AnchorChip(
                  key: ValueKey('filter-${k.name}'),
                  label: k.label,
                  selected: _filters.contains(k),
                  onTap: () => setState(() => _filters.contains(k) ? _filters.remove(k) : _filters.add(k)),
                ),
            ],
          ),
          const SizedBox(height: F.s12),
          Row(
            children: [
              Expanded(child: FSecondaryButton(label: _month ? 'الشهر اللي فات' : 'الأسبوع اللي فات', onPressed: () => _move(-1))),
              const SizedBox(width: F.s8),
              Expanded(child: FSecondaryButton(label: _month ? 'الشهر الجاي' : 'الأسبوع الجاي', onPressed: () => _move(1))),
            ],
          ),
          const SizedBox(height: F.s10),
          Text(
            _month ? '${arabicMonths[_selected.month - 1]} ${arabicNumber(_selected.year)}' : 'أسبوع ${arabicDate(start)}',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, fontWeight: FontWeight.w700, color: F.ink),
          ),
          const SizedBox(height: F.s8),
          Row(
            children: [
              for (final name in const ['سبت', 'حد', 'اتنين', 'تلات', 'أربع', 'خميس', 'جمعة'])
                Expanded(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  ),
                ),
            ],
          ),
          const SizedBox(height: F.s4),
          for (var w = 0; w < days.length; w += 7)
            Row(
              children: [
                for (final d in days.sublist(w, w + 7))
                  Expanded(
                    child: _DayCell(
                      day: d,
                      inMonth: !_month || d.month == _selected.month,
                      selected: d == _selected,
                      today: d == today,
                      kinds: {for (final e in byDay[d] ?? const <CalendarEntry>[]) e.kind},
                      attention: (byDay[d] ?? const []).any((e) => e.attention),
                      onTap: () {
                        setState(() => _selected = d);
                        _listenDoses();
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: F.s6),
          Text(
            'الجرعات بتبان لحد بكرة بس — اللي بعد كده بيظهر لما ييجي وقته.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.gap),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: F.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  arabicDate(_selected),
                  key: const ValueKey('day-title'),
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                ),
                const SizedBox(height: F.s8),
                if (selectedEntries.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(F.gap),
                    decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
                    child: Text(
                      'مفيش حاجة في اليوم ده. الزيارات والتحاليل بتتضاف من «الملف الصحي».',
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                  )
                else
                  for (final e in selectedEntries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: F.s8),
                      child: FCard(
                        tone: e.attention ? FCardTone.attention : FCardTone.plain,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.title,
                                    textDirection: nameDirection(e.title),
                                    style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                                  ),
                                  if (e.detail.isNotEmpty)
                                    Text(e.detail, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                                ],
                              ),
                            ),
                            Text(e.kind.label, style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.green)),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.kinds,
    required this.attention,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth, selected, today, attention;
  final Set<CalendarKind> kinds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          key: ValueKey('day-${day.year}-${day.month}-${day.day}'),
          color: selected ? F.railGround : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            side: attention
                ? const BorderSide(color: F.gold, width: 2)
                : selected
                    ? BorderSide(color: F.ink, width: 1.5)
                    : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(F.radiusTile),
            onTap: onTap,
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    arabicNumber(day.day),
                    style: TextStyle(
                      fontSize: F.minTextSize,
                      fontWeight: today ? FontWeight.w800 : FontWeight.w500,
                      color: inMonth ? F.ink : F.mutedLight,
                      decoration: today ? TextDecoration.underline : null,
                    ),
                  ),
                  const SizedBox(height: F.s4),
                  SizedBox(
                    height: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final _ in kinds.take(3))
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: F.green, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
