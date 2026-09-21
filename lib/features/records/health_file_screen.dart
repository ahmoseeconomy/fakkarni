import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../domain/health/follow_display.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
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
import 'record_row_card.dart';
import 'records_of_kind_screen.dart';
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
      // **تاريخ الورقة بتاع الورقة.** كان بيتنسخ على صف المتابعة، فزيارة
      // محجوزة بكرة كانت بتتعرض «١٣ سبتمبر ٢٠٢٣» على كل شاشة بتقرا
      // `happenedAt`. المتابعة بتبدأ **النهارده** (الافتراضي في
      // `CheckupService.start`)، والورقة بتتقال كأصل في سطر تاني عن
      // طريق `followSourceId`.
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


  /// مدخل لكل نوع فيه سجلات، بعدده — والدوسة بتفتح «الحالات السابقة»
  /// على النوع ده.
  ///
  /// بنستعمل شاشة الحالات السابقة نفسها لأنها **عندها فلتر النوع أصلاً**؛
  /// قايمة تانية مخصوصة كانت هتبقى مكان تاني لنفس العرض، حرّ يختلف عنه.
  List<Widget> _kindEntries(List<RecordRow> all) {
    final counts = <RecordKind, int>{};
    for (final r in all) {
      counts[r.kind] = (counts[r.kind] ?? 0) + 1;
    }
    return [
      for (final kind in RecordKind.values)
        if (counts[kind] case final n? when n > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: F.s10),
            child: FCard(
              key: ValueKey('kind-entry-${kind.name}'),
              child: InkWell(
                borderRadius: BorderRadius.circular(F.radiusCard),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RecordsOfKindScreen(kind: kind, today: widget.today),
                )),
                child: Container(
                  constraints: const BoxConstraints(minHeight: F.minTapTarget),
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    children: [
                      Icon(kind.icon, size: 22, color: F.green),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: Text(
                          kind.plural,
                          style: TextStyle(
                            fontSize: F.minBodySize,
                            fontWeight: FontWeight.w700,
                            color: F.ink,
                          ),
                        ),
                      ),
                      Text(
                        arabicNumber(n),
                        style: TextStyle(
                          fontSize: F.minBodySize,
                          fontWeight: FontWeight.w700,
                          color: F.mutedDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ];
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
                textInputAction: TextInputAction.search,
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
              // **مداخل بدل لفّة واحدة على كل حاجة.** الملف كان بيرصّ
              // التحاليل والروشتات والزيارات والأشعة والحجوزات تحت بعض في
              // قايمة واحدة، والواحد بيدوّر بعينه. دلوقتي مدخل لكل نوع
              // بعدده، وكل مدخل بيفتح قايمته — نفس تقسيم باقي التطبيق.
              //
              // **والبحث بيفضل يدوّر في كل حاجة**: أول ما تكتب، النتايج
              // بتحلّ محل المداخل. اللي بيدوّر عارف هو عايز إيه، وتقسيمه
              // على أنواع وقتها بيبقى شغل زيادة.
              else if (_query.text.trim().isEmpty)
                ..._kindEntries(all)
              else if (shown.isEmpty)
                const RecordsEmpty(
                  title: 'مفيش حاجة بالكلام ده',
                  how: 'جرّب اسم الدكتور، أو الشهر زي «أغسطس»، أو امسح البحث.',
                )
              else
                for (final r in shown) RecordRowCard(record: r, today: widget.today),
            ],
          );
        },
      ),
    );
  }
}

/// سطرين للسجل: العنوان (بأيقونة نوعه)، و«النوع — الدكتور — التاريخ».
///
/// **المتابعة المفتوحة بتتعرض بقواعدها هي** ([RecordSummary.follow]):
/// الاسم باللي بنتابعه، والميعاد ميعاد **المرحلة الحالية** — مش
/// `happenedAt`، اللي هو تاريخ بداية المتابعة ومش ميعاد حاجة جاية.
class RecordSummary extends StatelessWidget {
  const RecordSummary({required this.record, super.key})
      : follow = false,
        now = null;

  /// صف متابعة مفتوحة. [now] مطلوبة عشان «بكرة» / «بعد بكرة».
  const RecordSummary.follow({required this.record, required DateTime this.now, super.key})
      : follow = true;

  final RecordRow record;
  final bool follow;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final stage = follow ? CheckupService.stageOf(r) : null;
    final kind = CheckupService.kindOf(r);
    // **متابعة مفتوحة ما بتعرضش `happenedAt` أبداً.** ده تاريخ بداية
    // المتابعة (أو تاريخ الورقة في الصفوف القديمة)، ومفيش شاشة المفروض
    // تقوله كأنه ميعاد جاي. المصدر واحد للناحيتين: [followDateLine].
    final meta = stage == null
        ? [r.kind.label, ?r.doctor, arabicDate(r.happenedAt)].join(' — ')
        : (r.doctor ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(r.kind.icon, size: 22, color: F.green),
            const SizedBox(width: F.s6),
            Flexible(
              child: Text(
                follow ? followDisplayTitle(kind, r.title) : r.title,
                textDirection: nameDirection(r.title),
                style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: F.s4),
        if (meta.isNotEmpty)
          Text(meta, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
        // النوع بيحدد عدد المراحل: التحليل سبعة، والزيارة تلاتة.
        if (stage != null)
          Text(
            'متابعة ${kind.word} — ${arabicNumber(stage.number)} '
            'من ${arabicNumber(kind.stages.length)}: ${stage.label} — '
            '${followDateLine(CheckupService.stageDateOf(r, stage), now!)}',
            style: const TextStyle(
                fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenDeep, height: 1.4),
          )
        else if (CheckupService.stageOf(r) case final closed?)
          // متابعة خلصت: المرحلة الأخيرة، من غير ميعاد جاي.
          Text(
            'متابعة ${kind.word} — ${closed.label}',
            style: const TextStyle(
                fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenDeep, height: 1.4),
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
              textInputAction: TextInputAction.next,
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
                textInputAction: TextInputAction.done,
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
