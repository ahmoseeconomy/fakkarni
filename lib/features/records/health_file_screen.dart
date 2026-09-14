import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/records_repository.dart';
import '../health/scan_lab_screen.dart';
import 'deleted_row.dart';
import 'history_screen.dart';
import 'manual_entry_screen.dart';
import 'record_kinds.dart';

/// «الملف الصحي» (المخطط ١٣): بحث بالاسم والدكتور والتاريخ، و«⋯ خيارات»
/// لكل صف → «امسحه» بتأكيد.
///
/// المسح ناعم: الصف بيفضل مكانه مشطوب وباهت، و«↺ رجّعه» جنبه. مفيش شاشة
/// «محذوفات» — الكلام ما بيوعدش بيها. «استخراج الملف» بييجي في D3.8،
/// و«نشطة/منتهية» بتاعة التصميم جاية من الأدوية مش السجلات فمش هنا.
class HealthFileScreen extends StatefulWidget {
  const HealthFileScreen({this.today, super.key});

  /// للاختبارات.
  final DateTime? today;

  @override
  State<HealthFileScreen> createState() => _HealthFileScreenState();
}

class _HealthFileScreenState extends State<HealthFileScreen> {
  Stream<List<RecordRow>>? _records;
  final _query = TextEditingController();

  RecordsRepository get _repo => RecordsRepository(AppScope.of(context).db);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _records ??= _repo.watchAll(AppScope.of(context).patientId);
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _add() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ManualEntryScreen(today: widget.today)),
      );

  Future<void> _options(RecordRow record) async {
    final repo = _repo;
    await FSheet.show<void>(
      context,
      title: record.title,
      children: [
        FSecondaryButton(
          key: const ValueKey('record-delete'),
          label: 'امسحه',
          onPressed: () async {
            Navigator.of(context).pop();
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.white,
                title: Text(
                  'تمسح «${record.title}»؟',
                  style: const TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.subtitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                content: Text(
                  'هيفضل باين مشطوب وتقدر ترجّعه. بعد ${arabicNumber(RecordsRepository.retentionDays)} يوم بيتمسح نهائي.',
                  style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
                ),
                actions: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FPrimaryButton(
                        key: const ValueKey('record-delete-confirm'),
                        label: 'أيوه، امسحه',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      const SizedBox(height: F.s8),
                      FSecondaryButton(label: 'لأ، سيبه', onPressed: () => Navigator.of(context).pop(false)),
                    ],
                  ),
                ],
              ),
            );
            if (yes ?? false) await repo.softDelete(record.id);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الصحي')),
      body: StreamBuilder<List<RecordRow>>(
        stream: _records,
        builder: (context, snap) {
          final all = snap.data;
          final shown = [for (final r in all ?? const <RecordRow>[]) if (matchesQuery(r, _query.text)) r];
          return ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
            children: [
              TextField(
                key: const ValueKey('records-search'),
                controller: _query,
                style: const TextStyle(fontSize: F.minBodySize, color: F.ink),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: F.mutedDark),
                  hintText: 'دوّر بالاسم أو الدكتور أو التاريخ',
                  hintStyle: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                  filled: true,
                  fillColor: F.ivoryWarm,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(F.radiusCard),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: F.s12),
              Row(
                children: [
                  Expanded(
                    child: FSecondaryButton(
                      label: 'الحالات السابقة',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => HistoryScreen(today: widget.today)),
                      ),
                    ),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(child: FSecondaryButton(label: '+ ضيف', onPressed: _add)),
                ],
              ),
              const SizedBox(height: F.s10),
              FSecondaryButton(
                label: 'صوّر تقرير تحليل',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ScanLabScreen(reader: AppScope.of(context).labReader, today: widget.today),
                  ),
                ),
              ),
              const SizedBox(height: F.gap),
              if (all == null)
                const SizedBox.shrink()
              else if (all.isEmpty)
                const RecordsEmpty(
                  how: 'دوس «+ ضيف» وسجّل زيارة أو تحليل أو أشعة. والروشتة اللي بتأكّدها بعد التصوير بتتسجّل هنا لوحدها.',
                )
              else if (shown.isEmpty)
                const RecordsEmpty(
                  title: 'مفيش حاجة بالكلام ده',
                  how: 'جرّب اسم الدكتور، أو الشهر زي «أغسطس»، أو امسح البحث.',
                )
              else
                for (final r in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: F.s10),
                    child: FCard(
                      key: ValueKey('record-${r.id}'),
                      child: r.deletedAt == null
                          ? Row(
                              children: [
                                Expanded(child: RecordSummary(record: r)),
                                const SizedBox(width: F.s8),
                                SizedBox(
                                  height: F.minTapTarget,
                                  child: TextButton(
                                    key: ValueKey('record-options-${r.id}'),
                                    onPressed: () => _options(r),
                                    style: TextButton.styleFrom(
                                      foregroundColor: F.ink,
                                      textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
                                    ),
                                    child: const Text('⋯ خيارات'),
                                  ),
                                ),
                              ],
                            )
                          : DeletedRecord(
                              onRestore: () => _repo.restore(r.id),
                              child: RecordSummary(record: r),
                            ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// سطرين للسجل: العنوان (بأيقونة نوعه)، و«النوع · الدكتور · التاريخ».
class RecordSummary extends StatelessWidget {
  const RecordSummary({required this.record, super.key});

  final RecordRow record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final meta = [r.kind.label, ?r.doctor, arabicDate(r.happenedAt)].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(r.kind.icon, size: 22, color: F.green),
            const SizedBox(width: F.s6),
            Flexible(
              child: Text(
                r.title,
                textDirection: nameDirection(r.title),
                style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: F.s4),
        Text(meta, style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
      ],
    );
  }
}
