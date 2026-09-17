import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';

/// عجلة اختيار الساعة.
///
/// مكتوبة بإيدنا بدل CupertinoDatePicker عشان دي بترسم أرقام إنجليزي بحجم
/// ثابت صغير — وده بيكسر قاعدتين مع بعض: الأرقام العربي والحد الأدنى للخط.
///
/// العجلة مش بتلف: `selectedItem` بتاعة العجلة اللافّة بتطلع أرقام مفتوحة
/// (سالبة وكبيرة)، والحساب بيبوظ بالسكوت.
class TimeWheel extends StatefulWidget {
  const TimeWheel({required this.value, required this.onChanged, super.key});

  final MinuteOfDay value;
  final ValueChanged<MinuteOfDay> onChanged;

  static const int minuteStep = 5;

  @override
  State<TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<TimeWheel> {
  static const _itemExtent = 56.0;

  late FixedExtentScrollController _hours;
  late FixedExtentScrollController _minutes;

  @override
  void initState() {
    super.initState();
    _hours = FixedExtentScrollController(initialItem: _hourIndex(widget.value));
    _minutes =
        FixedExtentScrollController(initialItem: _minuteIndex(widget.value));
  }

  @override
  void didUpdateWidget(TimeWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // الشيب بيغيّر القيمة من برّه — العجلة لازم تلحقه عشان يفضل فيه رقم
    // واحد صح قدام المستخدم، مش اتنين مختلفين.
    _syncTo(_hours, _hourIndex(widget.value));
    _syncTo(_minutes, _minuteIndex(widget.value));
  }

  void _syncTo(FixedExtentScrollController controller, int index) {
    if (!controller.hasClients || controller.selectedItem == index) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.hasClients && controller.selectedItem != index) {
        controller.jumpToItem(index);
      }
    });
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  static int _hourIndex(MinuteOfDay v) =>
      (v.hour % 12 == 0 ? 12 : v.hour % 12) - 1;

  static int _minuteIndex(MinuteOfDay v) =>
      (v.minute ~/ TimeWheel.minuteStep).clamp(0, 11);

  bool get _isEvening => widget.value.hour >= 12;

  void _emitFromWheels() {
    if (!_hours.hasClients || !_minutes.hasClients) return;
    _emit(
      hour12: _hours.selectedItem + 1,
      minute: _minutes.selectedItem * TimeWheel.minuteStep,
      isEvening: _isEvening,
    );
  }

  void _emit({
    required int hour12,
    required int minute,
    required bool isEvening,
  }) {
    final hour24 = (hour12 % 12) + (isEvening ? 12 : 0);
    widget.onChanged(MinuteOfDay(hour24 * 60 + minute));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
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
          child: SizedBox(
            height: _itemExtent * 3,
            child: Row(
              children: [
                Expanded(
                  child: _wheel(
                    controller: _minutes,
                    semantics: 'الدقايق',
                    labels: [
                      for (var i = 0; i < 12; i++)
                        arabicDigits(
                          (i * TimeWheel.minuteStep).toString().padLeft(2, '0'),
                        ),
                    ],
                  ),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: F.mutedDark,
                  ),
                ),
                Expanded(
                  child: _wheel(
                    controller: _hours,
                    semantics: 'الساعة',
                    labels: [for (var h = 1; h <= 12; h++) arabicNumber(h)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required List<String> labels,
    required String semantics,
  }) {
    return Semantics(
      label: semantics,
      child: ListWheelScrollView(
        controller: controller,
        itemExtent: _itemExtent,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: (_) => _emitFromWheels(),
        children: [
          for (final label in labels)
            Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: F.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// صبح ولا مسا — زرارين بكلمة، مش أيقونة.
class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.isEvening, required this.onChanged});

  final bool isEvening;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(label: 'ص', selected: !isEvening, onTap: () => onChanged(false)),
        const SizedBox(height: 8),
        _button(label: 'م', selected: isEvening, onTap: () => onChanged(true)),
      ],
    );
  }

  Widget _button({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return SizedBox(
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
}
