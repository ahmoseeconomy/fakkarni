import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ai/lab_reading.dart';
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/lab_results_repository.dart';
import '../../domain/health/usual_range.dart';
import '../scan/review_prescription_screen.dart' show ReviewResult;
import 'usual_words.dart';

/// سطر في المراجعة — قابل للتعديل بإيد إنسان.
class _EditableLine {
  _EditableLine.from(LabLine l)
      : name = l.test.value ?? '',
        value = l.value.value,
        unit = l.unit.value,
        unsure = l.blocksConfirm;

  String name;
  double? value;
  String? unit;

  /// لسه محتاج إنسان يبص عليه — بيقفل «تمام» لحد ما يتعدّل أو يتشال.
  bool unsure;

  bool get blocks => unsure || name.trim().isEmpty || value == null;
}

/// «قراءة التقرير» (المخطط ٨) — أخطر شاشة في التطبيق.
///
/// **(أ) الرقم والنطاق والفرق، ويقف.** مفيش نصيحة ولا تشخيص ولا «يُفضّل»
/// ولا «راجع دكتورك». الموديل نفسه متقيّد في الـsystem instruction، والشاشة
/// ما بتعرضش أي نص حر منه — اسم ورقم ووحدة بس.
///
/// **(ب) «المعتاد» معناه المعتاد ليه هو** — قيم نفس التحليل في تقاريره اللي
/// فاتت. أقل من [minLabValues] = «لسه ما عندناش قياسات كفاية نعرف المعتاد
/// ليك» والرقم من غير أي تعليم. **مفيش نطاق مرجعي للمعمل ولا «أعلى/مرتفع»
/// زي التصميم**: ده تشخيص متنكر في واجهة.
///
/// القاعدة ٤: ولا سطر بيتحفظ غير بعد «تمام، احفظه». «صوّر تاني» بنفس الوزن.
class LabReportScreen extends StatefulWidget {
  const LabReportScreen({required this.reading, this.image, this.today, super.key});

  final LabReading reading;
  final Uint8List? image;

  /// للاختبارات.
  final DateTime? today;

  @override
  State<LabReportScreen> createState() => _LabReportScreenState();
}

class _LabReportScreenState extends State<LabReportScreen> {
  late final List<_EditableLine> _lines = [for (final l in widget.reading.lines) _EditableLine.from(l)];
  final Map<String, List<PastLabValue>> _history = {};
  bool _busy = false;

