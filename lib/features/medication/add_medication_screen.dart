import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import 'dose_editor.dart';
import 'medication_draft.dart';
import 'dose_row.dart';

/// «إضافة دواء» (المخطط 20) — الحقول الأول، وبعدها محرّر الجرعة.
///
/// هنا الاسم والجرعة وكام مرة ومع الأكل والمدة. «كمّل» بيسلّم لـ[DoseEditor]
/// مرة لكل جرعة في اليوم، متعبّي من الإجابات دي — والمراسي بتفضل هي التحكم
/// الأساسي هناك. **ولا حاجة بتتحفظ قبل آخر «احفظ الجرعة»**: لو رجع في النص،
/// مفيش دوا نص مكتوب.
///
/// «كام مرة» → مراسي عُرف تشغيلي مش ورقة: ١× الفطار، ٢× الفطار والعشا،
/// ٣× الفطار والغدا والعشا — وكل واحدة بتتعدّل في محرّرها.
class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({
    required this.routine,
    this.today,
    this.initialName,
    this.initialAmount,
    this.initialTimings = const [],
    this.initialDurationDays,
    this.draft = false,
    super.key,
  });

  final DayRoutine routine;
  final DateTime? today;

  /// قيم مبدئية — من قراءة الروشتة. بتتعرض للتعديل، ما بتتحفظش لوحدها.
  final String? initialName;
  final String? initialAmount;
  /// **وضع المسوّدة**: بترجّع [MedicationDraft] من غير ما تكتب أي حاجة.
  ///
  /// شاشة مراجعة الروشتة بتستعملها كده: «عدّل» بتعدّل سطر في الذاكرة
  /// وبترجع، والكتابة كلها مرة واحدة عند «تمام». قبل كده كانت بتحفظ فوراً،
  /// فزرار كان بيحفظ شوية أدوية والتاني الباقي — ومن هنا جه ضياع الجرعات.
  final bool draft;

  /// جرعات الروشتة **كلها** — فاضية يعني إدخال بإيد من الأول.
  ///
  /// كانت جرعة واحدة، وشاشة المراجعة كانت بتبعت أول وحدة بس: دوا مرتين في
  /// اليوم يتعدّل = تذكير واحد. القايمة هي اللي بتقفل الباب ده.
  final List<DoseTiming> initialTimings;
  final int? initialDurationDays;

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

