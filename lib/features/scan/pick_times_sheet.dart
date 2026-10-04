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
///
/// **زرار واحد «احفظ»** (طلب المدير، ٤ أكتوبر ٢٠٢٦): كان «ضيف الساعة» وبعدين
/// «تمام» — خطوتين لنفس النية، والراجل كان بيدوس «تمام» من غير «ضيف» فالساعة
/// تضيع. دلوقتي كل جرعة خانة، الشريحة أو البكرة بتكتب في الخانة المختارة،
/// و«احفظ» بياخد اللي اتختار.
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
  /// خانة لكل جرعة — null = لسه ما اتختارتش. العدد من الورقة لو قالته.
  late final List<MinuteOfDay?> _slots = () {
    final count = widget.facts.timesToPick ?? widget.facts.dosesPerDay ?? 1;
    final slots = <MinuteOfDay?>[...widget.initial];
    while (slots.length < count) {
      slots.add(null);
    }
    return slots;
  }();

  /// الخانة اللي الشرايح والبكرة بيكتبوا فيها.
  late int _sel = () {
    final empty = _slots.indexWhere((m) => m == null);
    return empty >= 0 ? empty : _slots.length - 1;
  }();

  String _time(MinuteOfDay m) => arabicTime(DateTime(2026, 1, 1, m.hour, m.minute));

  List<MinuteOfDay> get _picked {
    final out = {for (final m in _slots.whereType<MinuteOfDay>()) m.minutes: m}.values.toList()
      ..sort((a, b) => a.minutes.compareTo(b.minutes));
    return out;
  }

  /// باقي جرعات اليوم لو كمّل بالفاصل من أول ساعة — null = مفيش اقتراح.
  List<MinuteOfDay>? get _continuation {
    final step = widget.facts.stepHours;
    final n = widget.facts.dosesPerDay;
    final first = _slots.first;
    if (step == null || n == null || n < 2 || first == null) return null;
    if (_slots.skip(1).any((m) => m != null)) return null;
    return [for (var k = 1; k < n; k++) MinuteOfDay((first.minutes + k * step * 60) % 1440)];
  }

  void _set(MinuteOfDay m, {bool advance = false}) => setState(() {
        _slots[_sel] = m;
        if (advance) {
          final next = _slots.indexWhere((x) => x == null);
          if (next >= 0) _sel = next;
        }
      });

  void _continue(List<MinuteOfDay> more) => setState(() {
        while (_slots.length < more.length + 1) {
          _slots.add(null);
        }
        for (var k = 0; k < more.length; k++) {
          _slots[k + 1] = more[k];
        }
      });

  @override
  Widget build(BuildContext context) {
    final words = widget.facts.words;
    final more = _continuation;
    final many = _slots.length > 1;
    final current = _slots[_sel];
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
        if (many) ...[
          for (var i = 0; i < _slots.length; i++) _slotRow(i),
          const SizedBox(height: F.s4),
        ],
        if (more != null) ...[
          // اقتراح بدوسة — بعد ما هو اختار أول ساعة، ومش قبلها
          FSecondaryButton(
            key: const ValueKey('continue-interval'),
            label: 'كمّل كل ${hoursWord(widget.facts.stepHours!)} — ${more.map(_time).join(' و')}',
            onPressed: () => _continue(more),
          ),
          const SizedBox(height: F.gap),
        ],
        Text(
          _sel == 0 ? 'أول جرعة الساعة كام؟' : 'الجرعة ${arabicDigits('${_sel + 1}')} الساعة كام؟',
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
        ),
        const SizedBox(height: F.s8),
        QuickTimeChips(selected: current, onPick: (m) => _set(m, advance: true)),
        const SizedBox(height: F.s8),
        FTimeWheel(
          key: ValueKey('pick-wheel-$_sel'),
          value: current ?? PickTimesBody.rest,
          onChanged: (m) => _set(m),
        ),
        if (!many && current != null)
          Text(
            'الساعة ${_time(current)}',
            key: ValueKey('picked-${current.minutes}'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
          ),
        SizedBox(
          height: F.minTapTarget,
          child: TextButton(
            key: const ValueKey('one-more-slot'),
            onPressed: () => setState(() {
              _slots.add(null);
              _sel = _slots.length - 1;
            }),
            child: Text('ساعة كمان', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
          ),
        ),
        const SizedBox(height: F.s8),
        FPrimaryButton(
          key: const ValueKey('times-done'),
          label: 'احفظ',
          onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop(_picked),
        ),
      ],
    );
  }

  Widget _slotRow(int i) {
    final m = _slots[i];
    final selected = i == _sel;
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s8),
      child: Material(
        color: F.railGround,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(F.radiusCard),
          // الخانة اللي بتكتب فيها دلوقتي — «الحالة اللي إنت عليها» = دهبي
          side: BorderSide(color: selected ? F.gold : F.railGround, width: 2),
        ),
        child: InkWell(
          key: ValueKey('slot-$i'),
          borderRadius: BorderRadius.circular(F.radiusCard),
          onTap: () => setState(() => _sel = i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: F.minTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: F.s12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'الجرعة ${arabicDigits('${i + 1}')} — ${m == null ? 'اختار الساعة' : _time(m)}',
                      key: m == null ? null : ValueKey('picked-${m.minutes}'),
                      style: TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: m == null ? FontWeight.w500 : FontWeight.w700,
                        color: m == null ? F.mutedDark : F.ink,
                      ),
                    ),
                  ),
                  if (m != null)
                    SizedBox(
                      height: F.minTapTarget,
                      child: TextButton(
                        key: ValueKey('slot-clear-$i'),
                        onPressed: () => setState(() {
                          _slots[i] = null;
                          _sel = i;
                        }),
                        child: Text('شيل',
                            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
