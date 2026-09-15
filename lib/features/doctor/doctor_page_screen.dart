import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm, innerJoin, BooleanExpressionOperators;
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/medication_repository.dart';
import '../../data/repositories/visit_questions_repository.dart';
import '../../domain/health/glucose_summary.dart';
import '../health/usual_words.dart' show GlucoseContextWords, arabicDecimal;

/// «ملخص زيارة الطبيب» (المخطط ١٦) — شاشة واحدة تتفتح قدام الدكتور.
///
/// **نفس قاعدة D3.6 بالحرف: أرقام ووقائع وبس.** مفيش ملخص ذكي، مفيش
/// استنتاج، مفيش «يبدو أن». مفيش سهم «↑ عن الشهر السابق» ولا أسهم التحاليل
/// الحمرا زي التصميم، ومفيش سبب إيقاف دوا (مش متخزّن). اختبار الكلمات
/// الممنوعة بيقرا الشاشة دي كمان.
///
/// أسئلة العيلة بتتكتب هنا على الموبايل ده. الابن يضيف من موبايله = مؤجَّل.
class DoctorPageScreen extends StatefulWidget {
  const DoctorPageScreen({this.now, super.key});

  /// للاختبارات.
  final DateTime Function()? now;

  @override
  State<DoctorPageScreen> createState() => _DoctorPageScreenState();
}

class _LabLine {
  const _LabLine(this.name, this.value, this.unit, this.at, this.previous);
  final String name;
  final double value;
  final String? unit;
  final DateTime at;
  final (double, DateTime)? previous;
}

