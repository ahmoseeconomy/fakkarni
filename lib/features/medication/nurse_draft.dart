import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/care/medication_change.dart';
import '../../domain/scheduling/minute_of_day.dart';
import '../../domain/scheduling/dose_schedule.dart';
import 'add_medication_screen.dart';
import 'medication_draft.dart';

/// فورم «ضيف دوا» بتاع الأب في وضع المسوّدة — للممرض (المرحلة ب).
///
/// عايش هنا مش في `features/care/` عن قصد: جانب الابن **ما بيستوردش
/// الجدولة** (حارس `no_scheduling_imports_test`). الممرض بيختار ساعات
/// والمسوّدة بتشيلها زي ما هي، وموبايل المريض هو اللي بيكتبها.
Future<MedicationDraft?> draftMedicationAsNurse(BuildContext context, {DateTime? today}) =>
    Navigator.of(context).push<MedicationDraft>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(today: today, draft: true),
      ),
    );

/// «غيّر المواعيد»: كل جرعة على بكرة الساعة (نفس الفورم اللي المريض بيعرفه)،
/// «ضيف جرعة» و«شيل» — والحفظ طلب `timings` بالقايمة كلها.
Future<MedicationChangePayload?> pickTimingsAsNurse(BuildContext context, {required String name, required List<int> minutes}) async {
  final result = await FSheet.show<List<FixedTiming>>(
    context,
    title: 'مواعيد $name',
    children: [_TimingsBody(initial: minutes.isEmpty ? const [540] : minutes)],
  );
  if (result == null || result.isEmpty) return null;
  return MedicationChangePayload(timings: result);
}

class _TimingsBody extends StatefulWidget {
  const _TimingsBody({required this.initial});
  final List<int> initial;

  @override
  State<_TimingsBody> createState() => _TimingsBodyState();
}

class _TimingsBodyState extends State<_TimingsBody> {
  late final List<int> _minutes = List.of(widget.initial);
  int _editing = 0;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, m) in _minutes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: F.s6),
              child: Row(
                children: [
                  Expanded(
                    child: AnchorChip(
                      key: ValueKey('nurse-timing-$i'),
                      label: 'الجرعة ${arabicNumber(i + 1)} — ${arabicTime(DateTime(2000, 1, 1, 0, m))}',
                      selected: _editing == i,
                      onTap: () => setState(() => _editing = i),
                    ),
                  ),
                  if (_minutes.length > 1) ...[
                    const SizedBox(width: F.s8),
                    FSecondaryButton(
                      key: ValueKey('nurse-timing-remove-$i'),
                      label: 'شيل',
                      onPressed: () => setState(() {
                        _minutes.removeAt(i);
                        if (_editing >= _minutes.length) _editing = _minutes.length - 1;
                      }),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: F.s8),
          FTimeWheel(
            key: ValueKey('nurse-timing-wheel-$_editing'),
            value: MinuteOfDay(_minutes[_editing]),
            onChanged: (v) => setState(() => _minutes[_editing] = v.minutes),
          ),
          const SizedBox(height: F.s8),
          FSecondaryButton(
            key: const ValueKey('nurse-timing-add'),
            label: 'ضيف جرعة',
            onPressed: () => setState(() {
              _minutes.add((_minutes.last + 6 * 60) % 1440);
              _editing = _minutes.length - 1;
            }),
          ),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('nurse-timings-save'),
            label: 'ابعتها لموبايله',
            onPressed: () => Navigator.of(context).pop([for (final m in _minutes) FixedTiming(MinuteOfDay(m))]),
          ),
        ],
      );
}

