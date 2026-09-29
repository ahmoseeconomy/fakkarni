import 'package:flutter/material.dart';

import '../../ai/prescription_timing.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/minute_of_day.dart';
import '../medication/dose_editor.dart' show QuickTimeChips;

/// «اختار الساعات» لدوا من الروشتة — **الإنسان هو اللي بيختار**.
///
/// الروشتة قالت «كل ١٢ ساعة»؛ إحنا ما بنقولش ٨ و٨. بيختار أول ساعة (شرايح
/// سريعة + البكرة)، وبعدها بس بنعرض دوسة واحدة «كمّل كل ١٢ ساعة» — اقتراح
/// هو اللي بيوافق عليه. ولا حاجة بتتكتب هنا: الشيت بيرجّع الساعات للمسوّدة،
/// والحفظ لسه بـ«تمام» على شاشة المراجعة.
Future<List<MinuteOfDay>?> pickTimes(
  BuildContext context, {
  required TimingFacts facts,
  List<MinuteOfDay> initial = const [],
}) =>
    FSheet.show<List<MinuteOfDay>>(
      context,
      title: 'اختار الساعات',
      children: [PickTimesBody(facts: facts, initial: initial)],
    );

/// جسم الشيت — مفصول عشان الاختبار يبنيه لوحده.
class PickTimesBody extends StatefulWidget {
  const PickTimesBody({required this.facts, this.initial = const [], super.key});

  final TimingFacts facts;
  final List<MinuteOfDay> initial;

  /// البكرة بتقف هنا قبل ما يختار — مكان، مش ساعة مكتوبة.
  static final MinuteOfDay rest = MinuteOfDay.hm(8);

  @override
  State<PickTimesBody> createState() => _PickTimesBodyState();
}

class _PickTimesBodyState extends State<PickTimesBody> {
  late final List<MinuteOfDay> _picked = [...widget.initial];
  late MinuteOfDay _current = widget.initial.isEmpty ? PickTimesBody.rest : widget.initial.last;

  String _time(MinuteOfDay m) => arabicTime(DateTime(2026, 1, 1, m.hour, m.minute));

  List<MinuteOfDay> _sorted(Iterable<MinuteOfDay> xs) =>
      ({for (final x in xs) x.minutes: x}.values.toList())..sort((a, b) => a.minutes.compareTo(b.minutes));

  /// باقي جرعات اليوم لو كمّل بالفاصل من أول ساعة — null = مفيش اقتراح.
  List<MinuteOfDay>? get _continuation {
    final step = widget.facts.stepHours;
    final n = widget.facts.dosesPerDay;
    if (step == null || n == null || n < 2 || _picked.length != 1) return null;
    final first = _picked.single.minutes;
    return [for (var k = 1; k < n; k++) MinuteOfDay((first + k * step * 60) % 1440)];
  }

  void _add() => setState(() {
        if (!_picked.any((m) => m.minutes == _current.minutes)) _picked.add(_current);
      });

  @override
  Widget build(BuildContext context) {
    final words = widget.facts.words;
    final more = _continuation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (words.isNotEmpty) ...[
          Text(
            'الروشتة بتقول: ${words.join(' — ')}',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.s12),
        ],
        if (_picked.isNotEmpty) ...[
          for (final m in _sorted(_picked))
            Padding(
              padding: const EdgeInsets.only(bottom: F.s8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _time(m),
                      key: ValueKey('picked-${m.minutes}'),
                      style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                    ),
                  ),
                  SizedBox(
                    height: F.minTapTarget,
                    child: TextButton(
                      onPressed: () => setState(() => _picked.removeWhere((x) => x.minutes == m.minutes)),
                      child: Text('شيل', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: F.s4),
        ],
        if (more != null) ...[
          // اقتراح بدوسة — بعد ما هو اختار أول ساعة، ومش قبلها
          FSecondaryButton(
            key: const ValueKey('continue-interval'),
            label: 'كمّل كل ${hoursWord(widget.facts.stepHours!)} — ${more.map(_time).join(' و')}',
            onPressed: () => setState(() => _picked.addAll(more)),
          ),
          const SizedBox(height: F.gap),
        ],
        Text(
          _picked.isEmpty ? 'أول جرعة الساعة كام؟' : 'ساعة تانية؟',
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
        ),
        const SizedBox(height: F.s8),
        QuickTimeChips(selected: _current, onPick: (m) => setState(() => _current = m)),
        const SizedBox(height: F.s8),
        FTimeWheel(value: _current, onChanged: (m) => setState(() => _current = m)),
        const SizedBox(height: F.s8),
        FSecondaryButton(
          key: const ValueKey('add-time'),
          label: 'ضيف الساعة ${_time(_current)}',
          onPressed: _add,
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('times-done'),
          label: 'تمام',
          onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop(_sorted(_picked)),
        ),
      ],
    );
  }
}

/// «وقت آخر» على كارت دوا ليه ساعات خلاص (من الروشتة أو اختارها) — ساعة
/// **واحدة زيادة**، والإنسان هو اللي بيختارها (طلب المالك، ٢٩ سبتمبر ٢٠٢٦).
/// البكرة بتقف على ٨ كمكان مش كإجابة: «ضيف» مقفول لحد ما يدوس شريحة أو
/// يحرّك البكرة. ولا حاجة بتتكتب هنا — الساعة بترجع للمسوّدة، والحفظ لسه
/// بـ«تمام» على المراجعة (`MedicationSaveService`).
Future<MinuteOfDay?> pickOneMoreTime(BuildContext context, {List<MinuteOfDay> existing = const []}) =>
    FSheet.show<MinuteOfDay>(
      context,
      title: 'وقت آخر',
      children: [OneMoreTimeBody(existing: existing)],
    );

class OneMoreTimeBody extends StatefulWidget {
  const OneMoreTimeBody({this.existing = const [], super.key});

  /// الساعات اللي على الكارت — نفس الساعة مرتين ما بتتضافش.
  final List<MinuteOfDay> existing;

  @override
  State<OneMoreTimeBody> createState() => _OneMoreTimeBodyState();
}

class _OneMoreTimeBodyState extends State<OneMoreTimeBody> {
  MinuteOfDay _wheel = PickTimesBody.rest;

  /// null = لسه ما اختارش — البكرة واقفة مكانها بس.
  MinuteOfDay? _chosen;

  String _time(MinuteOfDay m) => arabicTime(DateTime(2026, 1, 1, m.hour, m.minute));

  void _choose(MinuteOfDay m) => setState(() {
        _wheel = m;
        _chosen = m;
      });

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final duplicate = chosen != null && widget.existing.any((m) => m.minutes == chosen.minutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الساعة كام؟',
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
        ),
        const SizedBox(height: F.s8),
        QuickTimeChips(selected: _chosen, onPick: _choose),
        const SizedBox(height: F.s8),
        FTimeWheel(value: _wheel, onChanged: _choose),
        if (duplicate) ...[
          const SizedBox(height: F.s8),
          GoldNote('الساعة دي على الكارت خلاص', key: const ValueKey('one-more-duplicate')),
        ],
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('one-more-add'),
          label: chosen == null ? 'اختار الساعة' : 'ضيف الساعة ${_time(chosen)}',
          onPressed: chosen == null || duplicate ? null : () => Navigator.of(context).pop(chosen),
        ),
      ],
    );
  }
}
