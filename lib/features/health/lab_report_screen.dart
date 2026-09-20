import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ai/lab_reading.dart';
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/lab_results_repository.dart';
import '../../domain/health/lab_range.dart';
import '../../domain/health/usual_range.dart';
import '../scan/review_prescription_screen.dart' show ReviewResult;
import 'lab_flag.dart';
import 'usual_words.dart';

/// سطر في المراجعة — قابل للتعديل بإيد إنسان.
class _EditableLine {
  _EditableLine.from(LabLine l)
    : name = l.test.value ?? '',
      value = l.value.value,
      unit = l.unit.value,
      range = l.range,
      unsure = l.blocksConfirm;

  String name;
  double? value;
  String? unit;

  /// نطاق الورقة زي ما اتقرا — null لو الورقة ما طبعتش نطاق. الإنسان يقدر
  /// يعدّله أو يشيله، وعمرنا ما بنحطّ واحد من عندنا.
  LabRange? range;

  /// العلامة — حساب على رقمين مطبوعين، مش حكم.
  LabFlag get flag => value == null ? const NoPrintedRange() : labFlagFor(value!, range);

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
/// ليك» والرقم من غير أي تعليم.
///
/// **(ج) نطاق الورقة بيتعرض والخارج عنه بياخد علامة — والنطاق من الورقة
/// وبس.** مفيش في التطبيق كله جدول قيم طبيعية، ومفيش سطر بيقول يعني إيه:
/// رقمين مطبوعين بيتقارنوا، والكلمة بتقول فوق/تحت/قريب من الحد ولا حاجة
/// غيرها ([LabFlagBadge]). سطر الورقة ما فيهوش نطاق بيتعرض رقم عادي
/// وبنقول إن الورقة مفيهاش نطاق.
///
/// القاعدة ٤: ولا سطر بيتحفظ غير بعد «تمام، احفظه». «صوّر تاني» بنفس الوزن.
class LabReportScreen extends StatefulWidget {
  const LabReportScreen({required this.reading, this.image, this.today, this.onSaved, super.key});

  final LabReading reading;
  final Uint8List? image;

