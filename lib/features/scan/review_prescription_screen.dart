import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../ai/prescription_reading.dart';
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/records_repository.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../medication/add_medication_screen.dart';
import '../medication/medication_draft.dart';
import 'debug_panel.dart';

enum ReviewResult { confirmed, retake }

/// «الذكاء يقترح، وأنت تؤكّد» (المخطط 06) — أهم شاشة في التطبيق.
///
/// ولا سطر بيتحفظ قبل دوسة. صف لكل **دوا**: الاسم، الوقت المحسوب للعرض
/// بس (عمره ما بيتخزّن)، وشريحة بتعرض **القاعدة** مش الساعة.
///
/// الصف اللي الذكاء مش متأكد منه بياخد حافة ذهبية على الجنب وسطر «مش
/// متأكد من دي — راجعها» وتحته الحقل وملاحظته. ده اعتراف بالشك — ميزة،
/// فبيتصمّم مدروس، مش مكسور.
///
/// المجهول نوعين (القاعدة ٤): اسم أو توقيت مش واضح بيقفل «تمام، ظبّطهم»؛
/// جرعة مش معروفة ما بتقفلش. و«أعدّل» بنفس الوزن البصري بالظبط — زرار
/// مليان بنفس المقاس والخط — محدش بيتدفع يأكّد جدول دوا ما قراهوش.
class ReviewPrescriptionScreen extends StatefulWidget {
  const ReviewPrescriptionScreen({
    required this.reading,
    required this.routine,
    this.today,
    super.key,
  });

  final PrescriptionReading reading;
  final DayRoutine routine;
  final DateTime? today;

  @override
  State<ReviewPrescriptionScreen> createState() => _ReviewPrescriptionScreenState();
}

class _ReviewPrescriptionScreenState extends State<ReviewPrescriptionScreen> {
  /// **الشاشة دي مسوّدة.** كل سطر هنا في الذاكرة لحد ما «تمام، ظبّطهم»
  /// تتداس — وساعتها بس بيتكتبوا كلهم مرة واحدة.
  ///
  /// قبل كده «عدّل» كانت بتحفظ فوراً و«تمام» بتحفظ الباقي، فروشتة واحدة
  /// كانت بتتكتب على مرتين من زرارين مختلفين — وده اللي خبّى ضياع الجرعات.
  late final List<_DraftLine> _lines = [
    for (final read in widget.reading.lines) _DraftLine.fromRead(read),
  ];

  bool _busy = false;

  DateTime get _today => widget.today ?? DateTime.now();

  /// السطور اللي هتتحفظ فعلاً — اللي اتشال مش فيها.
  List<_DraftLine> get _keep => [for (final l in _lines) if (!l.deleted) l];

  /// اللي بيقفل «تمام» فعلاً: اسم أو توقيت ناقص — من غيرهم مفيش حاجة تتجدول.
  bool get _hasBlocking => _keep.any((l) => l.blocks);

  /// جرعة مش معروفة بس — بتتحفظ «مش معروفة» ونسأل عنها بعدين.
  bool get _hasUnknownAmount => _keep.any((l) => l.amountUnknown);

  /// أول سطر «أعدّل» هيروح له: اللي بيقفل، وإلا اللي محتاج مراجعة، وإلا الأول.
  int? get _firstToEdit {
    for (final (i, l) in _lines.indexed) {
      if (!l.deleted && l.blocks) return i;
    }
    for (final (i, l) in _lines.indexed) {
      if (!l.deleted && l.needsReview) return i;
    }
    for (final (i, l) in _lines.indexed) {
      if (!l.deleted) return i;
    }
    return null;
  }

