/// **بكر الأرقام والساعة — عيلة واحدة لكل التطبيق.**
///
/// قرار منتج: كل رقم أو ساعة المستخدم بيحطّها بتتحط ببكرة زي بكرة الساعة
/// بتاعة آبل — مفيش عدّاد −/+ ولا شريط ولا رقم بيتكتب. المكان الواحد ده
/// هو اللي بيضمن إن الشكل واحد: خط كبير، الصف المختار بأرضية خضرا هادية،
/// هزّة على كل نقلة (iOS بيعملها لوحده، وأندرويد بناخدها من
/// [HapticFeedback])، وأرقام عربي.
///
/// `CupertinoPicker` مش `CupertinoDatePicker`: الأولانية بتاخد أولادها
/// منّنا، فالأرقام عربي والخط بمقاسنا. التانية بترسم أرقام إنجليزي بحجم
/// ثابت صغير وبتكسر قاعدتين مع بعض.
library;

import 'package:flutter/cupertino.dart' show CupertinoPicker, CupertinoPickerDefaultSelectionOverlay;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../format/arabic_time.dart';
import '../theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';


/// ارتفاع الصف الواحد — الخط ٢٦ ومعاه هوا.
const double wheelItemExtent = 44;

/// عمود واحد — اللي البكرتين بيتشاركوه.
class _WheelColumn extends StatelessWidget {
  const _WheelColumn({
    required this.controller,
    required this.labels,
    required this.onChanged,
    required this.semantics,
    this.height = wheelItemExtent * 3,
  });

  final FixedExtentScrollController controller;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  final String semantics;
  final double height;

  static void tick() {
    // آبل بتهزّ لوحدها على iOS؛ على أندرويد إحنا اللي بنهزّ
    if (defaultTargetPlatform != TargetPlatform.iOS) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: semantics,
        child: SizedBox(
          height: height,
          child: CupertinoPicker(
            scrollController: controller,
            itemExtent: wheelItemExtent,
            selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
              background: F.green.withValues(alpha: 0.14),
            ),
            onSelectedItemChanged: (i) {
              tick();
              onChanged(i);
            },
            children: [
              for (final label in labels)
                Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: F.minBodySize + 6,
                      fontWeight: FontWeight.w600,
                      color: F.ink,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// بكرة رقم: من [min] لـ[max] بخطوة [step]، وكلمة الوحدة جنب كل رقم.
///
/// [value] ممكن يبقى null: ساعتها البكرة واقفة على [rest] (أو [min])
/// **ومفيش حاجة اتكتبت** — [onChanged] بتتنده بس لما المستخدم يحرّكها
/// بإيده. ده اللي بيخلّي سؤال اختياري («سنّك كام؟») أو رقم مالوش افتراضي
/// عندنا («المعمل قال صيام كام ساعة؟» — القاعدة ٦) يفضلوا فاضيين لحد ما
/// الإنسان يقول. لما [value] يرجع null من برّه، البكرة بترجع لمكان الراحة
/// من غير ما النقلة دي تتحسب اختيار.
class FNumberWheel extends StatefulWidget {
  const FNumberWheel({
    required this.min,
    required this.max,
    required this.onChanged,
    this.value,
    this.step = 1,
    this.unit,
    this.labelOf,
    this.rest,
    this.height = defaultHeight,
    this.semanticsLabel,
    super.key,
  });

  final int? value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;

  /// «دقيقة» → «٣٠ دقيقة». [labelOf] بيغلبها لو الجمع بيتغيّر مع الرقم.
  final String? unit;
  final String Function(int value)? labelOf;

  /// فين البكرة بتقف وهي فاضية — مش قيمة، ومفيش حاجة بتتكتب منها.
  final int? rest;
  final double height;
  final String? semanticsLabel;

  static const double itemExtent = wheelItemExtent;

  /// ~٢٫٥ صف ظاهر — اتقاست على iPhone SE مع باقي شاشة «نتعرّف عليك».
  static const double defaultHeight = 110;

  int get count => (max - min) ~/ step + 1;

  int indexOf(int v) => ((v - min) / step).round().clamp(0, count - 1);

  int valueAt(int index) => min + index * step;

  String label(int v) => labelOf?.call(v) ?? (unit == null ? arabicNumber(v) : '${arabicNumber(v)} $unit');

  @override
  State<FNumberWheel> createState() => _FNumberWheelState();
}

class _FNumberWheelState extends State<FNumberWheel> {
  late final _controller = FixedExtentScrollController(
    initialItem: widget.indexOf(widget.value ?? widget.rest ?? widget.min),
  );

  /// وإحنا بنحرّك البكرة بأنفسنا، النقلة دي مش «هو حرّكها».
  bool _syncing = false;

  @override
  void didUpdateWidget(FNumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _jumpTo(widget.indexOf(widget.value ?? widget.rest ?? widget.min));
    }
  }

  void _jumpTo(int index) {
    if (!_controller.hasClients || _controller.selectedItem == index) return;
    _syncing = true;
    _controller.jumpToItem(index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncing = false);
  }

  void _picked(int index) {
    if (_syncing) return;
    widget.onChanged(widget.valueAt(index));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _WheelColumn(
        controller: _controller,
        labels: [for (var i = 0; i < widget.count; i++) widget.label(widget.valueAt(i))],
        onChanged: _picked,
        semantics: widget.semanticsLabel ?? widget.unit ?? 'رقم',
        height: widget.height,
      );
}

/// بكرة الساعة: ساعة ودقايق (خطوة ٥) وزرارين ص/م بكلمة.
///
/// **البكرة مش بتلف**: `selectedItem` بتاعة البكرة اللافّة بتطلع أرقام
/// مفتوحة (سالبة وكبيرة)، والحساب بيبوظ بالسكوت. ونفس [MinuteOfDay]
/// داخل وخارج — التوقيت اللي بيتخزّن ما اتغيّرش عن أيام `TimeWheel`.
class FTimeWheel extends StatefulWidget {
  const FTimeWheel({required this.value, required this.onChanged, super.key});

  final MinuteOfDay value;
  final ValueChanged<MinuteOfDay> onChanged;

  static const int minuteStep = 5;
  static const double itemExtent = wheelItemExtent;
  static const double height = wheelItemExtent * 3;

  @override
  State<FTimeWheel> createState() => _FTimeWheelState();
}

class _FTimeWheelState extends State<FTimeWheel> {
  late FixedExtentScrollController _hours;
  late FixedExtentScrollController _minutes;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _hours = FixedExtentScrollController(initialItem: _hourIndex(widget.value));
    _minutes = FixedExtentScrollController(initialItem: _minuteIndex(widget.value));
  }

  @override
  void didUpdateWidget(FTimeWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // الشيب بيغيّر القيمة من برّه — البكرة لازم تلحقه عشان يفضل فيه رقم
    // واحد صح قدام المستخدم، مش اتنين مختلفين.
    _syncTo(_hours, _hourIndex(widget.value));
    _syncTo(_minutes, _minuteIndex(widget.value));
  }

  void _syncTo(FixedExtentScrollController controller, int index) {
    if (!controller.hasClients || controller.selectedItem == index) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients || controller.selectedItem == index) return;
      _syncing = true;
      controller.jumpToItem(index);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncing = false);
    });
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  static int _hourIndex(MinuteOfDay v) => (v.hour % 12 == 0 ? 12 : v.hour % 12) - 1;

