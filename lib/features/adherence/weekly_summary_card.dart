import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/repositories/records_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/adherence/weekly_summary.dart';
import '../../domain/scheduling/routine_day.dart';
import 'summary_range.dart';
import 'weekly_summary_sources.dart';

/// **ملخص الأسبوع** بمقاسات المريض — عنده في «ملفّي»، وعند الممرض فوق «يومك».
/// أربع سطور، كل واحد بأيقونته وكلمته. **مفيش لون حكم**: اللي ما اتأكدش
/// بيتقال بالكلام، والدهبي محجوز للي محتاج انتباه **دلوقتي**.
class WeeklySummaryCard extends StatelessWidget {
  const WeeklySummaryCard({required this.summary, this.onPickRange, super.key});

  final WeeklySummary summary;

  /// «غيّر المدة» (المالك، ٥ أكتوبر مساءً) — null = من غير زرار.
  final VoidCallback? onPickRange;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return FCard(
      key: const ValueKey('weekly-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  s.title,
                  key: const ValueKey('weekly-summary-title'),
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w800, color: F.ink, height: 1.4),
                ),
              ),
              if (onPickRange case final pick?) ...[
                const SizedBox(width: F.s8),
                SummaryRangeButton(onTap: pick),
              ],
            ],
          ),
          const SizedBox(height: F.s8),
          _Line(icon: Icons.check_circle_outline, text: s.dosesLine),
          if (s.missedLine.isNotEmpty) _Line(icon: Icons.schedule, text: s.missedLine),
          _Line(icon: Icons.inventory_2_outlined, text: s.lowStockLine),
          _Line(icon: Icons.event_outlined, text: s.appointmentLine),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: F.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(icon, size: 22, color: F.mutedDark),
            ),
            const SizedBox(width: F.s8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5)),
            ),
          ],
        ),
      );
}

/// على موبايل المريض («ملفّي») — من القاعدة المحلية، وبيتحدّث مع كل كتابة.
class PatientWeeklySummary extends StatefulWidget {
  const PatientWeeklySummary({this.now, super.key});

  /// للاختبارات.
  final DateTime? now;

  @override
  State<PatientWeeklySummary> createState() => _PatientWeeklySummaryState();
}

class _PatientWeeklySummaryState extends State<PatientWeeklySummary> {
  /// المدة المختارة — الافتراضي آخر ٧ أيام كاملة، زي ما كان.
  SummaryRange? _range;
  StreamSubscription<List<DoseEventView>>? _weekSub;
  StreamSubscription<List<MedicationStockView>>? _stockSub;
  StreamSubscription<List<RecordRow>>? _recordsSub;
  List<DoseEventView>? _week;
  List<MedicationStockView> _stock = const [];
  List<RecordRow> _records = const [];

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_weekSub != null) return;
    final services = AppScope.of(context);
    _range ??= SummaryRange.lastWeek(routineDayOf(_now));
    _watchRange(services);
    _stockSub = StockRepository(services.db).watch(services.patientId).listen((rows) {
      if (mounted) setState(() => _stock = rows);
    });
    _recordsSub = RecordsRepository(services.db).watchAll(services.patientId).listen((rows) {
      if (mounted) setState(() => _records = rows);
    });
  }

  void _watchRange(AppServices services) {
    _weekSub?.cancel();
    _weekSub = services.events.watchRoutineDays(_range!.from, _range!.to).listen((rows) {
      if (mounted) setState(() => _week = rows);
    });
  }

  Future<void> _pickRange() async {
    final picked = await pickSummaryRange(
      context,
      today: routineDayOf(_now),
      current: _range!,
    );
    if (picked == null || !mounted || picked == _range) return;
    setState(() {
      _range = picked;
      _week = null; // لسه بنقرا المدة الجديدة — الكارت بيستنى الصفوف
    });
    _watchRange(AppScope.of(context));
  }

  @override
  void dispose() {
    _weekSub?.cancel();
    _stockSub?.cancel();
    _recordsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;
    // قبل ما الجرعات توصل مفيش كارت — «مفيش جرعات» قبل القراية كانت هتكدب
    if (week == null) return const SizedBox.shrink();
    final now = _now;
    return WeeklySummaryCard(
      onPickRange: _pickRange,
      summary: summaryFromLocal(
        week: week,
        stock: _stock,
        records: _records,
        today: routineDayOf(now),
        now: now,
        from: _range!.from,
        to: _range!.to,
      ),
    );
  }
}

/// **من الصورة، بمدة بتتغيّر** — الممرض فوق «يومك». الصورة فيها آخر ٨
/// أيام بس، فالبكر بتعرض الأيام دي ([snapshotDaysBack]) — أوسع من كده
/// محتاج توسيع قراية السحابة، وده قرار تكلفة مش جولة عرض.
const int snapshotDaysBack = 7;

class SnapshotWeeklySummary extends StatefulWidget {
  const SnapshotWeeklySummary({required this.summaryFor, required this.today, super.key});

  /// بيحسب الملخص للمدة — من `summaryFromSnapshot(s, t, from:, to:)`.
  final WeeklySummary Function(SummaryRange range) summaryFor;
  final DateTime today;

  @override
  State<SnapshotWeeklySummary> createState() => _SnapshotWeeklySummaryState();
}

class _SnapshotWeeklySummaryState extends State<SnapshotWeeklySummary> {
  late SummaryRange _range = SummaryRange.lastWeek(widget.today);

  Future<void> _pick() async {
    final picked = await pickSummaryRange(context, today: widget.today, current: _range, daysBack: snapshotDaysBack);
    if (picked != null && mounted) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) =>
      WeeklySummaryCard(summary: widget.summaryFor(_range), onPickRange: _pick);
}
