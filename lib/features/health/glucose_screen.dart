import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/readings_repository.dart';
import '../../domain/health/usual_range.dart';
import 'usual_words.dart';

/// اللي بيتقال عن قياس: المعتاد ليه ولا لسه مش كفاية. null range = مش كفاية.
({UsualRange? range, UsualComparison? comparison}) judgeReading(List<ReadingRow> newestFirst, ReadingRow reading) {
  final range = usualRangeOf(
    ReadingsRepository.previousInContext(newestFirst, reading),
    minimum: minGlucoseReadings,
  );
  return (range: range, comparison: range == null ? null : compareToUsual(reading.valueMgDl, range));
}

/// «قياس السكر» (المخطط ١٤) — **سكر الدم بس**، بالكتابة.
///
/// آخر قياس بالرقم، وتحته: المعتاد ليه **هو** (من قياساته في نفس السياق) أو
/// «لسه ما عندناش قياسات كفاية نعرف المعتاد ليك». مفيش «المستهدف» ولا «أعلى
/// من المستهدف» ولا أحمر زي التصميم: ده نطاق من كتاب متنكر في واجهة.
///
/// الإدخال بالصوت مش مبني (مفيش استقبال صوت) — مكتوب في المؤجَّل.
class GlucoseScreen extends StatefulWidget {
  const GlucoseScreen({this.now, super.key});

  /// للاختبارات.
  final DateTime Function()? now;

  @override
  State<GlucoseScreen> createState() => _GlucoseScreenState();
}

