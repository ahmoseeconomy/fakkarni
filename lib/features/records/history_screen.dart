import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/records_repository.dart';
import 'deleted_row.dart';
import 'manual_entry_screen.dart';
import 'record_kinds.dart';

/// «الحالات السابقة» (المخطط ٢٩): خط زمني بالترتيب (الأحدث فوق)، فلتر
/// بالنوع وبالفترة. الممسوح بيفضل على الخط مشطوب ومعاه «↺ رجّعه».
///
/// «إيقاف دوا» اللي في التصميم جاي من الأدوية مش من السجلات — مش هنا.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({this.today, super.key});

  /// للاختبارات.
  final DateTime? today;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Stream<List<RecordRow>>? _records;
  RecordKind? _kind;
  RecordPeriod _period = RecordPeriod.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    _records ??= RecordsRepository(services.db).watchAll(services.patientId);
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.today ?? DateTime.now();
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الحالات السابقة')),
      body: StreamBuilder<List<RecordRow>>(
        stream: _records,
        builder: (context, snap) {
          final all = snap.data;
          final shown = [
            for (final r in all ?? const <RecordRow>[])
              if ((_kind == null || r.kind == _kind) && _period.includes(r.happenedAt, now)) r,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
            children: [
              Text(
                'كل اللي حصل — بالتاريخ والدكتور والنتيجة.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
              ),
              const SizedBox(height: F.s12),
              Wrap(
                spacing: F.s8,
                runSpacing: F.s8,
                children: [
                  AnchorChip(label: 'الكل', selected: _kind == null, onTap: () => setState(() => _kind = null)),
                  for (final k in RecordKind.values)
                    AnchorChip(
                      key: ValueKey('filter-${k.name}'),
                      label: k.plural,
                      selected: _kind == k,
                      onTap: () => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: F.s12),
              const SectionHead('الفترة'),
              const SizedBox(height: F.s8),
              Wrap(
                spacing: F.s8,
                runSpacing: F.s8,
                children: [
                  for (final p in RecordPeriod.values)
                    AnchorChip(
                      key: ValueKey('period-${p.name}'),
                      label: p.label,
                      selected: _period == p,
                      onTap: () => setState(() => _period = p),
                    ),
                ],
              ),
              const SizedBox(height: F.gap),
              if (all == null)
                const SizedBox.shrink()
              else if (all.isEmpty) ...[
                const RecordsEmpty(
                  how: 'اللي بتسجّله من زيارات وتحاليل وأشعة بيتحط هنا بالترتيب.',
                ),
                const SizedBox(height: F.s12),
                FSecondaryButton(
                  label: '+ ضيف',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ManualEntryScreen(today: widget.today)),
                  ),
                ),
              ] else if (shown.isEmpty)
                const RecordsEmpty(
                  title: 'مفيش حاجة في الفلتر ده',
                  how: 'جرّب «الكل» في النوع أو في الفترة.',
                )
              else
                for (final (i, r) in shown.indexed)
                  _TimelineEntry(
                    record: r,
                    last: i == shown.length - 1,
                    onRestore: () => RecordsRepository(services.db).restore(r.id),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.record, required this.last, required this.onRestore});

  final RecordRow record;
  final bool last;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final lines = [?r.doctor, ?r.place].join(' — ');
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(arabicDate(r.happenedAt), style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
        Text(
          r.title,
          textDirection: nameDirection(r.title),
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
        ),
        if (lines.isNotEmpty)
          Text(lines, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
        if (r.notes != null)
          Text(
            r.notes!,
            textDirection: nameDirection(r.notes!),
            // اللاتيني LTR بس لازق في يمين العمود زي باقي السطور
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.greenDeep, height: 1.4),
          ),
      ],
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: F.cardGround,
                    border: Border.all(color: F.line),
                    borderRadius: BorderRadius.circular(F.radiusTile),
                  ),
                  child: Icon(r.kind.icon, size: 22, color: r.deletedAt == null ? F.green : F.mutedLight),
                ),
                if (!last) Expanded(child: Container(width: 2, color: F.line)),
              ],
            ),
          ),
          const SizedBox(width: F.s10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: F.gap),
              child: r.deletedAt == null ? content : DeletedRecord(onRestore: onRestore, child: content),
            ),
          ),
        ],
      ),
    );
  }
}