  /// بيتندَه بالـid بتاع السجل اللي اتكتب، بعد «تمام، احفظه» بالظبط.
  /// بيه «تابع تحليل» بتبدأ من نفس التقرير في نفس الخطوة.
  final void Function(int recordId)? onSaved;

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
    final result = await showDialog<_EditedLine>(
      context: context,
      builder: (_) => _EditLineDialog(
        name: line.name,
        value: line.value == null ? '' : _plain(line.value!),
        unit: line.unit ?? '',
        range: line.range,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      line
        ..name = result.name
        ..value = result.value
        ..unit = result.unit
        // النطاق زي ما إنسان كتبه من الورقة — وفاضي معناه الورقة مفيهاش.
        ..range = result.range
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

    final recordId = await LabResultsRepository(services.db).saveReport(
      patientId: services.patientId,
      happenedAt: reading.date.value != null && !reading.date.needsReview
          ? reading.date.value!
          : DateTime(today.year, today.month, today.day),
      place: reading.lab.needsReview ? null : reading.lab.value,
      attachmentPath: path,
      lines: [
        for (final l in _lines)
          ConfirmedLabLine(testName: l.name.trim(), value: l.value!, unit: l.unit, range: l.range),
      ],
    );
    widget.onSaved?.call(recordId);
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
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.screenTitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
            ),
          const SizedBox(height: F.s8),
          Text(
            'بنكتب الرقم، ونحطّ جنبه نطاق الورقة زي ما هو، ونقارنه بتحاليلك إنت اللي فاتت — وبس.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.gap),
          if (_lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(F.gap),
              decoration: BoxDecoration(
                color: F.railGround,
                borderRadius: BorderRadius.circular(F.radiusCard),
              ),
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
          if (_lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: F.s4, bottom: F.s8),
              child: Text(
                labRangeFooter,
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
            ),
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
                child: _Equal(
                  label: 'تمام، احفظه',
                  fill: F.green,
                  onPressed: _busy || _blocked ? null : _confirm,
                ),
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
                Text(
                  l.unit!,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                ),
              ],
            ],
          ),
          const SizedBox(height: F.s6),
          // نطاق الورقة والعلامة — قبل «المعتاد ليك»، لأن ده اللي على
          // الورقة اللي في إيده دلوقتي.
          ..._printedRange(l),
          if (value != null && history != null) ...[
            const SizedBox(height: F.s6),
            ..._usual(value, history!, l.unit),
          ],
          const SizedBox(height: F.s10),
          Row(
            children: [
              Expanded(
                child: FSecondaryButton(label: 'عدّل', onPressed: onEdit),
              ),
              const SizedBox(width: F.s10),
              Expanded(
                child: FSecondaryButton(label: 'شيل السطر', onPressed: onRemove),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// نطاق الورقة زي ما هو، والعلامة جنبه.
  ///
  /// الورقة ما طبعتش نطاق؟ بنقول كده بصراحة ([labNoRangeText]) وما بنعلّمش
  /// — ومش بنجيب نطاق من عندنا عشان نملا الفراغ.
  static List<Widget> _printedRange(_EditableLine l) {
    final style = TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5);
    final text = labRangeText(l.range);
    if (text == null) {
      return [Text(labNoRangeText, key: const ValueKey('lab-no-range'), style: style)];
    }
    final flag = l.flag;
    return [
      Row(
        children: [
          Expanded(child: Text(text, style: style)),
          if (labFlagWord(flag) != null) ...[const SizedBox(width: F.s8), LabFlagBadge(flag)],
        ],
      ),
    ];
  }

  /// المعتاد ليه هو: من قيم نفس التحليل **بنفس الوحدة** في تقاريره اللي فاتت.
  static List<Widget> _usual(double value, List<PastLabValue> history, String? unit) {
    final style = TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5);
    String norm(String? u) => (u ?? '').trim().toLowerCase();
    final sameUnit = [
      for (final h in history)
        if (norm(h.unit) == norm(unit)) h,
    ];
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

/// اللي الدايالوج بيرجّعه — نفس السطر بعد ما إنسان كتبه.
typedef _EditedLine = ({String name, double? value, String? unit, LabRange? range});

/// «عدّل السطر ده» — الدايالوج هو صاحب الـcontrollers، فبيتقفلوا معاه بعد
/// ما حركة القفل تخلص (مش وهي لسه بترسم).
///
/// حقول النطاق موجودة عشان اللي على الورقة يتصلّح لو القراءة غلطت — **مش**
/// عشان حد يحطّ نطاق من دماغه. سايبهم فاضيين = الورقة مفيهاش نطاق، والسطر
/// بيتعرض رقم من غير علامة.
class _EditLineDialog extends StatefulWidget {
  const _EditLineDialog({required this.name, required this.value, required this.unit, this.range});

  final String name, value, unit;
  final LabRange? range;

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _value = TextEditingController(text: widget.value);
  late final _unit = TextEditingController(text: widget.unit);
  late final _low = TextEditingController(text: _plainOrEmpty(widget.range?.low));
  late final _high = TextEditingController(text: _plainOrEmpty(widget.range?.high));
  late final _text = TextEditingController(text: widget.range?.text ?? '');

  static String _plainOrEmpty(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _unit.dispose();
    _low.dispose();
    _high.dispose();
    _text.dispose();
    super.dispose();
  }

  /// أرقام عربي بتتقرا زي الغربي — ده اللي على كيبورد الموبايل.
  static double? _number(String raw) {
    final western = raw
        .trim()
        .replaceAllMapped(
          RegExp('[٠-٩]'),
          (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x660 + 0x30),
        )
        .replaceAll('٫', '.');
    return double.tryParse(western);
  }

  void _done() {
    final unit = _unit.text.trim();
    final text = _text.text.trim();
    final range = LabRange(
      low: _number(_low.text),
      high: _number(_high.text),
      text: text.isEmpty ? null : text,
    );
    Navigator.of(context).pop((
      name: _name.text.trim(),
      value: _number(_value.text),
      unit: unit.isEmpty ? null : unit,
      // فاضي خالص = الورقة مفيهاش نطاق. ما بنحوّلهاش لحاجة تانية.
      range: range.isEmpty ? null : range,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: F.dialogGround,
    title: const Text(
      'عدّل السطر ده',
      style: TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
    ),
    content: SingleChildScrollView(
      child: Column(
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
          const SizedBox(height: F.s6),
          Text(
            'النطاق زي ما هو مكتوب على الورقة — سيبه فاضي لو الورقة مفيهاش نطاق',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('edit-ref-from'),
                  controller: _low,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: F.minBodySize),
                  decoration: const InputDecoration(labelText: 'من'),
                ),
              ),
              const SizedBox(width: F.s10),
              Expanded(
                child: TextField(
                  key: const ValueKey('edit-ref-to'),
                  controller: _high,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: F.minBodySize),
                  decoration: const InputDecoration(labelText: 'لحد'),
                ),
              ),
            ],
          ),
          TextField(
            key: const ValueKey('edit-ref-text'),
            controller: _text,
            style: const TextStyle(fontSize: F.minBodySize),
            decoration: const InputDecoration(labelText: 'أو نطاق مكتوب بالحروف — زي Negative'),
          ),
        ],
      ),
    ),
    actions: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [FPrimaryButton(key: const ValueKey('edit-save'), label: 'تمام', onPressed: _done)],
      ),
    ],
  );
}
