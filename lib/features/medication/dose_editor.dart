import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/patient_voice.dart';
import '../routine/ask_anchor_time.dart';

/// اختيار جاهز: مرساة + اتجاه — بالترتيب بتاع التصميم.
///
/// الروشتة بتقول «قبل الفطار»، مش «الساعة ٧». عشان كده الشرائح دي هي
/// التحكم الأساسي. الساعة الثابتة موجودة، بس ورا لينك صغير **تحت زرار
/// الحفظ** — الساعة حاجة الناس متعوّدة عليها والمراسي جديدة، فلينك جنب
/// الشرائح كان هيتداس بالعادة مش بالاختيار.
class AnchorChoice {
  const AnchorChoice(this.label, this.anchor, this.before);
  final String label;
  final DayAnchor anchor;
  final bool before;

  /// الإزاحة الافتراضية للاختيار ده: ٣٠ قبل الأكل، ١٥ قبل النوم، ٣٠ بعد.
  int get defaultGap => before ? defaultOffsetBefore(anchor) : 30;
}

const List<AnchorChoice> anchorChoices = [
  AnchorChoice('قبل الفطار', DayAnchor.breakfast, true),
  AnchorChoice('بعد الفطار', DayAnchor.breakfast, false),
  AnchorChoice('قبل الغدا', DayAnchor.lunch, true),
  AnchorChoice('بعد الغدا', DayAnchor.lunch, false),
  AnchorChoice('قبل العشا', DayAnchor.dinner, true),
  AnchorChoice('بعد العشا', DayAnchor.dinner, false),
  AnchorChoice('قبل النوم', DayAnchor.sleep, true),
  AnchorChoice('أول ما أصحى', DayAnchor.wake, false),
];

/// «محرّر الجرعة» (المخطط 23) — شاشة واحدة بتتعاد في كل مكان بيتحدد فيه
/// توقيت: إضافة دوا، تعديل دوا، ومراجعة الروشتة.
///
/// الشرائح هي التحكم الأساسي، المعاينة ذهبية وبتتحدّث مع كل ضغطة، والساعة
/// المحددة اختيار جنب المرساة فوق (كانت لينك تحت الزرار — قرار المالك).
/// **المرساة لسه الافتراضي.**
class DoseEditor extends StatefulWidget {
  const DoseEditor({
    required this.name,
    required this.routine,
    required this.onSave,
    this.initialTiming,
    this.today,
    this.kicker,
    this.saveLabel = 'احفظ الجرعة',
    this.onSetAnchor,
    this.startFixed = false,
    super.key,
  });

  /// افتح على «ساعة محددة» من الأول — صف في الفورم اختار الساعة المحددة
  /// ولسه ما حددش وقته. بس لما [initialTiming] null.
  final bool startFixed;

  /// المستخدم حدّد ميعاد وجبة من هنا («بتفطر الساعة كام؟» مرة واحدة) —
  /// اللي نادانا هو اللي بيكتبه في الروتين. null = المحرّر بيحدّثه في
  /// الذاكرة بس (الاختبارات).
  final Future<void> Function(DayAnchor anchor, MinuteOfDay time)? onSetAnchor;

  /// اسم الدوا — بيتعرض فوق «إمتى؟» بالـmono.
  final String name;
  final DayRoutine routine;
  final DoseTiming? initialTiming;
  final DateTime? today;

  /// سطر صغير فوق الاسم — «الجرعة ١ من ٣».
  final String? kicker;
  final String saveLabel;

  /// بيتنده بالتوقيت المختار؛ اللي بيفتح الشاشة هو اللي بيحفظ وبيقفلها.
  final Future<void> Function(DoseTiming timing) onSave;

  @override
  State<DoseEditor> createState() => _DoseEditorState();
}

class _DoseEditorState extends State<DoseEditor> {
  AnchorChoice _choice = anchorChoices.first;
  int _gap = anchorChoices.first.defaultGap;