class _GlucoseScreenState extends State<GlucoseScreen> {
  Stream<List<ReadingRow>>? _readings;
  final _value = TextEditingController();
  GlucoseContext? _context;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    _readings ??= ReadingsRepository(services.db).watchRecent(services.patientId);
  }

  @override
  void initState() {
    super.initState();
    _value.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  int? get _parsed {
    final western = _value.text.trim().replaceAllMapped(
          RegExp('[٠-٩]'),
          (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x660 + 0x30),
        );
    return int.tryParse(western);
  }

  Future<void> _save() async {
    final v = _parsed, c = _context;
    if (v == null || c == null || !ReadingsRepository.isReadable(v)) return;
    setState(() => _saving = true);
    final services = AppScope.of(context);
    await ReadingsRepository(services.db).add(
      patientId: services.patientId,
      valueMgDl: v,
      context: c,
      measuredAt: widget.now?.call() ?? DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _value.clear();
      _context = null;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final v = _parsed;
    final outOfRange = v != null && !ReadingsRepository.isReadable(v);
    final canSave = !_saving && v != null && !outOfRange && _context != null;

    return Scaffold(
      appBar: AppBar(title: const Text('قياس السكر')),
      body: StreamBuilder<List<ReadingRow>>(
        stream: _readings,
        builder: (context, snap) {
          final rows = snap.data ?? const <ReadingRow>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
            children: [
              const Text(
                'سكر الدم بس — بالملّيجرام/ديسيلتر زي ما الجهاز بيقول.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
              ),
              const SizedBox(height: F.s12),
              if (rows.isNotEmpty) ...[
                _LatestCard(rows: rows),
                const SizedBox(height: F.gap),
              ],
              FCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHead('سجّل قراءة'),
                    const SizedBox(height: F.s8),
                    TextField(
                      key: const ValueKey('glucose-value'),
                      controller: _value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩]'))],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: F.displayFamily,
                        fontSize: F.display3,
                        fontWeight: FontWeight.w700,
                        color: F.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'الرقم',
                        hintStyle: const TextStyle(fontSize: F.minBodySize, color: F.muted),
                        suffixText: 'ملّيجرام/ديسيلتر',
                        suffixStyle: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
                      ),
                    ),
                    if (outOfRange) ...[
                      const SizedBox(height: F.s6),
                      Text(
                        'الرقم ده برّه اللي أجهزة القياس بتقراه '
                        '(${arabicNumber(ReadingsRepository.minMgDl)}–${arabicNumber(ReadingsRepository.maxMgDl)}) — اتأكد منه.',
                        style: const TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5),
                      ),
                    ],
                    const SizedBox(height: F.s12),
                    const Text('كنت…', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                    const SizedBox(height: F.s6),
                    Row(
                      children: [
                        for (final c in GlucoseContext.values) ...[
                          Expanded(
                            child: AnchorChip(
                              key: ValueKey('glucose-${c.name}'),
                              label: c.label,
                              selected: _context == c,
                              onTap: () => setState(() => _context = c),
                            ),
                          ),
                          if (c != GlucoseContext.values.last) const SizedBox(width: F.s8),
                        ],
                      ],
                    ),
                    const SizedBox(height: F.gap),
                    FPrimaryButton(label: 'احفظ القراءة', onPressed: canSave ? _save : null),
                  ],
                ),
              ),
              const SizedBox(height: F.gap),
              if (snap.data == null)
                const SizedBox.shrink()
              else if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(F.gap),
                  decoration: BoxDecoration(color: F.ivoryPale, borderRadius: BorderRadius.circular(F.radiusCard)),
                  child: const Text(
                    'لسه مفيش قياسات. اكتب الرقم اللي الجهاز قاله، واختار كنت صايم ولا بعد الأكل.',
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                  ),
                )
              else ...[
                const SectionHead('آخر القياسات'),
                const SizedBox(height: F.s8),
                for (final r in rows.take(10))
                  Container(
                    constraints: const BoxConstraints(minHeight: F.minTapTarget),
                    padding: const EdgeInsets.symmetric(vertical: F.s6),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: F.lineSoft))),
                    child: Row(
                      children: [
                        Text(
                          arabicNumber(r.valueMgDl),
                          style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                        ),
                        const SizedBox(width: F.s8),
                        Text(r.context.label, style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                        const Spacer(),
                        Text(
                          '${arabicDate(r.measuredAt)} — ${arabicTime(r.measuredAt)}',
                          style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// آخر قياس: الرقم، سياقه ووقته، وسطر «المعتاد ليك» — أو إنه لسه مش كفاية.
class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.rows});

  final List<ReadingRow> rows;

  @override
  Widget build(BuildContext context) {
    final latest = rows.first;
    final judged = judgeReading(rows, latest);
    final outside = judged.comparison != null && judged.comparison is! WithinUsual;
    final sameContext = [for (final r in rows) if (r.context == latest.context) r].take(usualWindow).toList();

    return FCard(
      // ذهبي بس لو برّه المعتاد **ليه هو** — «ده محتاج انتباهك». مفيش أحمر.
      tone: outside ? FCardTone.attention : FCardTone.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('آخر قراءة', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                arabicNumber(latest.valueMgDl),
                key: const ValueKey('glucose-latest'),
                style: const TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.display2,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
              const SizedBox(width: F.s8),
              const Text('ملّيجرام/ديسيلتر', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
            ],
          ),
          Text(
            '${latest.context.label} — ${arabicDate(latest.measuredAt)} — ${arabicTime(latest.measuredAt)}',
            style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
          ),
          const SizedBox(height: F.s8),
          Text(
            judged.range == null ? notEnoughForUsual : comparisonText(judged.comparison!, judged.range!),
            key: const ValueKey('glucose-usual'),
            style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
          ),
          if (sameContext.length >= 2) ...[
            const SizedBox(height: F.s12),
            SizedBox(
              height: 90,
              width: double.infinity,
              child: CustomPaint(painter: _Line([for (final r in sameContext.reversed) r.valueMgDl])),
            ),
            Text(
              'آخر ${arabicNumber(sameContext.length)} قياسات وإنت ${latest.context.label}',
              style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
            ),
          ],
        ],
      ),
    );
  }
}

/// خط بسيط أخضر — مفيش خط «مستهدف» ولا نقطة حمرا.
class _Line extends CustomPainter {
  const _Line(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce((a, b) => a < b ? a : b).toDouble();
    final hi = values.reduce((a, b) => a > b ? a : b).toDouble();
    final span = (hi - lo) == 0 ? 1.0 : hi - lo;
    Offset at(int i) => Offset(
          size.width - (size.width - 12) * i / (values.length - 1) - 6, // RTL: الأقدم يمين
          size.height - 8 - (size.height - 16) * (values[i] - lo) / span,
        );
    final line = Paint()
      ..color = F.green
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = F.greenDeep;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(at(i), 4, dot);
    }
  }

  @override
  bool shouldRepaint(_Line old) => old.values != values;
}
