import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/ramadan.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../../core/widgets/f_wheels.dart';

/// «يومك في رمضان» (المخطط 25).
///
/// اليوم بيترسي على **السحور · الفطار (المغرب) · النوم** بدل الخمس مراسي.
/// المعاينة هي قلب الشاشة: «N أدوية هتتحرك» وقبل → بعد لكل دوا، محسوبة
/// من نفس المحرّك اللي هيرن بيه.
///
/// **ولا حاجة بتتغيّر قبل «فعّل وضع رمضان».** مفيش مفتاح ولا حفظ تلقائي:
/// الزرار هو الفعل، والشاشة لو اتقفلت من غيره الجدول زي ما هو بالحرف.
/// المنطق والنسخة الاحتياطية في `domain/scheduling/ramadan.dart`
/// و`RoutineRepository` — الشاشة بتسأل وبتعرض وبس.
class RamadanScreen extends StatefulWidget {
  const RamadanScreen({this.today, super.key});

  /// للاختبارات — يوم المعاينة.
  final DateTime? today;

  @override
  State<RamadanScreen> createState() => _RamadanScreenState();
}

class _RamadanScreenState extends State<RamadanScreen> {
  bool _loaded = false;

  /// الحالة المحفوظة — بتتقرا مرة عند الفتح وبعد كل ضغطة.
  bool _on = false;
  RamadanTimes _times = RamadanTimes.cairoDefaults;

  /// الروتين الساري، والأصل المحفوظ لو رمضان شغّال — للمعاينة بس.
  DayRoutine? _routine;
  DayRoutine? _original;
  List<DoseSchedule> _schedules = const [];

  bool _busy = false;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  Future<void> _reload() async {
    final services = AppScope.of(context);
    final saved = await services.routines.ramadanTimes(services.patientId);
    final routine = await services.routines.getRoutine(services.patientId);
    final original = await services.routines.ramadanOriginal(services.patientId);
    final schedules = await services.medications.activeSchedules(services.patientId);
    if (!mounted) return;
    setState(() {
      _on = saved != null;
      _times = saved ?? _times;
      _routine = routine ?? DayRoutine.fallback;
      _original = original;
      _schedules = schedules;
    });
  }

