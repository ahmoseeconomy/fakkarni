import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/records_repository.dart';
import '../../data/services/checkup_service.dart';
import '../../domain/health/follow_up.dart';
import '../doctor/doctor_page_screen.dart';
import '../export/export_screen.dart';
import 'calendar_screen.dart';
import 'checkup_screen.dart';
import 'records_empty.dart';
import 'history_screen.dart';
import 'manual_entry_screen.dart';
import 'attachment_viewer.dart';
import 'start_follow_up.dart';
import 'record_kinds.dart';

/// «الملف الصحي» (المخطط ١٣): بحث بالاسم والدكتور والتاريخ، و«⋯ خيارات»
/// لكل صف → «امسحه» بتأكيد.
///
/// **الشاشة دي بتفرّج وبتتابع، ما بتضيفش.** «صوّر تقرير تحليل» كانت هنا
/// كمان وهي أصلاً في شيت «ضيف» — والإضافة عايشة هناك. بابين لنفس الحاجة
/// بيخلّوا الواحد يسأل هما اتنين ولا واحدة.
///
/// المسح بيمسح: الصف بيختفي من هنا في لحظته. مفيش شاشة
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
  /// **تلات طرق تبدأ بيها متابعة** — من الملف، من صورة جديدة، أو بالإيد.
  Future<void> _startFollowUp(FollowKind kind) async {
    final way = await askStartWay(context, kind);
    if (way == null || !mounted) return;
    switch (way) {
      case StartFollowUpWay.fromFile:
        await _startFromFile(kind);
      case StartFollowUpWay.fromPhoto:
        await _startFromPhoto(kind);
      case StartFollowUpWay.byHand:
        await _startByHand(kind);
    }
  }

  /// السجل اللي في الملف معاه بياناته خلاص — الاسم والدكتور والتاريخ —
  /// فالمتابعة بتشيلهم وما بنسألش عن حاجة إحنا عارفينها.
  Future<void> _startFromFile(FollowKind kind) async {
    final picked = await pickSource(context, kind, today: widget.today);
    if (picked == null || !mounted) return;
    if (picked.alreadyFollowed) {
      // ورقة واحدة بمتابعة واحدة — بنفتح اللي موجودة مش بنبدأ تانية.
      final open = await AppScope.of(context).checkups.openFollowUpFor(picked.recordId);
      if (open != null && mounted) _openCheckup(open.id);
      return;
    }
    await _startFrom(picked.recordId, kind);
  }

  Future<void> _startFromPhoto(FollowKind kind) async {
    final recordId = await scanForFollowUp(context, kind, today: widget.today);
    if (recordId == null || !mounted) return;
    await _startFrom(recordId, kind);
  }

  Future<void> _startFrom(int sourceId, FollowKind kind) async {
    final services = AppScope.of(context);
    final source = await (services.db.select(services.db.records)
          ..where((t) => t.id.equals(sourceId)))
        .getSingleOrNull();
    if (source == null || !mounted) return;
    final id = await services.checkups.start(
      patientId: services.patientId,
      kind: kind,
      title: followTitleFrom(kind, source),
      doctor: source.doctor,
      place: source.place,
      happenedAt: source.happenedAt,
      fromRecordId: sourceId,
      today: widget.today ?? DateTime.now(),
    );
    if (mounted) _openCheckup(id);
  }

  Future<void> _startByHand(FollowKind kind) async {
    final services = AppScope.of(context);
    final result = await showDialog<({String title, String doctor})>(
      context: context,
      builder: (_) => _StartCheckupDialog(kind: kind),
    );
    if (result == null || result.title.trim().isEmpty || !mounted) return;
    final id = await services.checkups.start(
      patientId: services.patientId,
      kind: kind,
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
    final attachments = AppScope.of(context).attachments;
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
                // **الخسارة بتتقال قبل الدوسة، مش بعدها.** مفيش مهلة ٣٠
                // يوم دلوقتي، فالجملة الوحيدة اللي بتحمي حد هي دي — واللي
                // مالوش رجعة فيها (الصورة) بيتسمّى بالاسم.
                content: Text(
                  record.attachmentPath == null
                      ? 'هيتشال من الملف خالص، ومفيش رجوع.'
                      : 'هيتشال من الملف خالص، ومعاه الصورة المرفقة. مفيش رجوع.',
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
            // عن طريق المتابعة: لو السجل ده عليه تذكيرات بتتلغي معاه
            if (yes ?? false) await checkups.delete(record.id, attachments: attachments);
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
            padding: EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
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
                  Expanded(
                    child: FSecondaryButton(
                      key: const ValueKey('start-follow-lab'),
                      label: FollowKind.lab.startLabel,
                      onPressed: () => _startFollowUp(FollowKind.lab),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: F.s10),
              Row(
                children: [
                  Expanded(
                    child: FSecondaryButton(
                      key: const ValueKey('start-follow-visit'),
                      label: FollowKind.visit.startLabel,
                      onPressed: () => _startFollowUp(FollowKind.visit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: F.s6),
              // سطر واحد بيقول الزرارين بيعملوا إيه — «تابع تحليل» لوحدها
              // ممكن تتقري «سجّل تحليل».
              Text(
                'نمشي معاك من طلب الدكتور لحد ما النتيجة توصله، ومن حجز الزيارة لحد ما تتم.',
                key: const ValueKey('follow-lab-why'),
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
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
                      child: Row(
                              children: [
                                Expanded(
                                  // المتابعة بتفتح شاشتها زي ما هي؛ غير كده
                                  // السجل اللي ليه صورة بيفتحها ملء الشاشة،
                                  // واللي مالوش صورة ما بيتفتحش — من غير
                                  // إطار فاضي ولا زرار ما بيعملش حاجة.
                                  child: switch ((r.checkupStage, r.attachmentPath)) {
                                    (final int _, _) => InkWell(
                                        key: ValueKey('checkup-open-${r.id}'),
                                        onTap: () => _openCheckup(r.id),
                                        child: RecordSummary(record: r),
                                      ),
                                    (null, final String _) => InkWell(
                                        key: ValueKey('record-photo-${r.id}'),
                                        onTap: () => openAttachment(context, r),
                                        child: RecordSummary(record: r),
                                      ),
                                    _ => RecordSummary(record: r),
                                  },
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
        // النوع بيحدد عدد المراحل: التحليل سبعة، والزيارة تلاتة.
        if (CheckupService.stageOf(r) case final stage?)
          Text(
            'متابعة ${CheckupService.kindOf(r).word} — ${arabicNumber(stage.number)} '
            'من ${arabicNumber(CheckupService.kindOf(r).stages.length)}: ${stage.label}',
            style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenDeep, height: 1.4),
          ),
      ],
    );
  }
}

class _StartCheckupDialog extends StatefulWidget {
  const _StartCheckupDialog({required this.kind});

  final FollowKind kind;

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
        title: Text(
          widget.kind == FollowKind.lab ? 'متابعة تحليل جديدة' : 'متابعة زيارة جديدة',
          style: const TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('checkup-title'),
              controller: _title,
              style: const TextStyle(fontSize: F.minBodySize),
              decoration: InputDecoration(
                labelText: widget.kind == FollowKind.lab ? 'اسم الفحص' : 'الزيارة عند مين؟',
                hintText: widget.kind == FollowKind.lab ? 'مثلاً: صورة دم كاملة' : 'مثلاً: د. حسام',
              ),
            ),
            // الزيارة اسمها هو الدكتور نفسه، فمفيش حقل تاني يتكتب مرتين.
            if (widget.kind == FollowKind.lab)
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
                onPressed: () => Navigator.of(context).pop((
                  title: _title.text,
                  doctor: widget.kind == FollowKind.lab ? _doctor.text : _title.text,
                )),
              ),
            ],
          ),
        ],
      );
}
