import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/minute_of_day.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../../core/widgets/f_wheels.dart';

/// اختيار سريع لساعة — «الصبح ٩» وأخواتها: افتراضيات بتتعدّل على البكرة.
class QuickTime {
  const QuickTime(this.label, this.minute);
  final String label;
  final MinuteOfDay minute;
}

/// الأربع شرايح السريعة (قرار المالك، ٢٧ سبتمبر ٢٠٢٦): الصبح ٩ / الضهر ٢ /
/// العصر ٥ / بالليل ٩ — كل واحدة بتحط البكرة عليها، والبكرة بتتحرّك بعدها.
const List<QuickTime> quickTimes = [
  QuickTime('الصبح ٩', MinuteOfDay(9 * 60)),
  QuickTime('الضهر ٢', MinuteOfDay(14 * 60)),
  QuickTime('العصر ٥', MinuteOfDay(17 * 60)),
  QuickTime('بالليل ٩', MinuteOfDay(21 * 60)),
];

/// «محرّر الجرعة» (المخطط 23) — شاشة واحدة بتتعاد في كل مكان بيتحدد فيه
/// ميعاد: إضافة دوا، تعديل دوا، ومراجعة الروشتة.
///
/// **الساعة بالساعة وبس** (٢٧ سبتمبر ٢٠٢٦): أربع شرايح سريعة فوق، والبكرة
/// تحتها، والمعاينة ذهبية بتتحدّث مع كل حركة. مفيش مراسي ولا روتين —
/// علاقة الأكل كلمة تعليمات على الدوا كله في الفورم، مش هنا.
class DoseEditor extends StatefulWidget {
  const DoseEditor({
    required this.name,
    required this.onSave,
    this.initialTiming,
    this.today,
    this.kicker,
    this.saveLabel = 'احفظ الجرعة',
    super.key,
  });

  /// اسم الدوا — بيتعرض فوق «إمتى؟» بالـmono.
  final String name;
  final FixedTiming? initialTiming;
  final DateTime? today;

  /// سطر صغير فوق الاسم — «الجرعة ١ من ٣».
  final String? kicker;
  final String saveLabel;

  /// بيتنده بالساعة المختارة؛ اللي بيفتح الشاشة هو اللي بيحفظ وبيقفلها.
  final Future<void> Function(FixedTiming timing) onSave;

  /// البكرة بتقف هنا لما مفيش ساعة جاية من برّه.
  static final MinuteOfDay restTime = MinuteOfDay.hm(9);

  @override
  State<DoseEditor> createState() => _DoseEditorState();
}

class _DoseEditorState extends State<DoseEditor> {
  late MinuteOfDay _time = widget.initialTiming?.minuteOfDay ?? DoseEditor.restTime;
  bool _saving = false;

  DateTime get _day => widget.today ?? DateTime.now();

  DateTime get _preview => const ScheduleEngine().resolveFixed(minuteOfDay: _time, onDay: _day);

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(FixedTiming(_time));
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
                    'الساعة كام؟',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.s8),
                  // شرايح سريعة: شبكة ٢×٢ بعرض متساوي — أربعة في صف واحد
                  // بيقصّوا الكلمة على SE
                  QuickTimeChips(selected: _time, onPick: (m) => setState(() => _time = m)),
                  const SizedBox(height: F.s12),
                  _TimePicker(value: _time, onChanged: (value) => setState(() => _time = value)),
                  const SizedBox(height: F.s12),
                  // المعاينة — ذهبية لأنها بتقول «ده اللي هيرن»: بتتحدّث مع كل حركة.
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
                            'هيرن الساعة ${arabicTime(_preview)}',
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

/// الأربع شرايح السريعة — شبكة ٢×٢. المختارة هي اللي البكرة واقفة عليها
/// بالظبط؛ ساعة تانية على البكرة = ولا شريحة مختارة.
class QuickTimeChips extends StatelessWidget {
  const QuickTimeChips({required this.selected, required this.onPick, super.key});

  final MinuteOfDay? selected;
  final ValueChanged<MinuteOfDay> onPick;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final pair in const [
            [0, 1],
            [2, 3],
          ]) ...[
            Row(
              children: [
                for (final i in pair) ...[
                  Expanded(
                    child: AnchorChip(
                      key: ValueKey('quick-time-${quickTimes[i].minute.minutes}'),
                      label: quickTimes[i].label,
                      selected: selected == quickTimes[i].minute,
                      onTap: () => onPick(quickTimes[i].minute),
                    ),
                  ),
                  if (i != pair.last) const SizedBox(width: F.s8),
                ],
              ],
            ),
            if (pair.first == 0) const SizedBox(height: F.s8),
          ],
        ],
      );
}

/// الساعة الكبيرة والعجلة.
class _TimePicker extends StatelessWidget {
  const _TimePicker({required this.value, required this.onChanged});

  final MinuteOfDay value;
  final ValueChanged<MinuteOfDay> onChanged;

  @override
  Widget build(BuildContext context) => FCard(
        padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.gap),
        child: Column(
          children: [
            Text(
              arabicTime(DateTime(2026, 1, 1, value.hour, value.minute)),
              style: TextStyle(
                fontSize: F.bigTimeSize,
                fontWeight: FontWeight.w700,
                color: F.greenStrong,
              ),
            ),
            const SizedBox(height: F.s8),
            FTimeWheel(value: value, onChanged: onChanged),
          ],
        ),
      );
}
