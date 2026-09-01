import 'package:flutter/material.dart';

import '../../ai/prescription_reading.dart';
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../medication/add_medication_screen.dart';

enum ReviewResult { confirmed, retake }

/// «فهمت الروشتة كده» — الذكاء يقترح، وإنت تؤكّد.
///
/// ولا سطر بيتحفظ قبل دوسة. اللي ثقته قليلة بيتعلّم بالذهبي «محتاج تحديد»
/// و«تمام» بتفضل مقفولة لحد ما يتحدد من «أعدّل». و«أعدّل» بنفس حجم «تمام»
/// عن قصد — محدش بيتدفع يأكّد جدول دوا ما قراهوش.
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
  bool _busy = false;

  List<int> get _remaining => [
        for (var i = 0; i < widget.reading.lines.length; i++)
          if (!_saved.contains(i)) i,
      ];

  bool get _hasUnresolved =>
      _remaining.any((i) => widget.reading.lines[i].needsReview);

  int? get _firstToEdit {
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

  /// «تمام»: بيحفظ السطور الواضحة المتبقية — وبس. الدوسة دي هي التأكيد.
  Future<void> _confirm() async {
    if (_busy || _hasUnresolved) return;
    setState(() => _busy = true);

    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final today = widget.today ?? DateTime.now();

    for (final i in _remaining) {
      final line = widget.reading.lines[i];
      final timings = line.timings.value!;
      final id = await services.medications.addMedication(
        patientId: services.patientId,
        name: line.name.value!,
        amountLabel: line.amount.value,
        timing: timings.first,
        startDate: today,
        durationDays: line.duration.value, // null = مفتوحة، زي ما الورقة سابتها
      );
      for (final timing in timings.skip(1)) {
        await services.medications.addDoseSchedule(
          id,
          timing: timing,
          startDate: today,
          durationDays: line.duration.value,
        );
      }
    }
    await services.scheduler.rescheduleAll();

    if (mounted) navigator.pop(ReviewResult.confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final reading = widget.reading;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'فهمت الروشتة كده',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(F.gap),
                children: [
                  const Text(
                    'راجع كل سطر — اللي بالذهبي محتاج تحديد منك.',
                    style: TextStyle(fontSize: F.minBodySize, color: F.muted, height: 1.6),
                  ),
                  if (reading.doctor.value != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'د. ${reading.doctor.value}',
                      style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                    ),
                  ],
                  const SizedBox(height: F.gap),
                  if (reading.isEmpty)
                    const _EmptyReading()
                  else
                    for (final (i, line) in reading.lines.indexed) ...[
                      _LineCard(
                        line: line,
                        saved: _saved.contains(i),
                        onEdit: () => _edit(i),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_hasUnresolved)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'في سطر محتاج تحديد — دوس «أعدّل» وحدده الأول.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: F.primaryButtonHeight,
                          child: FilledButton(
                            onPressed: _busy || _firstToEdit == null
                                ? null
                                : () => _edit(_firstToEdit!),
                            style: FilledButton.styleFrom(
                              backgroundColor: F.ivory,
                              foregroundColor: F.ink,
                            ),
                            child: const Text('أعدّل'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: F.primaryButtonHeight,
                          child: FilledButton(
                            onPressed: _busy || _hasUnresolved ? null : _confirm,
                            child: const Text('تمام'),
                          ),
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

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.saved, required this.onEdit});

  final ReadLine line;
  final bool saved;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final durationText = switch (line.duration.value) {
      null => 'مفتوحة — لحد ما توقفه',
      final d => '${arabicNumber(d)} يوم',
    };

    return Opacity(
      opacity: saved ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(
            color: line.needsReview && !saved ? F.gold : F.line,
            width: line.needsReview && !saved ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FieldRow(label: 'الدوا', field: line.name, text: line.name.value, mono: true),
            _FieldRow(label: 'الجرعة', field: line.amount, text: line.amount.value),
            _FieldRow(
              label: 'التوقيت',
              field: line.timings,
              text: line.timings.value == null ? null : line.timingLabel,
            ),
            _FieldRow(label: 'المدة', field: line.duration, text: durationText, last: true),
            const SizedBox(height: 12),
            if (saved)
              const Row(
                children: [
                  Icon(Icons.check, color: F.green, size: 26),
                  SizedBox(width: 6),
                  Text(
                    'اتضاف',
                    style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.greenDeep),
                  ),
                ],
              )
            else
              SizedBox(
                height: F.minTapTarget,
                child: OutlinedButton(
                  onPressed: onEdit,
                  child: const Text(
                    'أعدّل السطر ده',
                    style: TextStyle(fontSize: F.minTextSize + 1, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// حقل واحد: القيمة، ونسبة الثقة — أو «محتاج تحديد» بالذهبي.
///
/// الذهبي هنا بنفس معناه في التطبيق كله: «ده محتاج انتباهك».
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.field,
    required this.text,
    this.mono = false,
    this.last = false,
  });

  final String label;
  final ReadField<Object?> field;
  final String? text;
  final bool mono;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final review = field.needsReview;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                ),
              ),
              if (review)
                const Text(
                  'محتاج تحديد',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.gold),
                )
              else
                Text(
                  'ثقة ${arabicNumber((field.confidence * 100).round())}٪',
                  style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            text ?? 'غير واضح',
            style: TextStyle(
              fontSize: mono ? F.screenTitleSize : F.minBodySize + 2,
              fontWeight: FontWeight.w700,
              color: review ? F.gold : F.ink,
              fontFamily: mono ? F.monoFamily : null,
              fontFamilyFallback: mono ? F.monoFallback : null,
              height: 1.4,
            ),
          ),
          if (review && field.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                field.note!,
                style: const TextStyle(fontSize: F.minTextSize, color: F.gold, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyReading extends StatelessWidget {
  const _EmptyReading();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: const Text(
          'مقدرتش ألاقي أدوية في الصورة دي. صوّر تاني والنور يكون كويس.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
      );
}