class _DoctorPageScreenState extends State<DoctorPageScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  List<MedicationSummary> _meds = const [];
  List<ReadingRow> _readings = const [];
  List<VisitQuestionRow> _questions = const [];
  List<_LabLine> _labs = const [];
  RecordRow? _nextBooking;
  final _newQuestion = TextEditingController();

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty) return;
    final s = AppScope.of(context);
    final db = s.db;
    _subs
      ..add(s.medications.watchActiveSummaries(s.patientId).listen((v) => _set(() => _meds = v)))
      ..add((db.select(db.readings)
            ..where((t) => t.patientId.equals(s.patientId))
            ..orderBy([(t) => OrderingTerm.desc(t.measuredAt)]))
          .watch()
          .listen((v) => _set(() => _readings = v)))
      ..add(VisitQuestionsRepository(db).watch(s.patientId).listen((v) => _set(() => _questions = v)))
      ..add((db.select(db.records)..where((t) => t.patientId.equals(s.patientId) & t.deletedAt.isNull()))
          .watch()
          .listen((rows) {
        final upcoming = [
          for (final r in rows)
            if (r.kind == RecordKind.booking && !r.happenedAt.isBefore(DateTime(_now.year, _now.month, _now.day))) r,
        ]..sort((a, b) => a.happenedAt.compareTo(b.happenedAt));
        _set(() => _nextBooking = upcoming.isEmpty ? null : upcoming.first);
        _loadLabs();
      }));
    _newQuestion.addListener(() => setState(() {}));
  }

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  Future<void> _loadLabs() async {
    final s = AppScope.of(context);
    final db = s.db;
    final query = db.select(db.labResults).join([
      innerJoin(db.records, db.records.id.equalsExp(db.labResults.recordId)),
    ])
      ..where(db.records.patientId.equals(s.patientId) & db.records.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(db.records.happenedAt), OrderingTerm.desc(db.labResults.id)]);
    final byTest = <String, List<(LabResultRow, DateTime)>>{};
    for (final row in await query.get()) {
      final r = row.readTable(db.labResults);
      byTest.putIfAbsent(r.testName.trim().toLowerCase(), () => []).add((r, row.readTable(db.records).happenedAt));
    }
    final lines = [
      for (final entries in byTest.values)
        _LabLine(
          entries.first.$1.testName,
          entries.first.$1.value,
          entries.first.$1.unit,
          entries.first.$2,
          entries.length > 1 ? (entries[1].$1.value, entries[1].$2) : null,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    _set(() => _labs = lines.take(8).toList());
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _newQuestion.dispose();
    super.dispose();
  }

  Future<void> _addQuestion() async {
    final s = AppScope.of(context);
    if (_newQuestion.text.trim().isEmpty) return;
    await VisitQuestionsRepository(s.db).add(s.patientId, _newQuestion.text, now: _now);
    _newQuestion.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final now = _now;
    final since = DateTime(now.year, now.month, now.day - 30);
    final recent = [for (final r in _readings) if (!r.measuredAt.isBefore(since)) r];
    const body = TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5);
    const sub = TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4);

    return Scaffold(
      appBar: AppBar(title: const Text('ملخص زيارة الطبيب')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          if (_nextBooking case final b?)
            Text(
              'الميعاد الجاي: ${[b.title, ?b.doctor].join(' · ')} — ${arabicDate(b.happenedAt)}',
              key: const ValueKey('next-booking'),
              style: sub,
            ),
          const SizedBox(height: F.s10),
          _Section(
            title: 'الأدوية الحالية',
            children: _meds.isEmpty
                ? const [Text('مفيش أدوية متسجّلة', style: sub)]
                : [
                    for (final m in _meds)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: F.s4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.medication.name,
                              textDirection: nameDirection(m.medication.name),
                              style: body.copyWith(fontWeight: FontWeight.w700, fontFamily: F.monoFamily, fontFamilyFallback: F.monoFallback),
                            ),
                            Text(
                              [
                                if (m.medication.amountLabel != null) m.medication.amountLabel!,
                                for (final sc in m.schedules) sc.ruleLabel,
                              ].join(' · '),
                              style: sub,
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
          _Section(
            title: 'القياسات · آخر ${arabicNumber(30)} يوم',
            children: [
              if (recent.isEmpty) const Text('مفيش قياسات سكر في آخر ٣٠ يوم', style: sub),
              for (final c in GlucoseContext.values)
                if (GlucoseStats.of([for (final r in recent) if (r.context == c) r.valueMgDl]) case final st?)
                  Container(
                    margin: const EdgeInsets.only(bottom: F.s8),
                    padding: const EdgeInsets.all(F.s12),
                    decoration: BoxDecoration(color: F.ivoryWarm, borderRadius: BorderRadius.circular(F.radiusCard)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('سكر ${c.label} · ${arabicNumber(st.count)} قياس', style: body.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          'متوسط ${arabicNumber(st.average)} · أقل ${arabicNumber(st.lowest)} · أعلى ${arabicNumber(st.highest)} ملّيجرام/ديسيلتر',
                          style: body,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
          _Section(
            title: 'التحاليل الأخيرة',
            children: _labs.isEmpty
                ? const [Text('مفيش تحاليل متسجّلة', style: sub)]
                : [
                    for (final l in _labs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: F.s4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${l.name} ${arabicDecimal(l.value)}${l.unit == null ? '' : ' ${l.unit}'}',
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.right,
                              style: body.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              [
                                arabicDate(l.at),
                                if (l.previous case (final v, final at)) 'كان ${arabicDecimal(v)} في ${arabicDate(at)}',
                              ].join(' · '),
                              style: sub,
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
          _Section(
            title: 'أسئلة العيلة',
            children: [
              if (_questions.isEmpty)
                const Text('لسه مفيش أسئلة. اكتب اللي عايزين تسألوا الدكتور فيه عشان ما يتنسيش.', style: sub),
              for (final q in _questions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: F.s4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          q.body,
                          style: body.copyWith(
                            decoration: q.asked ? TextDecoration.lineThrough : null,
                            color: q.asked ? F.mutedDark : F.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: F.s8),
                      SizedBox(
                        height: F.minTapTarget,
                        child: OutlinedButton(
                          key: ValueKey('question-asked-${q.id}'),
                          onPressed: () => VisitQuestionsRepository(s.db).setAsked(q.id, !q.asked),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, F.minTapTarget),
                            foregroundColor: F.ink,
                            side: const BorderSide(color: F.line, width: 1.5),
                            textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
                          ),
                          child: Text(q.asked ? 'اتسأل ✓' : 'اتسأل؟'),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: F.s8),
              TextField(
                key: const ValueKey('question-field'),
                controller: _newQuestion,
                style: const TextStyle(fontSize: F.minBodySize),
                decoration: InputDecoration(
                  hintText: 'سؤال للدكتور',
                  hintStyle: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
                ),
              ),
              const SizedBox(height: F.s8),
              FSecondaryButton(
                label: 'ضيف السؤال',
                onPressed: _newQuestion.text.trim().isEmpty ? null : _addQuestion,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s12),
        child: FCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: F.sectionHeadSize, fontWeight: FontWeight.w700, color: F.green)),
              const SizedBox(height: F.s8),
              ...children,
            ],
          ),
        ),
      );
}
