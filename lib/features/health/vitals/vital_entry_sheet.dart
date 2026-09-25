import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/f_sheet.dart';
import '../../../core/widgets/f_wheels.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/repositories/vitals_repository.dart';
import '../../../domain/health/vitals.dart';
import '../../../domain/scheduling/day_routine.dart' show MinuteOfDay;
import '../glucose_screen.dart';

/// **«سجّل قياس»** — ورقة واحدة لكل القياسات: الأنواع شرايح، والرقم من
/// الكيبورد (نفس السكر: رقم الجهاز بيتقرا وبيتكتب، مش بيتلف على عجلة).
/// الوقت «دلوقتي» وبيتغيّر: الأيام شرايح والساعة عجلة (قاعدة «كل ساعة على
/// عجلة»). السكر شريحة كمان — بتفتح شاشته زي ما هي.
///
/// بترجّع النوع اللي اتسجّل (null = قفل من غير حفظ).
Future<VitalKind?> showVitalEntrySheet(BuildContext context, {VitalKind? initial, DateTime? now}) async {
  final result = await FSheet.show<_VitalResult>(
    context,
    title: 'سجّل قياس',
    children: [_VitalEntryBody(initial: initial ?? VitalKind.bloodPressure, now: now ?? DateTime.now())],
  );
  if (result == null || !context.mounted) return null;
  if (result.glucose) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlucoseScreen()));
    return null;
  }
  final services = AppScope.of(context);
  await VitalsRepository(services.db).add(services.patientId, result.entry!, measuredAt: result.at!);
  return result.entry!.kind;
}

class _VitalResult {
  const _VitalResult.saved(VitalEntry this.entry, DateTime this.at) : glucose = false;
  const _VitalResult.glucose()
      : entry = null,
        at = null,
        glucose = true;

  final VitalEntry? entry;
  final DateTime? at;
  final bool glucose;
}

class _VitalEntryBody extends StatefulWidget {
  const _VitalEntryBody({required this.initial, required this.now});

  final VitalKind initial;
  final DateTime now;

  @override
  State<_VitalEntryBody> createState() => _VitalEntryBodyState();
}

class _VitalEntryBodyState extends State<_VitalEntryBody> {
  late VitalKind _kind = widget.initial;
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _pulse = TextEditingController();
  late DateTime _day = DateTime(widget.now.year, widget.now.month, widget.now.day);
  late MinuteOfDay _time = MinuteOfDay(widget.now.hour * 60 + widget.now.minute);
  bool _editTime = false;
  bool _tried = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _pulse.dispose();
    super.dispose();
  }

  VitalEntry? get _entry {
    final v = parseVitalNumber(_first.text);
    if (v == null) return null;
    if (_kind == VitalKind.bloodPressure) {
      final pulse = _pulse.text.trim().isEmpty ? null : parseVitalNumber(_pulse.text)?.round();
      return VitalEntry(kind: _kind, value: v, value2: parseVitalNumber(_second.text), pulse: pulse);
    }
    return VitalEntry(kind: _kind, value: v);
  }

  DateTime get _at => DateTime(_day.year, _day.month, _day.day, 0, _time.minutes);

  String? get _problem {
    final e = _entry;
    if (e == null) return null;
    if (_kind == VitalKind.bloodPressure && _pulse.text.trim().isNotEmpty && e.pulse == null) {
      return 'الرقم ده غريب — راجعه';
    }
    if (_at.isAfter(widget.now.add(const Duration(minutes: 1)))) return 'الوقت ده لسه ما جاش — راجعه';
    return vitalEntryProblem(e);
  }

  void _save() {
    setState(() => _tried = true);
    final e = _entry;
    if (e == null || _problem != null) return;
    Navigator.of(context).pop(_VitalResult.saved(e, _at));
  }

  Widget _field(TextEditingController c, String hint, {Key? key, TextInputAction action = TextInputAction.next}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: _kind.decimals),
        textInputAction: action,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩.,٫،]'))],
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: F.bigTimeSize * 0.8, fontWeight: FontWeight.w700, color: F.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: F.minTextSize, color: F.placeholder),
          filled: true,
          fillColor: F.fieldGround,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final problem = _tried || _entry != null ? _problem : null;
    final yesterday = DateTime(widget.now.year, widget.now.month, widget.now.day - 1);
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: F.s8,
          runSpacing: F.s8,
          children: [
            for (final k in VitalKind.values)
              AnchorChip(
                key: ValueKey('vital-kind-${k.name}'),
                label: k.label,
                selected: _kind == k,
                onTap: () => setState(() {
                  _kind = k;
                  _tried = false;
                }),
              ),
            AnchorChip(
              key: const ValueKey('vital-kind-glucose'),
              label: 'السكر',
              selected: false,
              onTap: () => Navigator.of(context).pop(const _VitalResult.glucose()),
            ),
          ],
        ),
        const SizedBox(height: F.gap),
        if (_kind == VitalKind.bloodPressure) ...[
          Row(
            children: [
              Expanded(child: _field(_first, 'الرقم الكبير', key: const ValueKey('vital-value'))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: F.s8),
                child: Text('/', style: TextStyle(fontSize: F.bigTimeSize * 0.8, color: F.mutedDark)),
              ),
              Expanded(child: _field(_second, 'الرقم الصغير', key: const ValueKey('vital-value2'))),
            ],
          ),
          const SizedBox(height: F.s8),
          _field(_pulse, 'النبض (لو الجهاز قاله)', key: const ValueKey('vital-pulse'), action: TextInputAction.done),
        ] else
          _field(_first, '${_kind.label} بـ${_kind.unit}', key: const ValueKey('vital-value'), action: TextInputAction.done),
        const SizedBox(height: F.s6),
        Text(_kind.unit, textAlign: TextAlign.center, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
        if (problem != null) ...[
          const SizedBox(height: F.s10),
          GoldNote(problem, key: const ValueKey('vital-problem')),
        ],
        const SizedBox(height: F.s12),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_day == today ? 'النهارده' : _day == yesterday ? 'امبارح' : arabicDate(_day)} — ${arabicTime(_at)}',
                key: const ValueKey('vital-when'),
                style: TextStyle(fontSize: F.minBodySize, color: F.ink),
              ),
            ),
            TextButton(
              key: const ValueKey('vital-edit-time'),
              onPressed: () => setState(() => _editTime = !_editTime),
              style: TextButton.styleFrom(minimumSize: const Size(0, F.minTapTarget)),
              child: Text(_editTime ? 'تمام' : 'غيّر الوقت',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.green)),
            ),
          ],
        ),
        if (_editTime) ...[
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              AnchorChip(label: 'النهارده', selected: _day == today, onTap: () => setState(() => _day = today)),
              AnchorChip(label: 'امبارح', selected: _day == yesterday, onTap: () => setState(() => _day = yesterday)),
              AnchorChip(
                label: _day != today && _day != yesterday ? arabicDate(_day) : 'يوم تاني',
                selected: _day != today && _day != yesterday,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(widget.now.year - 5),
                    lastDate: today,
                  );
                  if (picked != null) setState(() => _day = picked);
                },
              ),
            ],
          ),
          const SizedBox(height: F.s8),
          FTimeWheel(value: _time, onChanged: (t) => setState(() => _time = t)),
        ],
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('vital-save'),
          label: 'احفظ',
          onPressed: _entry == null ? null : _save,
        ),
      ],
    );
  }
}
