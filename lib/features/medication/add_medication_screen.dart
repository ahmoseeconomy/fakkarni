import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../onboarding/time_wheel.dart';

/// اختيار جاهز: مرساة + اتجاه.
///
/// الروشتة بتقول «قبل الفطار»، مش «الساعة ٧». عشان كده الشيبات دي هي
/// المدخل الأساسي. الساعة الثابتة موجودة، بس ورا لينك صغير **تحت زرار
/// الحفظ** — الساعة حاجة الناس متعوّدة عليها والمراسي جديدة، فلينك جنب
/// الشيبات كان هيتداس بالعادة مش بالاختيار.
class _AnchorChoice {
  const _AnchorChoice(this.label, this.anchor, this.before);
  final String label;
  final DayAnchor anchor;
  final bool before;
}

const _choices = [
  _AnchorChoice('أول ما أصحى', DayAnchor.wake, false),
  _AnchorChoice('قبل الفطار', DayAnchor.breakfast, true),
  _AnchorChoice('بعد الفطار', DayAnchor.breakfast, false),
  _AnchorChoice('قبل الغدا', DayAnchor.lunch, true),
  _AnchorChoice('بعد الغدا', DayAnchor.lunch, false),
  _AnchorChoice('قبل العشا', DayAnchor.dinner, true),
  _AnchorChoice('بعد العشا', DayAnchor.dinner, false),
  _AnchorChoice('قبل النوم', DayAnchor.sleep, true),
];

