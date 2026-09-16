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
  /// السطور اللي اتحفظت من شاشة التعديل — بتفضل معروضة بس هادية.
  final Set<int> _saved = {};

  /// أدوية ضافها بإيده من «أضف دوا ما اتعرفش عليه».
  int _addedByHand = 0;
  bool _busy = false;

  DateTime get _today => widget.today ?? DateTime.now();

  List<int> get _remaining => [
        for (var i = 0; i < widget.reading.lines.length; i++)
          if (!_saved.contains(i)) i,
      ];

  /// اللي بيقفل «تمام» فعلاً: اسم أو توقيت مش واضح.
  bool get _hasBlocking =>
      _remaining.any((i) => widget.reading.lines[i].blocksConfirm);

  /// جرعة مش معروفة بس — بتتحفظ «مش معروفة» ونسأل عنها بعدين.
  bool get _hasUnknownAmount =>
      _remaining.any((i) => widget.reading.lines[i].amount.needsReview);

  int? get _firstToEdit {
    for (final i in _remaining) {
      if (widget.reading.lines[i].blocksConfirm) return i;
    }
    for (final i in _remaining) {
      if (widget.reading.lines[i].needsReview) return i;
    }
    return _remaining.isEmpty ? null : _remaining.first;
  }

  Future<void> _edit(int index) async {
    final line = widget.reading.lines[index];
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(
          routine: widget.routine,
          today: widget.today,
          initialName: line.name.value,
          initialAmount: line.amount.value,
          initialTiming: line.timings.value?.firstOrNull,
          initialDurationDays: line.duration.value,
        ),
      ),
    );
    if (saved == true && mounted) setState(() => _saved.add(index));
  }

  /// سطر ما اتقراش خالص — بيتكتب بإيد إنسان، فمفيش حاجة للتأكيد بعدها.
  Future<void> _addUnread() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(routine: widget.routine, today: widget.today),
      ),
    );
    if (saved == true && mounted) setState(() => _addedByHand++);
  }

  /// «تمام، ظبّطهم»: بيحفظ السطور الواضحة المتبقية — وبس. الدوسة دي هي التأكيد.
  Future<void> _confirm() async {
    if (_busy || _hasBlocking) return;
    setState(() => _busy = true);

    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    for (final i in _remaining) {
      final line = widget.reading.lines[i];
      final timings = line.timings.value!;
      // جرعة مش واضحة → null + «مش معروفة». مش بنخترع قيمة عشان نكمّل.
      final amountUnknown = line.amount.needsReview;
      final id = await services.medications.addMedication(
        patientId: services.patientId,
        name: line.name.value!,
        amountLabel: amountUnknown ? null : line.amount.value,
        amountUnknown: amountUnknown,
        timing: timings.first,
        startDate: _today,
        durationDays: line.duration.value, // null = مفتوحة، زي ما الورقة سابتها
      );
      for (final timing in timings.skip(1)) {
        await services.medications.addDoseSchedule(
          id,
          timing: timing,
          startDate: _today,
          durationDays: line.duration.value,
        );
      }
    }
    await services.scheduler.rescheduleAll();

    // الملف الصحي (D3.5): الروشتة اللي اتأكدت بتتسجّل — بالتاريخ والأدوية.
    // بعد الأدوية والجدولة (دول الوعد)؛ لو السطر ده فشل التأكيد ما بيتلغيش.
    // الدكتور بس لو القراءة واثقة منه — مفيش تخمين في ملف حد.
    final names = [for (final i in _remaining) widget.reading.lines[i].name.value!];
    if (names.isNotEmpty) {
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
                  const Text(
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
                  const Text(
                    'راجع كل دوا قبل ما يتحفظ. اللي عليه علامة ذهبية الذكاء مش متأكد منه.',
                    style: TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.6),
                  ),
                  if (reading.doctor.value != null) ...[
                    const SizedBox(height: F.s4),
                    Text(
                      'د. ${reading.doctor.value}',
                      style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                    ),
                  ],
                  if (kDebugMode && reading.modelWarning != null) ...[
                    const SizedBox(height: F.s8),
                    DebugPanel(reading.modelWarning!),
                  ],
                  const SizedBox(height: F.gap),
                  if (reading.isEmpty)
                    const _EmptyReading()
                  else
                    for (final (i, line) in reading.lines.indexed) ...[
                      _MedicineRow(
                        line: line,
                        saved: _saved.contains(i),
                        timeFor: (t) => arabicTime(switch (t) {
                          AnchorTiming(:final anchor, :final offsetMinutes) =>
                            engine.resolveTime(anchor: anchor, offsetMinutes: offsetMinutes, onDay: _today),
                          FixedTiming(:final minuteOfDay) =>
                            engine.resolveFixed(minuteOfDay: minuteOfDay, onDay: _today),
                        }),
                        onEdit: () => _edit(i),
                      ),
                      const SizedBox(height: F.s12),
                    ],
                  _AddUnreadRow(onTap: _busy ? null : _addUnread),
                  if (_addedByHand > 0) ...[
                    const SizedBox(height: F.s8),
                    Row(
                      children: [
                        const Icon(Icons.check, color: F.greenOk, size: 24),
                        const SizedBox(width: F.s6),
                        Text(
                          _addedByHand == 1
                              ? 'اتضاف دوا بإيدك'
                              : 'اتضاف ${arabicNumber(_addedByHand)} أدوية بإيدك',
                          style: const TextStyle(
                            fontSize: F.minTextSize,
                            fontWeight: FontWeight.w600,
                            color: F.greenOk,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_hasBlocking)
                    const Padding(
                      padding: EdgeInsets.only(bottom: F.s8),
                      child: Text(
                        'في دوا اسمه أو توقيته مش واضح — دوس «أعدّل» وحدده الأول.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5),
                      ),
                    )
                  else if (_hasUnknownAmount)
                    const Padding(
                      padding: EdgeInsets.only(bottom: F.s8),
                      child: Text(
                        'هتتحفظ من غير الجرعة — تقدر تضيفها بعدين',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.5),
                      ),
                    ),
                  // القراءة الوحشة علاجها صورة أحسن، مش تعديل خمس حقول بالإيد.
                  SizedBox(
                    height: F.minTapTarget,
                    child: TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(ReviewResult.retake),
                      child: const Text(
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
                          label: 'تمام، ظبّطهم',
                          fill: F.green,
                          onPressed: _busy || _hasBlocking ? null : _confirm,
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
  const _EqualButton({required this.label, required this.fill, required this.onPressed});

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
            foregroundColor: Colors.white,
            disabledBackgroundColor: F.ivoryWarm,
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
    required this.saved,
    required this.timeFor,
    required this.onEdit,
  });

  final ReadLine line;
  final bool saved;
  final String Function(DoseTiming) timeFor;
  final VoidCallback onEdit;

  /// أقل ثقة في الحقول اللي بتتحفظ — الرقم اللي بيتعرض على الصف الواضح.
  double get _confidence => [
        line.name.confidence,
        line.amount.confidence,
        line.timings.confidence,
      ].reduce((a, b) => a < b ? a : b);

  @override
  Widget build(BuildContext context) {
    final unsure = line.needsReview && !saved;
    final name = line.name.value;
    final timings = line.timings.value;

    final unsureFields = [
      if (line.name.needsReview) ('الاسم', line.name.note),
      if (line.timings.needsReview) ('التوقيت', line.timings.note),
      if (line.amount.needsReview) ('الجرعة', line.amount.note),
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
                        line.amount.needsReview
                            ? 'الجرعة مش معروفة'
                            : (line.amount.value ?? 'الجرعة مش معروفة'),
                        switch (line.duration.value) {
                          null => 'مفتوحة — لحد ما توقفه',
                          final d => '${arabicNumber(d)} يوم',
                        },
                      ].join(' — '),
                      style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: F.s8),
              if (saved)
                const Padding(
                  padding: EdgeInsets.only(top: F.s8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: F.greenOk, size: 24),
                      SizedBox(width: F.s4),
                      Text(
                        'اتضاف',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenOk),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: F.minTapTarget,
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: F.ink,
                      minimumSize: const Size(0, F.minTapTarget),
                      padding: const EdgeInsets.symmetric(horizontal: F.s12),
                      side: const BorderSide(color: F.line, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusTile)),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 22),
                    label: const Text(
                      'عدّل',
                      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: F.s10),
          // الوقت المحسوب + شريحة القاعدة — لكل توقيت. القاعدة هي اللي
          // بتتحفظ؛ الساعة للعرض بس.
          if (timings == null || timings.isEmpty)
            const Text(
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
                        style: const TextStyle(
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
          if (!unsure && !saved) ...[
            const SizedBox(height: F.s8),
            Text(
              'ثقة ${arabicNumber((_confidence * 100).round())}٪',
              style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
            ),
          ],
          if (unsure) ...[
            const SizedBox(height: F.s12),
            // الشك مكتوب بهدوء: عنوان، وكل حقل مش متأكد منه بملاحظته.
            Container(
              padding: const EdgeInsets.all(F.s12),
              decoration: BoxDecoration(
                color: F.ivoryPale,
                borderRadius: BorderRadius.circular(F.radiusTile),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
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
                      style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return Opacity(
      opacity: saved ? 0.6 : 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
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
        painter: const _DashedBorder(color: F.mutedLight, radius: F.radiusCard),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusCard),
            child: Container(
              constraints: const BoxConstraints(minHeight: F.minTapTarget + F.s8),
              padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s12),
              child: const Row(
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
          color: F.ivoryWarm,
          borderRadius: BorderRadius.circular(F.radiusCard),
        ),
        child: const Text(
          'مقدرتش ألاقي أدوية في الصورة دي. صوّر تاني والنور يكون كويس.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
      );
}

/// «روشتة — دوا واحد» / «روشتة — دواءين» / «روشتة — ٣ أدوية».
String prescriptionRecordTitle(int count) => switch (count) {
      1 => 'روشتة — دوا واحد',
      2 => 'روشتة — دواءين',
      _ => 'روشتة — ${arabicNumber(count)} أدوية',
    };