  /// «عدّل»: بيعدّل السطر **في الذاكرة** وبيرجع — ولا بايت بيتكتب.
  Future<void> _edit(int index) async {
    final line = _lines[index];
    // **كل** جرعات السطر — مش أولها. دوا مرتين في اليوم بيتعدّل مرتين.
    final draft = await Navigator.of(context).push<MedicationDraft>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(
          draft: true,
          routine: widget.routine,
          today: widget.today,
          initialName: line.name,
          initialAmount: line.amountLabel,
          initialTimings: line.timings,
          initialDurationDays: line.durationDays,
        ),
      ),
    );
    if (draft != null && mounted) setState(() => _lines[index].applyDraft(draft));
  }

  /// سطر ما اتقراش خالص — بيتكتب بإيد إنسان، وبيدخل المسوّدة زي أي سطر.
  Future<void> _addUnread() async {
    final draft = await Navigator.of(context).push<MedicationDraft>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(draft: true, routine: widget.routine, today: widget.today),
      ),
    );
    if (draft != null && mounted) setState(() => _lines.add(_DraftLine.fromDraft(draft)));
  }

  /// «شيله»: بيطلع من المسوّدة — والتراجع **مكانه في القايمة**، مش SnackBar.
  ///
  /// دوا الدكتور ما كتبهوش، أو تكرار الذكاء اخترعه، لازم ينشال من هنا — من
  /// غير ما حد يسيب الشاشة ولا يمسح دوا اتحفظ بالغلط بعدين.
  ///
  /// والتراجع بيفضل ظاهر لحد ما يخلّص: شريط بيختفي بعد ٦ ثواني بيطلب من راجل
  /// في السبعين إنه يسابق الوقت، وبيغطّي زرار «تمام» اللي تحته وهو ظاهر.
  void _delete(int index) => setState(() => _lines[index].deleted = true);

  void _undoDelete(int index) => setState(() => _lines[index].deleted = false);

  /// «تمام، ظبّطهم»: **الكتابة الوحيدة في الشاشة دي** — كل السطور الباقية
  /// في معاملة واحدة، وبعدها الجدولة. ولا حاجة بتوصل القاعدة قبل الدوسة دي.
  Future<void> _confirm() async {
    final keep = _keep;
    if (_busy || _hasBlocking || keep.isEmpty) return;
    setState(() => _busy = true);

    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    await services.medications.addMedicationsWithDoses(
      patientId: services.patientId,
      startDate: _today,
      medications: [
        for (final l in keep)
          (
            name: l.name!,
            timings: l.timings,
            // جرعة مش واضحة → null + «مش معروفة». مش بنخترع قيمة عشان نكمّل.
            amountLabel: l.amountUnknown ? null : l.amountLabel,
            amountUnknown: l.amountUnknown,
            durationDays: l.durationDays, // null = مفتوحة، زي ما الورقة سابتها
          ),
      ],
    );
    await services.scheduler.rescheduleAll();

    // الملف الصحي (D3.5): الروشتة اللي اتأكدت بتتسجّل — بالتاريخ والأدوية.
    // بعد الأدوية والجدولة (دول الوعد)؛ لو السطر ده فشل التأكيد ما بيتلغيش.
    // الدكتور بس لو القراءة واثقة منه — مفيش تخمين في ملف حد.
    final names = [for (final l in keep) l.name!];
    try {
      final doctor = widget.reading.doctor;
      await RecordsRepository(services.db).add(
        patientId: services.patientId,
        kind: RecordKind.prescription,
        title: prescriptionRecordTitle(names.length),
        happenedAt: DateTime(_today.year, _today.month, _today.day),
        doctor: doctor.needsReview ? null : doctor.value,
        notes: names.join(' — '),
      );
    } catch (error, stack) {
      debugPrint('الروشتة اتحفظت بس ما اتسجّلتش في الملف الصحي: $error\n$stack');
    }

    if (mounted) navigator.pop(ReviewResult.confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final reading = widget.reading;
    final engine = ScheduleEngine(widget.routine);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
                children: [
                  const Kicker('مراجعة وتأكيد'),
                  const SizedBox(height: F.s4),
                  Text(
                    'الذكاء يقترح، وأنت تؤكّد',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: F.s6),
                  Text(
                    'راجع كل دوا قبل ما يتحفظ. اللي عليه علامة ذهبية الذكاء مش متأكد منه.',
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                  ),
                  if (reading.doctor.value != null) ...[
                    const SizedBox(height: F.s4),
                    Text(
                      'د. ${reading.doctor.value}',
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                    ),
                  ],
                  if (kDebugMode && reading.modelWarning != null) ...[
                    const SizedBox(height: F.s8),
                    DebugPanel(reading.modelWarning!),
                  ],
                  const SizedBox(height: F.gap),
                  if (reading.isEmpty && _lines.isEmpty)
                    const _EmptyReading()
                  else
                    for (final (i, line) in _lines.indexed)
                      if (line.deleted) ...[
                        _RemovedRow(
                          name: line.name ?? 'السطر',
                          onUndo: _busy ? null : () => _undoDelete(i),
                        ),
                        const SizedBox(height: F.s12),
                      ] else ...[
                        _MedicineRow(
                          line: line,
                          timeFor: (t) => arabicTime(switch (t) {
                            AnchorTiming(:final anchor, :final offsetMinutes) =>
                              engine.resolveTime(anchor: anchor, offsetMinutes: offsetMinutes, onDay: _today),
                            FixedTiming(:final minuteOfDay) =>
                              engine.resolveFixed(minuteOfDay: minuteOfDay, onDay: _today),
                          }),
                          onEdit: _busy ? null : () => _edit(i),
                          onDelete: _busy ? null : () => _delete(i),
                        ),
                        const SizedBox(height: F.s12),
                      ],
                  if (_keep.isEmpty && _lines.isNotEmpty) ...[
                    Container(
                      key: const ValueKey('all-removed'),
                      padding: const EdgeInsets.all(F.s12),
                      decoration: BoxDecoration(
                        color: F.railGround,
                        borderRadius: BorderRadius.circular(F.radiusTile),
                      ),
                      child: Text(
                        'شيلت كل الأدوية — مفيش حاجة تتأكّد. رجّع واحد أو صوّر تاني.',
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: F.s12),
                  ],
                  _AddUnreadRow(onTap: _busy ? null : _addUnread),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_hasBlocking)
                    Padding(
                      padding: EdgeInsets.only(bottom: F.s8),
                      child: Text(
                        'في دوا اسمه أو توقيته مش واضح — دوس «أعدّل» وحدده الأول.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5),
                      ),
                    )
                  else if (_hasUnknownAmount)
                    Padding(
                      padding: EdgeInsets.only(bottom: F.s8),
                      child: Text(
                        'هتتحفظ من غير الجرعة — تقدر تضيفها بعدين',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                      ),
                    ),
                  // القراءة الوحشة علاجها صورة أحسن، مش تعديل خمس حقول بالإيد.
                  SizedBox(
                    height: F.minTapTarget,
                    child: TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(ReviewResult.retake),
                      child: Text(
                        'صوّر تاني',
                        style: TextStyle(
                          fontSize: F.minBodySize,
                          fontWeight: FontWeight.w600,
                          color: F.green,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: F.s4),
                  // الزرارين نفس الوزن بالظبط: مليانين، نفس المقاس والخط.
                  Row(
                    children: [
                      Expanded(
                        child: _EqualButton(
                          label: 'أعدّل',
                          fill: F.ink,
                          onPressed: _busy || _firstToEdit == null ? null : () => _edit(_firstToEdit!),
                        ),
                      ),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: _EqualButton(
                          key: const ValueKey('confirm-review'),
                          // العدد على الزرار: اللي بيتأكّد لازم يعرف هيحفظ كام
                          label: 'تمام — ${_countWord(_keep.length)}',
                          fill: F.green,
                          onPressed: _busy || _hasBlocking || _keep.isEmpty ? null : _confirm,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// زرار من الاتنين — كل الفرق بينهم لون التعبئة، والاتنين غامقين.
class _EqualButton extends StatelessWidget {
  const _EqualButton({required this.label, required this.fill, required this.onPressed, super.key});

  final String label;
  final Color fill;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.primaryButtonHeight,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: fill,
            foregroundColor: F.onDark,
            disabledBackgroundColor: F.railGround,
            disabledForegroundColor: F.mutedDark,
            textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
            padding: const EdgeInsets.symmetric(horizontal: F.s8),
          ),
          child: Text(label, maxLines: 1),
        ),
      );
}

/// صف دوا واحد.
class _MedicineRow extends StatelessWidget {
  const _MedicineRow({
    required this.line,
    required this.timeFor,
    required this.onEdit,
    required this.onDelete,
  });

  /// سطر المسوّدة — اللي هيتحفظ، مش اللي الورقة قالته بالظبط.
  final _DraftLine line;
  final String Function(DoseTiming) timeFor;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final read = line.read;
    final edited = line.edited;
    final timings = line.timings;
    final unsure = line.needsReview;
    final name = line.name;

    final unsureFields = [
      if (read != null && !edited) ...[
        if (read.name.needsReview) ('الاسم', read.name.note),
        if (read.timings.needsReview) ('التوقيت', read.timings.note),
        if (read.amount.needsReview) ('الجرعة', read.amount.note),
      ],
    ];

    final body = Padding(
      padding: const EdgeInsets.all(F.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        name ?? 'الاسم مش واضح',
                        textDirection: name == null ? null : nameDirection(name),
                        style: TextStyle(
                          fontSize: name == null ? F.minBodySize : F.medicationNameSize,
                          fontWeight: FontWeight.w700,
                          color: F.ink,
                          fontFamily: name == null ? null : F.monoFamily,
                          fontFamilyFallback: name == null ? null : F.monoFallback,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: F.s4),
                    Text(
                      [
                        line.amountUnknown
                            ? 'الجرعة مش معروفة'
                            : (line.amountLabel ?? 'الجرعة مش معروفة'),
                        switch (line.durationDays) {
                          null => 'مفتوحة — لحد ما توقفه',
                          final d => '${arabicNumber(d)} يوم',
                        },
                      ].join(' — '),
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: F.s8),
              if (edited)
                Padding(
                  padding: const EdgeInsets.only(top: F.s8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: F.greenOk, size: 24),
                      const SizedBox(width: F.s4),
                      Text(
                        'اتعدّل',
                        style: TextStyle(
                          fontSize: F.minTextSize,
                          fontWeight: FontWeight.w700,
                          color: F.greenOk,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: F.s10),
          // الوقت المحسوب + شريحة القاعدة — لكل توقيت. القاعدة هي اللي
          // بتتحفظ؛ الساعة للعرض بس.
          if (timings.isEmpty)
            Text(
              'التوقيت مش واضح',
              style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink),
            )
          else
            Wrap(
              spacing: F.s12,
              runSpacing: F.s8,
              children: [
                for (final t in timings)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeFor(t),
                        style: TextStyle(
                          fontSize: F.minBodySize,
                          fontWeight: FontWeight.w700,
                          color: F.ink,
                        ),
                      ),
                      const SizedBox(width: F.s6),
                      StatusChip(label: t.ruleLabel),
                    ],
                  ),
              ],
            ),
          if (!unsure && !edited && read != null) ...[
            const SizedBox(height: F.s8),
            Text(
              'ثقة ${arabicNumber((line.confidence * 100).round())}٪',
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
            ),
          ],
          const SizedBox(height: F.s12),
          // التعديل والشيل مع بعض في آخر الكارت: الاتنين بكلمة، والاتنين
          // على المسوّدة — ولا واحد فيهم بيكتب في القاعدة.
          Row(
            children: [
              Expanded(
                child: _RowButton(
                  icon: Icons.edit_outlined,
                  label: 'عدّل',
                  onPressed: onEdit,
                ),
              ),
              const SizedBox(width: F.s8),
              Expanded(
                child: _RowButton(
                  icon: Icons.delete_outline,
                  label: 'شيله',
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
          if (unsure) ...[
            const SizedBox(height: F.s12),
            // الشك مكتوب بهدوء: عنوان، وكل حقل مش متأكد منه بملاحظته.
            Container(
              padding: const EdgeInsets.all(F.s12),
              decoration: BoxDecoration(
                color: F.railGround,
                borderRadius: BorderRadius.circular(F.radiusTile),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'مش متأكد من دي — راجعها',
                    style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                  ),
                  for (final (label, note) in unsureFields) ...[
                    const SizedBox(height: F.s4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$label: ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: note ?? 'مش واضح في الصورة'),
                        ],
                      ),
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
          border: Border.all(color: unsure ? F.gold : F.line, width: unsure ? 1.5 : 1),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: body),
              // حافة ذهبية على جنب واحد — آخر ابن في RTL = الشمال، زي README
              if (unsure) Container(key: const ValueKey('unsure-edge'), width: 6, color: F.gold),
            ],
          ),
        ),
    );
  }
}

/// «أضف دوا ما اتعرفش عليه» — حد متقطع، زرار بكلمة وأيقونة.
class _AddUnreadRow extends StatelessWidget {
  const _AddUnreadRow({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedBorder(color: F.mutedLight, radius: F.radiusCard),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusCard),
            child: Container(
              constraints: const BoxConstraints(minHeight: F.minTapTarget + F.s8),
              padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s12),
              child: Row(
                children: [
                  Icon(Icons.add, color: F.green, size: 26),
                  SizedBox(width: F.s8),
                  Expanded(
                    child: Text(
                      'أضف دوا ما اتعرفش عليه',
                      style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.green),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
        Radius.circular(radius),
      ));
    const dash = 7.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

class _EmptyReading extends StatelessWidget {
  const _EmptyReading();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: F.s12),
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: F.railGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
        ),
        child: Text(
          'مقدرتش ألاقي أدوية في الصورة دي. صوّر تاني والنور يكون كويس.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
      );
}

/// «دوا واحد» / «دواءين» / «٣ أدوية» — للزرار.
String _countWord(int count) => switch (count) {
      0 => 'مفيش أدوية',
      1 => 'دوا واحد',
      2 => 'دواءين',
      _ => '${arabicNumber(count)} أدوية',
    };

/// سطر في المسوّدة: اللي الورقة قالته + اللي الإنسان غيّره، ولسه ما اتحفظش.
class _DraftLine {
  _DraftLine({
    required this.read,
    required this.name,
    required this.amountLabel,
    required this.amountUnknown,
    required this.timings,
    required this.durationDays,
    this.edited = false,
  });

  /// من قراية الذكاء — بثقتها وملاحظاتها زي ما هي.
  factory _DraftLine.fromRead(ReadLine read) => _DraftLine(
        read: read,
        name: read.name.value,
        amountLabel: read.amount.value,
        amountUnknown: read.amount.needsReview,
        timings: read.timings.value ?? const [],
        durationDays: read.duration.value,
      );

  /// «أضف دوا ما اتعرفش عليه» — إنسان كتبه، فمفيش شك فيه.
  factory _DraftLine.fromDraft(MedicationDraft d) => _DraftLine(
        read: null,
        name: d.name,
        amountLabel: d.amountLabel,
        amountUnknown: d.amountUnknown,
        timings: d.timings,
        durationDays: d.durationDays,
        edited: true,
      );

  /// null = السطر اتكتب بالإيد، مش من الورقة.
  final ReadLine? read;

  String? name;
  String? amountLabel;
  bool amountUnknown;
  List<DoseTiming> timings;
  int? durationDays;

  /// إنسان عدّاها بإيده — فالشك بتاع الذكاء خلص.
  bool edited;

  /// اتشال من المسوّدة (وممكن يرجع من «رجّعه»).
  bool deleted = false;

  void applyDraft(MedicationDraft d) {
    name = d.name;
    amountLabel = d.amountLabel;
    amountUnknown = d.amountUnknown;
    timings = d.timings;
    durationDays = d.durationDays;
    edited = true;
  }

  /// من غير اسم أو من غير جرعة مفيش حاجة تتجدول — ده اللي بيقفل «تمام».
  bool get blocks => (name ?? '').trim().isEmpty || timings.isEmpty;

  /// الذكاء مش متأكد، والإنسان لسه ما راجعهاش.
  bool get needsReview => !edited && (read?.needsReview ?? false);

  /// أقل ثقة في الحقول اللي بتتحفظ.
  double get confidence => read == null
      ? 1
      : [read!.name.confidence, read!.amount.confidence, read!.timings.confidence]
          .reduce((a, b) => a < b ? a : b);
}

/// سطر اتشال — مكانه في القايمة، والتراجع جنبه ومستني.
class _RemovedRow extends StatelessWidget {
  const _RemovedRow({required this.name, required this.onUndo});

  final String name;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('removed-row'),
        padding: const EdgeInsets.fromLTRB(F.s14, F.s8, F.s14, F.s8),
        decoration: BoxDecoration(
          color: F.railGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
          border: Border.all(color: F.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'اتشال $name',
                style: TextStyle(
                  fontSize: F.minBodySize,
                  color: F.mutedDark,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
            const SizedBox(width: F.s8),
            _RowButton(icon: Icons.undo, label: 'رجّعه', onPressed: onUndo),
          ],
        ),
      );
}

/// زرار صغير على كارت السطر — بأيقونة **وكلمة**.
class _RowButton extends StatelessWidget {
  const _RowButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: F.ink,
            minimumSize: const Size(0, F.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.s12),
            side: BorderSide(color: F.line, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusTile)),
          ),
          icon: Icon(icon, size: 22),
          label: Text(label, style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700)),
        ),
      );
}

/// «روشتة — دوا واحد» / «روشتة — دواءين» / «روشتة — ٣ أدوية».
String prescriptionRecordTitle(int count) => switch (count) {
      1 => 'روشتة — دوا واحد',
      2 => 'روشتة — دواءين',
      _ => 'روشتة — ${arabicNumber(count)} أدوية',
    };