  /// قبل → بعد. مقفول: الساري → رمضان المحسوب من المواعيد اللي على الشاشة.
  /// شغّال: الأصل المحفوظ → الساري (اللي هو رمضان فعلاً) — عشان الأسهم
  /// تفضل صادقة ومش تقارن الجدول بنفسه.
  DayRoutine get _before => _on ? (_original ?? _routine ?? DayRoutine.fallback) : (_routine ?? DayRoutine.fallback);
  DayRoutine get _after => _on ? (_routine ?? DayRoutine.fallback) : ramadanRoutine(_before, _times);

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    try {
      if (_on) {
        await services.routines.leaveRamadan(services.patientId);
      } else {
        await services.routines.enterRamadan(services.patientId, _times);
      }
      // نفس ما بيحصل بعد «عدّل يومك»: جرعات المراسي بتاخد أرقام جديدة،
      // والساعات الثابتة بترجع بنفس أرقامها.
      await services.scheduler.rescheduleAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ScheduleEngine(_before);
    final ramadanEngine = ScheduleEngine(_after);
    final moving = [
      for (final s in _schedules)
        if (s.timing is AnchorTiming) s,
    ];
    final fixed = [
      for (final s in _schedules)
        if (s.timing is FixedTiming) s,
    ];

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
                  Text(
                    'يومك في رمضان',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.s6),
                  Text(
                    'في رمضان يومك بيترسي على السحور والفطار (المغرب) والنوم — '
                    'بدل الخمس مراسي العادية. كل جرعة مربوطة بالأكل هتتحرك معاها لوحدها.',
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                  ),
                  const SizedBox(height: F.gap),
                  // الحالة الحالية — بوضوح، والذهبي وهو شغّال (إنت هنا)
                  FCard(
                    tone: _on ? FCardTone.attention : FCardTone.warm,
                    child: Text(
                      _on
                          ? 'وضع رمضان شغّال دلوقتي — جدولك على السحور والمغرب.'
                          : 'وضع رمضان مقفول — جدولك العادي شغّال.',
                      style: TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w700,
                        color: F.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  FCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _TimeRow(
                          label: 'السحور',
                          value: _times.suhoor,
                          onChanged: (v) => setState(() => _times = _times.copyWith(suhoor: v)),
                        ),
                        Divider(height: 1, color: F.lineSoft),
                        _TimeRow(
                          label: 'الفطار (المغرب)',
                          value: _times.iftar,
                          onChanged: (v) => setState(() => _times = _times.copyWith(iftar: v)),
                        ),
                        Divider(height: 1, color: F.lineSoft),
                        // النوم بيتحسب: بعد السحور بساعة — مش بيتظبط لوحده
                        _TimeRow(label: 'النوم', value: _after.sleep, derived: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.gap),
                  // قلب الشاشة: إيه اللي هيتحرك، وإزاي
                  Text(
                    moving.isEmpty
                        ? 'مفيش أدوية مربوطة بالأكل لسه — مفيش حاجة هتتحرك.'
                        : _countLine(moving.length, on: _on),
                    style: TextStyle(
                      fontSize: F.minBodySize,
                      fontWeight: FontWeight.w700,
                      color: F.green,
                    ),
                  ),
                  if (moving.isNotEmpty) ...[
                    const SizedBox(height: F.s8),
                    FCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, s) in moving.indexed) ...[
                            if (i > 0) Divider(height: 1, color: F.lineSoft),
                            _MoveRow(
                              name: s.medicationName,
                              before: engine.resolve(s, _today),
                              after: ramadanEngine.resolve(s, _today),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (fixed.isNotEmpty) ...[
                    const SizedBox(height: F.s12),
                    Text(
                      '${fixed.map((s) => s.medicationName).join('، ')} — ساعة ثابتة، ما بتتحركش.',
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: F.s12),
                  Text(
                    _on
                        ? 'لما تقفله يومك بيرجع زي ما كان قبل رمضان بالظبط.'
                        : 'مفيش حاجة بتتغيّر قبل ما تدوس «فعّل وضع رمضان».',
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(F.gap),
              child: FPrimaryButton(
                label: _on ? 'اقفل وضع رمضان' : 'فعّل وضع رمضان',
                onPressed: _busy || _routine == null ? null : _toggle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _countLine(int n, {required bool on}) => switch ((n, on)) {
        (1, false) => 'دوا واحد هيتحرك',
        (1, true) => 'دوا واحد اتحرك',
        (2, false) => 'دواءين هيتحركوا',
        (2, true) => 'دواءين اتحركوا',
        (_, false) when n <= 10 => '${arabicNumber(n)} أدوية هتتحرك',
        (_, true) when n <= 10 => '${arabicNumber(n)} أدوية اتحركت',
        (_, false) => '${arabicNumber(n)} دوا هيتحركوا',
        (_, true) => '${arabicNumber(n)} دوا اتحركوا',
      };
}

/// صف مرساة رمضان: الاسم والوقت، والبكرة تحته على طول — أو محسوب.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    this.derived = false,
    this.onChanged,
  });

  final String label;
  final MinuteOfDay value;
  final bool derived;
  final ValueChanged<MinuteOfDay>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: F.minBodySize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                ),
                Text(
                  arabicTime(DateTime(2026, 1, 1, value.hour, value.minute)),
                  style: TextStyle(
                    fontSize: F.subtitleSize,
                    fontWeight: FontWeight.w700,
                    color: derived ? F.mutedDark : F.greenDeep,
                  ),
                ),
              ],
            ),
          ),
          if (derived)
            Padding(
              padding: EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'بعد السحور بساعة',
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                ),
              ),
            ),
          if (onChanged != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(F.s12, 0, F.s12, F.s8),
              child: FTimeWheel(value: value, onChanged: onChanged!),
            ),
        ],
      );
}

/// دوا واحد: الاسم mono، وقبل → بعد بالوقتين. السهم أيقونة اتجاهية،
/// فبيلف مع RTL لوحده.
class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.name, required this.before, required this.after});

  final String name;
  final DateTime before;
  final DateTime after;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                name,
                textDirection: nameDirection(name),
                style: TextStyle(
                  fontSize: F.minBodySize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                ),
              ),
            ),
            const SizedBox(height: F.s4),
            Row(
              children: [
                Text(
                  arabicTime(before),
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: F.s8),
                  child: Icon(Icons.arrow_forward, size: 20, color: F.muted),
                ),
                Text(
                  arabicTime(after),
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