/// مع الأكل: قبل / مع / بعد — بتحدد إزاحة المرساة الافتراضية.
enum FoodRelation { before, with_, after }

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _amount = TextEditingController(text: widget.initialAmount ?? '');
  int _timesPerDay = 1;
  FoodRelation _food = FoodRelation.before;

  /// جرعات اليوم قبل ما تتراجع واحدة واحدة — **في الذاكرة، ولسه ما اتحفظتش**.
  ///
  /// بتتعبّى من الورقة لو جاية منها، وإلا من «كام مرة» + «مع الأكل». و«شيل»
  /// و«أضف جرعة» بيغيّروا العدد هنا: ده اللي كان ناقص، ومن غيره سطر روشتة
  /// بأربع جرعات ما كانش ينفع يتعدّل لاتنين.
  List<DoseTiming> _doses = const [];
  bool _openEnded = true;
  int _days = 7;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final days = widget.initialDurationDays;
    if (days != null) {
      _openEnded = false;
      _days = days.clamp(1, 90);
    }
    _doses = widget.initialTimings.isNotEmpty ? [...widget.initialTimings] : _fromConvention();
    if (widget.initialTimings.firstOrNull case AnchorTiming(:final offsetMinutes)) {
      _food = offsetMinutes == 0
          ? FoodRelation.with_
          : offsetMinutes < 0
              ? FoodRelation.before
              : FoodRelation.after;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// عُرف «كام مرة» + «مع الأكل» — مش الورقة.
  List<DoseTiming> _fromConvention() {
    final anchors = switch (_timesPerDay) {
      1 => [DayAnchor.breakfast],
      2 => [DayAnchor.breakfast, DayAnchor.dinner],
      _ => [DayAnchor.breakfast, DayAnchor.lunch, DayAnchor.dinner],
    };
    return [for (final anchor in anchors) _withFood(anchor)];
  }

  DoseTiming _withFood(DayAnchor anchor) => AnchorTiming(
        anchor,
        switch (_food) {
          FoodRelation.before => -defaultOffsetBefore(anchor),
          FoodRelation.with_ => 0,
          FoodRelation.after => 30,
        },
      );

  /// «كام مرة» و«مع الأكل» بيعيدوا بناء القايمة — الشرايح دي **إعداد مسبق**،
  /// ولما المستخدم يغيّرها يبقى قصده يبدأ من جديد.
  void _reseed(VoidCallback change) => setState(() {
        change();
        _doses = _fromConvention();
      });

  /// «أضف جرعة»: أول مرساة لسه مش مستعملة — والمستخدم بيراجعها في محرّرها
  /// بعد «كمّل» زي أي جرعة تانية.
  void _addDose() {
    const order = [DayAnchor.breakfast, DayAnchor.lunch, DayAnchor.dinner, DayAnchor.wake, DayAnchor.sleep];
    final used = {
      for (final t in _doses)
        if (t case AnchorTiming(:final anchor)) anchor,
    };
    final next = order.firstWhere((a) => !used.contains(a), orElse: () => DayAnchor.dinner);
    setState(() => _doses = [..._doses, _withFood(next)]);
  }

  /// الساعة المحسوبة على مواعيد اليوم — عرض بس، عمرها ما بتتخزّن.
  DateTime _resolve(DoseTiming timing) {
    final engine = ScheduleEngine(widget.routine);
    final day = widget.today ?? DateTime.now();
    return switch (timing) {
      AnchorTiming(:final anchor, :final offsetMinutes) =>
        engine.resolveTime(anchor: anchor, offsetMinutes: offsetMinutes, onDay: day),
      FixedTiming(:final minuteOfDay) => engine.resolveFixed(minuteOfDay: minuteOfDay, onDay: day),
    };
  }

  /// الأرضية: الدوا لازم له جرعة واحدة. آخر صف مالوش «شيل» أصلاً.
  void _removeDose(int index) {
    if (_doses.length <= 1) return;
    setState(() => _doses = [..._doses]..removeAt(index));
  }

  /// «كمّل»: محرّر لكل جرعة بالترتيب، والحفظ بعد الأخيرة بس.
  Future<void> _continue() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final navigator = Navigator.of(context);
      final initial = _doses;
      final chosen = <DoseTiming>[];

      for (var i = 0; i < initial.length; i++) {
        DoseTiming? picked;
        await navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => DoseEditor(
              name: _name.text.trim(),
              routine: widget.routine,
              today: widget.today,
              initialTiming: initial[i],
              kicker: initial.length == 1
                  ? null
                  : 'الجرعة ${arabicNumber(i + 1)} من ${arabicNumber(initial.length)}',
              saveLabel: i == initial.length - 1 ? 'احفظ الجرعة' : 'الجرعة اللي بعدها',
              onSave: (timing) async {
                picked = timing;
                navigator.pop();
              },
            ),
          ),
        );
        if (picked == null || !mounted) return; // رجع من غير ما يختار — مفيش حفظ
        chosen.add(picked!);
      }

      await _save(chosen);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(List<DoseTiming> timings) async {
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final today = widget.today ?? DateTime.now();
    final amount = _amount.text.trim();
    final result = MedicationDraft(
      name: _name.text.trim(),
      amountLabel: amount.isEmpty ? null : amount,
      amountUnknown: amount.isEmpty,
      timings: timings,
      // المدة المفتوحة هي الافتراضي — وما بنخمّنش مدة أبداً.
      durationDays: _openEnded ? null : _days,
    );

    // مسوّدة: بنرجّع اللي اتظبط، **وما بنكتبش**. اللي نادانا هو اللي بيقرر
    // إمتى يتحفظ — ومن غير كده الحفظ بيتفرّق على زرارين.
    if (widget.draft) {
      if (mounted) navigator.pop(result);
      return;
    }

    // طريق واحد لكتابة «دوا بـN جرعة» — نفس اللي شاشة المراجعة بتستعمله.
    await services.medications.addMedicationWithDoses(
      patientId: services.patientId,
      name: result.name,
      amountLabel: result.amountLabel,
      timings: result.timings,
      startDate: today,
      durationDays: result.durationDays,
    );
    await services.scheduler.rescheduleAll();

    // نفس النوع في الحالتين، عشان اللي نادى ما يفرقش: null = رجع من غير حفظ.
    if (mounted) navigator.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final fromPaper = widget.initialTimings.isNotEmpty;
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
                  const Kicker('إضافة يدوية'),
                  const SizedBox(height: F.s4),
                  Text(
                    'ضيف دوا وجرعته',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.gap),
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('اسم الدوا والتركيز'),
                        _Field(
                          controller: _name,
                          hint: 'زي Concor 5mg',
                          mono: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: F.gap),
                        const _FieldLabel('الجرعة في المرة (اختياري)'),
                        _Field(controller: _amount, hint: 'زي: قرص واحد'),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  if (!fromPaper)
                    FCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _FieldLabel('كام مرة في اليوم؟'),
                          Row(
                            children: [
                              for (final n in [1, 2, 3]) ...[
                                Expanded(
                                  child: AnchorChip(
                                    label: switch (n) { 1 => 'مرة', 2 => 'مرتين', _ => '٣ مرات' },
                                    selected: _timesPerDay == n,
                                    onTap: () => _reseed(() => _timesPerDay = n),
                                  ),
                                ),
                                if (n != 3) const SizedBox(width: F.s8),
                              ],
                            ],
                          ),
                          const SizedBox(height: F.gap),
                          const _FieldLabel('مع الأكل؟'),
                          Row(
                            children: [
                              for (final f in FoodRelation.values) ...[
                                Expanded(
                                  child: AnchorChip(
                                    label: switch (f) {
                                      FoodRelation.before => 'قبل الأكل',
                                      FoodRelation.with_ => 'مع الأكل',
                                      FoodRelation.after => 'بعد الأكل',
                                    },
                                    selected: _food == f,
                                    onTap: () => _reseed(() => _food = f),
                                  ),
                                ),
                                if (f != FoodRelation.values.last) const SizedBox(width: F.s8),
                              ],
                            ],
                          ),
                          const SizedBox(height: F.s10),
                          Text(
                            'الأوقات بتتظبط على مراسي يومك — وهتراجعها واحدة واحدة بعد ما تكمّل.',
                            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: F.s12),
                  // قايمة الجرعات قبل «كمّل» — العدد بيتظبط هنا، والتوقيت
                  // بيتراجع واحد واحد بعد كده. الساعة للعرض بس.
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FieldLabel(fromPaper ? 'جرعات الورقة' : 'جرعات اليوم'),
                        const SizedBox(height: F.s8),
                        for (final (i, timing) in _doses.indexed)
                          DoseRow(
                            key: ValueKey('dose-row-$i'),
                            timing: timing,
                            time: arabicTime(_resolve(timing)),
                            onRemove: _doses.length > 1 && !_busy ? () => _removeDose(i) : null,
                          ),
                        SizedBox(
                          height: F.minTapTarget,
                          child: FSecondaryButton(
                            label: 'أضف جرعة',
                            onPressed: _busy ? null : _addDose,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('المدة'),
                        Row(
                          children: [
                            Expanded(
                              child: AnchorChip(
                                label: 'مفتوحة',
                                selected: _openEnded,
                                onTap: () => setState(() => _openEnded = true),
                              ),
                            ),
                            const SizedBox(width: F.s8),
                            Expanded(
                              child: AnchorChip(
                                label: 'أيام محددة',
                                selected: !_openEnded,
                                onTap: () => setState(() => _openEnded = false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: F.s10),
                        if (!_openEnded)
                          MinuteStepper(
                            value: _days,
                            step: 1,
                            min: 1,
                            max: 90,
                            unit: 'يوم',
                            onChanged: (value) => setState(() => _days = value),
                          )
                        else
                          Text(
                            'التذكير هيفضل شغال لحد ما توقفه بنفسك.',
                            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(F.gap),
              child: FPrimaryButton(
                label: 'كمّل — إمتى؟',
                onPressed: _busy || _name.text.trim().isEmpty ? null : _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: Text(
          text,
          style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.mono = false, this.onChanged});

  final TextEditingController controller;
  final String hint;
  final bool mono;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: F.minBodySize,
          fontFamily: mono ? F.monoFamily : null,
          fontFamilyFallback: mono ? F.monoFallback : null,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: F.minTextSize, color: F.placeholder),
          filled: true,
          fillColor: F.fieldGround,
          contentPadding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            borderSide: BorderSide(color: F.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            borderSide: BorderSide(color: F.line),
          ),
        ),
      );
}