class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({
    required this.routine,
    this.today,
    this.initialName,
    this.initialAmount,
    this.initialTiming,
    this.initialDurationDays,
    super.key,
  });

  final DayRoutine routine;
  final DateTime? today;

  /// قيم مبدئية — من قراءة الروشتة. بتتعرض للتعديل، ما بتتحفظش لوحدها.
  final String? initialName;
  final String? initialAmount;
  final DoseTiming? initialTiming;
  final int? initialDurationDays;

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _amount = TextEditingController(text: widget.initialAmount ?? '');
  _AnchorChoice _choice = _choices[1];
  int _gap = 30;

  /// المخرج الثانوي: ساعة ثابتة بدل المرساة. الافتراضي دايماً مرساة.
  bool _fixed = false;
  MinuteOfDay _fixedTime = MinuteOfDay.hm(8);
  bool _openEnded = true;
  int _days = 7;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _applyInitial();
  }

  /// بيحوّل التوقيت المبدئي لحالة الشاشة — أقرب شيب + إزاحة، أو ساعة ثابتة.
  void _applyInitial() {
    final days = widget.initialDurationDays;
    if (days != null) {
      _openEnded = false;
      _days = days.clamp(1, 90);
    }
    switch (widget.initialTiming) {
      case AnchorTiming(:final anchor, :final offsetMinutes):
        final before = offsetMinutes < 0;
        _choice = _choices.firstWhere(
          (c) => c.anchor == anchor && (anchor == DayAnchor.wake || c.before == before),
          orElse: () => _choices[1],
        );
        _gap = offsetMinutes.abs();
      case FixedTiming(:final minuteOfDay):
        _fixed = true;
        _fixedTime = minuteOfDay;
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  int get _offsetMinutes => _choice.before ? -_gap : _gap;

  DoseTiming get _timing => _fixed
      ? FixedTiming(_fixedTime)
      : AnchorTiming(_choice.anchor, _offsetMinutes);

  DateTime get _preview {
    final engine = ScheduleEngine(widget.routine);
    final day = widget.today ?? DateTime.now();
    return switch (_timing) {
      AnchorTiming(:final anchor, :final offsetMinutes) => engine.resolveTime(
          anchor: anchor,
          offsetMinutes: offsetMinutes,
          onDay: day,
        ),
      FixedTiming(:final minuteOfDay) =>
        engine.resolveFixed(minuteOfDay: minuteOfDay, onDay: day),
    };
  }

  Future<void> _save() async {
    if (_saving || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    await services.medications.addMedication(
      patientId: services.patientId,
      name: _name.text.trim(),
      amountLabel: _amount.text.trim().isEmpty ? null : _amount.text.trim(),
      timing: _timing,
      startDate: widget.today ?? DateTime.now(),
      // المدة المفتوحة هي الافتراضي — وما بنخمّنش مدة أبداً.
      durationDays: _openEnded ? null : _days,
    );
    await services.scheduler.rescheduleAll();

    // true = اتحفظ — شاشة مراجعة الروشتة بتفرّق بين الحفظ والرجوع.
    if (mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ضيف دوا',
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
                  const _FieldLabel('اسم الدوا'),
                  TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: F.minBodySize,
                      fontFamily: F.monoFamily,
                      fontFamilyFallback: F.monoFallback,
                    ),
                    decoration: InputDecoration(
                      hintText: 'زي Concor 5mg',
                      hintStyle: const TextStyle(
                        fontSize: F.minTextSize,
                        color: F.muted,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(F.radius),
                        borderSide: const BorderSide(color: F.line),
                      ),
                    ),
                  ),
                  const SizedBox(height: F.gap),
                  const _FieldLabel('الجرعة (اختياري)'),
                  TextField(
                    controller: _amount,
                    style: const TextStyle(fontSize: F.minBodySize),
                    decoration: InputDecoration(
                      hintText: 'زي: قرص واحد',
                      hintStyle: const TextStyle(
                        fontSize: F.minTextSize,
                        color: F.muted,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(F.radius),
                        borderSide: const BorderSide(color: F.line),
                      ),
                    ),
                  ),
                  const SizedBox(height: F.gap + 6),
                  const Text(
                    'إمتى؟',
                    style: TextStyle(
                      fontSize: F.questionSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_fixed) ...[
                    // بنقولها صراحة: الجرعة دي مش هتتحرك مع الروتين.
                    const _FixedNotice(),
                    const SizedBox(height: 12),
                    _FixedTimePicker(
                      value: _fixedTime,
                      onChanged: (value) => setState(() => _fixedTime = value),
                    ),
                    SizedBox(
                      height: F.minTapTarget,
                      child: TextButton(
                        onPressed: () => setState(() => _fixed = false),
                        child: const Text(
                          'ارجع للمراسي',
                          style: TextStyle(
                            fontSize: F.minTextSize,
                            fontWeight: FontWeight.w600,
                            color: F.green,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'اختار المرساة الأول — الساعة بتتحسب لوحدها.',
                      style: TextStyle(fontSize: F.minTextSize, color: F.muted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final choice in _choices)
                          _ChoiceChip(
                            label: choice.label,
                            selected: choice == _choice,
                            onTap: () => setState(() {
                            _choice = choice;
                            // الافتراضي بيتبع المرساة: ٣٠ قبل الأكل، ١٥ قبل النوم
                            _gap = choice.before
                                ? defaultOffsetBefore(choice.anchor)
                                : 30;
                          }),
                          ),
                      ],
                    ),
                    const SizedBox(height: F.gap + 6),
                    const _FieldLabel('بكام؟'),
                    _Stepper(
                      value: _gap,
                      onChanged: (value) => setState(() => _gap = value),
                    ),
                  ],
                  const SizedBox(height: F.gap),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(F.radius),
                      border: Border.all(color: F.gold, width: 1.5),
                    ),
                    child: Text(
                      'يبقى حوالي ${arabicTime(_preview)}',
                      style: const TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w600,
                        color: F.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: F.gap + 6),
                  const _FieldLabel('المدة'),
                  Row(
                    children: [
                      Expanded(
                        child: _ChoiceChip(
                          label: 'مفتوحة',
                          selected: _openEnded,
                          onTap: () => setState(() => _openEnded = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ChoiceChip(
                          label: 'أيام محددة',
                          selected: !_openEnded,
                          onTap: () => setState(() => _openEnded = false),
                        ),
                      ),
                    ],
                  ),
                  if (!_openEnded) ...[
                    const SizedBox(height: 12),
                    _Stepper(
                      value: _days,
                      step: 1,
                      min: 1,
                      max: 90,
                      unit: 'يوم',
                      onChanged: (value) => setState(() => _days = value),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    const Text(
                      'التذكير هيفضل شغال لحد ما توقفه بنفسك.',
                      style: TextStyle(
                        fontSize: F.minTextSize,
                        color: F.muted,
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: F.primaryButtonHeight,
                    child: FilledButton(
                      onPressed: _name.text.trim().isEmpty ? null : _save,
                      child: const Text('احفظ الجرعة'),
                    ),
                  ),
                  // اللينك آخر حاجة في الشاشة عن قصد — بعد ما المسار الأساسي
                  // اتشاف كله. مش بيظهر وإحنا في وضع الساعة الثابتة أصلاً.
                  if (!_fixed)
                    SizedBox(
                      height: F.minTapTarget,
                      child: TextButton(
                        onPressed: () => setState(() => _fixed = true),
                        child: const Text(
                          'أحدد ساعة ثابتة بدل كده',
                          style: TextStyle(
                            fontSize: F.minTextSize,
                            color: F.muted,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: F.minTapTarget),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// التنبيه اللي لازم يتقال لما الجرعة على ساعة ثابتة.
///
/// عاجي مش ذهبي: ده تنبيه معلوماتي مش تذكير ولا حالة نشطة.
class _FixedNotice extends StatelessWidget {
  const _FixedNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: const Text(
          'ساعة ثابتة — مش هتتحرك مع روتين يومك',
          style: TextStyle(
            fontSize: F.minBodySize,
            fontWeight: FontWeight.w600,
            color: F.ink,
            height: 1.5,
          ),
        ),
      );
}

/// الساعة الكبيرة والعجلة — نفس شكل سؤال الروتين.
class _FixedTimePicker extends StatelessWidget {
  const _FixedTimePicker({required this.value, required this.onChanged});

  final MinuteOfDay value;
  final ValueChanged<MinuteOfDay> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: F.gap),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: Column(
          children: [
            Text(
              arabicTime(DateTime(2026, 1, 1, value.hour, value.minute)),
              style: const TextStyle(
                fontSize: F.bigTimeSize,
                fontWeight: FontWeight.w700,
                color: F.greenDeep,
              ),
            ),
            const SizedBox(height: 8),
            TimeWheel(value: value, onChanged: onChanged),
          ],
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: F.minTextSize,
            fontWeight: FontWeight.w600,
            color: F.muted,
          ),
        ),
      );
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: F.minTapTarget),
        child: Material(
          color: selected ? F.green : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radius),
            side: BorderSide(color: selected ? F.green : F.line, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: F.minTextSize + 1,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : F.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// خطوة بكلمة، مش بأيقونة لوحدها.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.onChanged,
    this.step = 5,
    this.min = 0,
    this.max = 180,
    this.unit = 'دقيقة',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int step;
  final int min;
  final int max;
  final String unit;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _button(
              label: 'أقل',
              enabled: value > min,
              onTap: () => onChanged((value - step).clamp(min, max)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: F.minTapTarget,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: F.ivory,
                borderRadius: BorderRadius.circular(F.radius),
              ),
              child: Text(
                '${arabicNumber(value)} $unit',
                style: const TextStyle(
                  fontSize: F.minBodySize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
            ),
          ),
          Expanded(
            child: _button(
              label: 'أكتر',
              enabled: value < max,
              onTap: () => onChanged((value + step).clamp(min, max)),
            ),
          ),
        ],
      );

  Widget _button({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      SizedBox(
        height: F.minTapTarget,
        child: OutlinedButton(
          onPressed: enabled ? onTap : null,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: F.minTextSize + 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