  /// الروتين الحي — بيتحدّث لما وجبة تتحدد من هنا.
  late DayRoutine _routine = widget.routine;

  /// المخرج الثانوي: ساعة ثابتة بدل المرساة. الافتراضي دايماً مرساة.
  bool _fixed = false;
  MinuteOfDay _fixedTime = MinuteOfDay.hm(8);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    switch (widget.initialTiming) {
      case AnchorTiming(:final anchor, :final offsetMinutes):
        final before = offsetMinutes < 0;
        _choice = anchorChoices.firstWhere(
          (c) => c.anchor == anchor && (anchor == DayAnchor.wake || c.before == before),
          orElse: () => anchorChoices.first,
        );
        _gap = offsetMinutes.abs();
      case FixedTiming(:final minuteOfDay):
        _fixed = true;
        _fixedTime = minuteOfDay;
      case null:
        if (widget.startFixed) _fixed = true;
    }
    // **مرساة ما اتحددتش = مفيش ساعة تتعرض منها.** الجرعة بتبدأ على ساعة
    // ثابتة المستخدم هو اللي بيختارها — ولا رقم بيتعبّى من روتين افتراضي.
    // لو رجع للمراسي واختار «قبل الفطار»، هيتسأل عن الفطار الأول.
    if (!_fixed && !_routine.isSet(_choice.anchor)) _fixed = true;
  }

  DateTime get _day => widget.today ?? DateTime.now();

  /// شريحة على مرساة مش متحددة: نسأل عن ميعادها **مرة واحدة**، نحفظه
  /// متحدد، وبعدين المرساة بتتاخد عادي. قفل الشيت من غير إجابة = الشريحة
  /// ما اتختارتش، ولا حاجة اتكتبت.
  Future<void> _pick(AnchorChoice choice) async {
    if (!_routine.isSet(choice.anchor)) {
      final time = await askAnchorTime(context, anchor: choice.anchor, say: PatientVoice.of(context));
      if (time == null || !mounted) return;
      await widget.onSetAnchor?.call(choice.anchor, time);
      if (!mounted) return;
      setState(() => _routine = _routine.withAnchor(choice.anchor, time));
    }
    setState(() {
      _choice = choice;
      // الافتراضي بيتبع المرساة: ٣٠ قبل الأكل، ١٥ قبل النوم
      _gap = choice.defaultGap;
    });
  }

  DoseTiming get _timing => _fixed
      ? FixedTiming(_fixedTime)
      : AnchorTiming(_choice.anchor, _choice.before ? -_gap : _gap);

  DateTime get _preview {
    final engine = ScheduleEngine(_routine);
    final day = _day;
    return switch (_timing) {
      AnchorTiming(:final anchor, :final offsetMinutes) =>
        engine.resolveTime(anchor: anchor, offsetMinutes: offsetMinutes, onDay: day),
      FixedTiming(:final minuteOfDay) => engine.resolveFixed(minuteOfDay: minuteOfDay, onDay: day),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_timing);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  if (widget.kicker != null) ...[
                    Kicker(widget.kicker!),
                    const SizedBox(height: F.s4),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      widget.name,
                      textDirection: nameDirection(widget.name),
                      style: TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w600,
                        color: F.mutedDark,
                        fontFamily: F.monoFamily,
                        fontFamilyFallback: F.monoFallback,
                      ),
                    ),
                  ),
                  const SizedBox(height: F.s4),
                  Text(
                    'إمتى؟',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.s8),
                  // **الوضعين جنب بعض فوق** (قرار المالك، ٢٤ سبتمبر ٢٠٢٦):
                  // «مع الأكل / الروتين» هو الأول والمختار افتراضياً، و«ساعة
                  // محددة» جنبه بنفس الحجم — مش لينك تحت الزرار زي ما كان.
                  // المرساة لسه الافتراضي؛ اللي اتغيّر إن الساعة بقت مرئية.
                  Row(
                    children: [
                      Expanded(
                        child: AnchorChip(
                          key: const ValueKey('mode-anchor'),
                          label: 'مع الأكل / الروتين',
                          selected: !_fixed,
                          onTap: () => setState(() => _fixed = false),
                        ),
                      ),
                      const SizedBox(width: F.s8),
                      Expanded(
                        child: AnchorChip(
                          key: const ValueKey('mode-fixed'),
                          label: 'ساعة محددة',
                          selected: _fixed,
                          onTap: () => setState(() => _fixed = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: F.s12),
                  if (_fixed) ...[
                    // بنقولها صراحة: الجرعة دي مش هتتحرك مع الروتين.
                    const _FixedNotice(),
                    const SizedBox(height: F.s12),
                    _FixedTimePicker(
                      value: _fixedTime,
                      onChanged: (value) => setState(() => _fixedTime = value),
                    ),
                  ] else ...[
                    Text(
                      'اختار الأكلة أو الميعاد الأول — الساعة بتتحسب لوحدها.',
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                    const SizedBox(height: F.s12),
                    Wrap(
                      spacing: F.s8,
                      runSpacing: F.s8,
                      children: [
                        for (final choice in anchorChoices)
                          AnchorChip(
                            // مرساة مش متحددة بتتقال بعلامة استفهام: الدوسة
                            // عليها سؤال قبل ما تبقى اختيار
                            label: _routine.isSet(choice.anchor) ? choice.label : '${choice.label}؟',
                            selected: choice == _choice,
                            onTap: () => _pick(choice),
                          ),
                      ],
                    ),
                    const SizedBox(height: F.gap),
                    _GapCard(
                      value: _gap,
                      onChanged: (value) => setState(() => _gap = value),
                    ),
                  ],
                  const SizedBox(height: F.s12),
                  // المعاينة — ذهبية لأنها بتقول «ده اللي هيرن»: بتتحدّث مع كل ضغطة.
                  Container(
                    padding: const EdgeInsets.all(F.s14),
                    decoration: BoxDecoration(
                      color: F.cardGround,
                      borderRadius: BorderRadius.circular(F.radiusCard),
                      border: Border.all(color: F.gold, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(color: F.gold, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: F.s10),
                        Expanded(
                          child: Text(
                            'يعني حوالي ${arabicTime(_preview)}',
                            style: TextStyle(
                              fontSize: F.minBodySize,
                              fontWeight: FontWeight.w700,
                              color: F.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FPrimaryButton(label: widget.saveLabel, onPressed: _saving ? null : _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «بكام؟» — بكرة دقايق في كارت: من ٠ لـ١٨٠ بخطوة ٥، نفس المدى اللي كان
/// للعدّاد بالحرف.
class _GapCard extends StatelessWidget {
  const _GapCard({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  /// نفس حدود العدّاد القديم — الإزاحة المخزّنة ما اتغيّرش مداها.
  static const int minGap = 0;
  static const int maxGap = 180;
  static const int step = 5;

  @override
  Widget build(BuildContext context) => FCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'بكام؟',
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
            ),
            const SizedBox(height: F.s4),
            FNumberWheel(
              key: const ValueKey('gap-wheel'),
              value: value,
              min: minGap,
              max: maxGap,
              step: step,
              unit: 'دقيقة',
              semanticsLabel: 'الإزاحة بالدقايق',
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

/// التنبيه اللي لازم يتقال لما الجرعة على ساعة ثابتة.
///
/// عاجي مش ذهبي: ده تنبيه معلوماتي مش تذكير ولا حالة نشطة.
class _FixedNotice extends StatelessWidget {
  const _FixedNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.s14),
        decoration: BoxDecoration(
          color: F.railGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
        ),
        child: Text(
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
  Widget build(BuildContext context) => FCard(
        padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.gap),
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
            const SizedBox(height: F.s8),
            FTimeWheel(value: value, onChanged: onChanged),
          ],
        ),
      );
}