  bool get _blocked => _lines.isEmpty || _lines.any((l) => l.blocks);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_history.isNotEmpty || _lines.isEmpty) return;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final services = AppScope.of(context);
    final repo = LabResultsRepository(services.db);
    for (final l in _lines) {
      final key = LabResultsRepository.normalize(l.name);
      if (key.isEmpty || _history.containsKey(key)) continue;
      final past = await repo.historyFor(services.patientId, l.name);
      if (!mounted) return;
      setState(() => _history[key] = past);
    }
  }

  Future<void> _edit(_EditableLine line) async {
    final result = await showDialog<({String name, double? value, String? unit})>(
      context: context,
      builder: (_) => _EditLineDialog(
        name: line.name,
        value: line.value == null ? '' : _plain(line.value!),
        unit: line.unit ?? '',
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      line
        ..name = result.name
        ..value = result.value
        ..unit = result.unit
        // إنسان بص عليه وكتب — مبقاش «مش متأكد»
        ..unsure = false;
    });
    _loadHistory();
  }

  Future<void> _confirm() async {
    if (_busy || _blocked) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final today = widget.today ?? DateTime.now();
    final reading = widget.reading;

    // الصورة: لو التخزين فشل التقرير بيتحفظ من غيرها — الأرقام هي اللي اتأكدت.
    String? path;
    final image = widget.image;
    if (image != null) {
      try {
        path = await services.attachments.save(image);
      } catch (error) {
        debugPrint('صورة التقرير ما اتحفظتش: $error');
      }
    }

    await LabResultsRepository(services.db).saveReport(
      patientId: services.patientId,
      happenedAt: reading.date.value != null && !reading.date.needsReview
          ? reading.date.value!
          : DateTime(today.year, today.month, today.day),
      place: reading.lab.needsReview ? null : reading.lab.value,
      attachmentPath: path,
      lines: [
        for (final l in _lines) ConfirmedLabLine(testName: l.name.trim(), value: l.value!, unit: l.unit),
      ],
    );
    if (mounted) navigator.pop(ReviewResult.confirmed);
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final reading = widget.reading;
    final meta = [
      if (!reading.lab.needsReview && reading.lab.value != null) reading.lab.value!,
      if (!reading.date.needsReview && reading.date.value != null) arabicDate(reading.date.value!),
    ].join(' — ');

    return Scaffold(
      appBar: AppBar(title: const Text('قراءة التقرير')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          Text(
            'النتايج زي ما اتقرت',
            style: TextStyle(fontFamily: F.displayFamily, fontSize: F.screenTitleSize, fontWeight: FontWeight.w700, color: F.ink),
          ),
          if (meta.isNotEmpty) Text(meta, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
          const SizedBox(height: F.s8),
          Text(
            'بنكتب الرقم، ونقارنه بتحاليلك إنت اللي فاتت — وبس.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.gap),
          if (_lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(F.gap),
              decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
              child: Text(
                'مفيش نتايج اتقرت من الصورة دي. صوّر تاني في نور أحسن، أو اكتب التحليل بإيدك من «الملف الصحي».',
                style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
              ),
            ),
          for (final (i, l) in _lines.indexed) ...[
            _ResultCard(
              key: ValueKey('lab-line-$i'),
              line: l,
              history: _history[LabResultsRepository.normalize(l.name)],
              onEdit: () => _edit(l),
              onRemove: () => setState(() => _lines.removeAt(i)),
            ),
            const SizedBox(height: F.s10),
          ],
          const SizedBox(height: F.s8),
          // نفس الوزن بالظبط — مليانين، نفس المقاس (القاعدة ٤).
          Row(
            children: [
              Expanded(
                child: _Equal(
                  label: 'صوّر تاني',
                  fill: F.ink,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(ReviewResult.retake),
                ),
              ),
              const SizedBox(width: F.s10),
              Expanded(
                child: _Equal(label: 'تمام، احفظه', fill: F.green, onPressed: _busy || _blocked ? null : _confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.line,
    required this.history,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

  final _EditableLine line;

  /// null = لسه بيتحمّل.
  final List<PastLabValue>? history;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final value = l.value;
    return FCard(
      // ذهبي = «راجعها» (القراءة مش متأكدة) — مش حكم على الرقم.
      tone: l.unsure ? FCardTone.attention : FCardTone.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (l.unsure)
            Padding(
              padding: EdgeInsets.only(bottom: F.s6),
              child: Text(
                'مش متأكد من دي — راجعها',
                style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.name.isEmpty ? 'اسم مش واضح' : l.name,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    fontFamily: F.monoFamily,
                    fontFamilyFallback: F.monoFallback,
                  ),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value == null ? 'الرقم مش واضح' : arabicDecimal(value),
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: value == null ? F.minBodySize : F.display3,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
              if (l.unit != null) ...[
                const SizedBox(width: F.s8),
                Text(l.unit!, textDirection: TextDirection.ltr, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
              ],
            ],
          ),
          if (value != null && history != null) ...[
            const SizedBox(height: F.s6),
            ..._usual(value, history!, l.unit),
          ],
          const SizedBox(height: F.s10),
          Row(
            children: [
              Expanded(child: FSecondaryButton(label: 'عدّل', onPressed: onEdit)),
              const SizedBox(width: F.s10),
              Expanded(child: FSecondaryButton(label: 'شيل السطر', onPressed: onRemove)),
            ],
          ),
        ],
      ),
    );
  }

  /// المعتاد ليه هو: من قيم نفس التحليل **بنفس الوحدة** في تقاريره اللي فاتت.
  static List<Widget> _usual(double value, List<PastLabValue> history, String? unit) {
    final style = TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5);
    String norm(String? u) => (u ?? '').trim().toLowerCase();
    final sameUnit = [for (final h in history) if (norm(h.unit) == norm(unit)) h];
    if (history.isNotEmpty && sameUnit.isEmpty) {
      return [Text('الوحدة مختلفة عن المرات اللي فاتت — مش هنقارن', style: style)];
    }
    final range = usualRangeOf([for (final h in sameUnit) h.value], minimum: minLabValues);
    if (range == null) return [Text(notEnoughForUsual, key: ValueKey('lab-not-enough'), style: style)];
    final last = sameUnit.first;
    return [
      Text(comparisonText(compareToUsual(value, range), range), style: style),
      Text(
        'آخر مرة كان ${arabicDecimal(last.value)} في ${arabicDate(last.at)}',
        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
      ),
    ];
  }
}

class _Equal extends StatelessWidget {
  const _Equal({required this.label, required this.fill, required this.onPressed});

  final String label;
  final Color fill;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.primaryButtonHeight,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: fill,
            foregroundColor: F.onDark,
            disabledBackgroundColor: F.railGround,
            disabledForegroundColor: F.mutedDark,
            textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
          ),
          child: Text(label, maxLines: 1),
        ),
      );
}

/// «عدّل السطر ده» — الدايالوج هو صاحب الـcontrollers، فبيتقفلوا معاه بعد
/// ما حركة القفل تخلص (مش وهي لسه بترسم).
class _EditLineDialog extends StatefulWidget {
  const _EditLineDialog({required this.name, required this.value, required this.unit});

  final String name, value, unit;

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _value = TextEditingController(text: widget.value);
  late final _unit = TextEditingController(text: widget.unit);

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _done() {
    final western = _value.text
        .trim()
        .replaceAllMapped(RegExp('[٠-٩]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x660 + 0x30))
        .replaceAll('٫', '.');
    final unit = _unit.text.trim();
    Navigator.of(context).pop((name: _name.text.trim(), value: double.tryParse(western), unit: unit.isEmpty ? null : unit));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: const Text('عدّل السطر ده', style: TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('edit-test'),
              controller: _name,
              style: const TextStyle(fontSize: F.minBodySize),
              decoration: const InputDecoration(labelText: 'اسم التحليل زي ما هو في الورقة'),
            ),
            TextField(
              key: const ValueKey('edit-value'),
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: F.minBodySize),
              decoration: const InputDecoration(labelText: 'الرقم'),
            ),
            TextField(
              key: const ValueKey('edit-unit'),
              controller: _unit,
              style: const TextStyle(fontSize: F.minBodySize),
              decoration: const InputDecoration(labelText: 'الوحدة'),
            ),
          ],
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [FPrimaryButton(key: const ValueKey('edit-save'), label: 'تمام', onPressed: _done)],
          ),
        ],
      );
}