  static int _minuteIndex(MinuteOfDay v) =>
      (v.minute ~/ FTimeWheel.minuteStep).clamp(0, 11);

  bool get _isEvening => widget.value.hour >= 12;

  void _emitFromWheels() {
    if (_syncing || !_hours.hasClients || !_minutes.hasClients) return;
    _emit(
      hour12: _hours.selectedItem + 1,
      minute: _minutes.selectedItem * FTimeWheel.minuteStep,
      isEvening: _isEvening,
    );
  }

  void _emit({required int hour12, required int minute, required bool isEvening}) {
    final hour24 = (hour12 % 12) + (isEvening ? 12 : 0);
    widget.onChanged(MinuteOfDay(hour24 * 60 + minute));
  }

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PeriodToggle(
            isEvening: _isEvening,
            onChanged: (evening) => _emit(
              hour12: widget.value.hour % 12 == 0 ? 12 : widget.value.hour % 12,
              minute: widget.value.minute,
              isEvening: evening,
            ),
          ),
          const SizedBox(width: F.gap),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _WheelColumn(
                    controller: _minutes,
                    semantics: 'الدقايق',
                    onChanged: (_) => _emitFromWheels(),
                    labels: [
                      for (var i = 0; i < 12; i++)
                        arabicDigits((i * FTimeWheel.minuteStep).toString().padLeft(2, '0')),
                    ],
                  ),
                ),
                Text(
                  ':',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: F.mutedDark),
                ),
                Expanded(
                  child: _WheelColumn(
                    controller: _hours,
                    semantics: 'الساعة',
                    onChanged: (_) => _emitFromWheels(),
                    labels: [for (var h = 1; h <= 12; h++) arabicNumber(h)],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

/// صبح ولا مسا — زرارين بكلمة، مش أيقونة.
class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.isEvening, required this.onChanged});

  final bool isEvening;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(label: 'ص', selected: !isEvening, onTap: () => onChanged(false)),
          const SizedBox(height: 8),
          _button(label: 'م', selected: isEvening, onTap: () => onChanged(true)),
        ],
      );

  Widget _button({required String label, required bool selected, required VoidCallback onTap}) =>
      SizedBox(
        width: F.minTapTarget,
        height: F.minTapTarget,
        child: Material(
          color: selected ? F.green : F.cardGround,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radius),
            side: BorderSide(color: selected ? F.green : F.line, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radius),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: selected ? F.onDark : F.ink,
                ),
              ),
            ),
          ),
        ),
      );
}
