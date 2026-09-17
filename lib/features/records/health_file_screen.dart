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
import '../../domain/health/checkup.dart';
import '../doctor/doctor_page_screen.dart';
import '../export/export_screen.dart';
import 'calendar_screen.dart';
import 'checkup_screen.dart';
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

  void _openCheckup(int id) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CheckupScreen(recordId: id)),
      );

  /// اسم الفحص (والدكتور لو معروف) → مرحلة ١ «طلب الطبيب».
  Future<void> _startCheckup() async {
    final services = AppScope.of(context);
    final result = await showDialog<({String title, String doctor})>(
      context: context,
      builder: (_) => const _StartCheckupDialog(),
    );
    if (result == null || result.title.trim().isEmpty || !mounted) return;
    final id = await services.checkups.start(
      patientId: services.patientId,
      title: result.title,
      doctor: result.doctor,
      today: widget.today ?? DateTime.now(),
    );
    if (mounted) _openCheckup(id);
  }

  void _add() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ManualEntryScreen(today: widget.today)),
      );

  Future<void> _options(RecordRow record) async {
    final checkups = AppScope.of(context).checkups;
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
                backgroundColor: F.dialogGround,
                title: Text(
                  'تمسح «${record.title}»؟',
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.subtitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                content: Text(
                  'هيفضل باين مشطوب وتقدر ترجّعه. بعد ${arabicNumber(RecordsRepository.retentionDays)} يوم بيتمسح نهائي.',
                  style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
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
            // عن طريق دورة الفحص: لو السجل ده عليه تذكير صيام بيتلغي معاه
            if (yes ?? false) await checkups.softDelete(record.id);
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
                style: TextStyle(fontSize: F.minBodySize, color: F.ink),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: F.mutedDark),
                  hintText: 'دوّر بالاسم أو الدكتور أو التاريخ',
                  hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  filled: true,
                  fillColor: F.railGround,
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
              Row(
                children: [
                  Expanded(
                    child: FSecondaryButton(
                      label: 'التقويم',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => CalendarScreen(today: widget.today)),
                      ),
                    ),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(child: FSecondaryButton(label: 'ابدأ دورة فحص', onPressed: _startCheckup)),
                ],
              ),
              const SizedBox(height: F.s10),
              Row(
                children: [
                  Expanded(
                    child: FSecondaryButton(
                      label: 'صفحة الطبيب',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const DoctorPageScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(
                    child: FSecondaryButton(
                      label: 'استخراج الملف',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const ExportScreen()),
                      ),
                    ),
                  ),
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
                                Expanded(
                                  child: r.checkupStage == null
                                      ? RecordSummary(record: r)
                                      : InkWell(
                                          key: ValueKey('checkup-open-${r.id}'),
                                          onTap: () => _openCheckup(r.id),
                                          child: RecordSummary(record: r),
                                        ),
                                ),
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
    final meta = [r.kind.label, ?r.doctor, arabicDate(r.happenedAt)].join(' — ');
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
                style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: F.s4),
        Text(meta, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
        if (CheckupStage.fromNumber(r.checkupStage) case final stage?)
          Text(
            'دورة فحص — ${arabicNumber(stage.number)} من ${arabicNumber(CheckupStage.values.length)}: ${stage.label}',
            style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenDeep, height: 1.4),
          ),
      ],
    );
  }
}

class _StartCheckupDialog extends StatefulWidget {
  const _StartCheckupDialog();

  @override
  State<_StartCheckupDialog> createState() => _StartCheckupDialogState();
}

class _StartCheckupDialogState extends State<_StartCheckupDialog> {
  final _title = TextEditingController();
  final _doctor = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _doctor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: const Text('دورة فحص جديدة', style: TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('checkup-title'),
              controller: _title,
              style: const TextStyle(fontSize: F.minBodySize),
              decoration: const InputDecoration(labelText: 'اسم الفحص', hintText: 'مثلاً: صورة دم كاملة'),
            ),
            TextField(
              controller: _doctor,
              style: const TextStyle(fontSize: F.minBodySize),
              decoration: const InputDecoration(labelText: 'الدكتور اللي طلبه'),
            ),
          ],
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('checkup-start'),
                label: 'ابدأ',
                onPressed: () => Navigator.of(context).pop((title: _title.text, doctor: _doctor.text)),
              ),
            ],
          ),
        ],
      );
}
