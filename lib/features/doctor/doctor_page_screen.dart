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
import '../../data/repositories/lab_results_repository.dart' show rangeOfRow;
import '../../data/repositories/medication_repository.dart';
import '../../data/repositories/visit_questions_repository.dart';
import '../../domain/health/glucose_summary.dart';
import '../../domain/health/lab_range.dart';
import '../health/lab_flag.dart';
import '../health/usual_words.dart'
    show GlucoseContextWords, arabicDecimal, labFlagWord, labNoRangeText, labRangeText;

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

/// زيارة أو روشتة زي ما هي متسجّلة: مين كتبها، فين، وتاريخ الورقة.
class _Visit {
  const _Visit(this.title, this.place, this.at);
  final String title;
  final String? place;
  final DateTime at;
}

class _LabLine {
  const _LabLine(this.name, this.value, this.unit, this.at, this.previous, this.range);
  final String name;
  final double value;
  final String? unit;
  final DateTime at;
  final (double, DateTime)? previous;

  /// نطاق الورقة اللي الرقم ده اتقرا منها — null لو الورقة ما طبعتش نطاق.
  final LabRange? range;

  LabFlag get flag => labFlagFor(value, range);
}

class _DoctorPageScreenState extends State<DoctorPageScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  List<MedicationSummary> _meds = const [];
  List<ReadingRow> _readings = const [];
  List<VisitQuestionRow> _questions = const [];
  List<_LabLine> _labs = const [];

  /// الزيارات والروشتات مجمّعة باسم الدكتور، الأحدث الأول — واللي مكتوبش
  /// عليها دكتور في الآخر تحت اسمها الصريح، مش مخلوطة مع حد.
  List<(String?, List<_Visit>)> _byDoctor = const [];
  RecordRow? _nextBooking;

  /// سقف: الشاشة دي بتتفتح قدام الدكتور وهو واقف — مش أرشيف.
  static const _maxVisits = 8;
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
        _set(() {
          _nextBooking = upcoming.isEmpty ? null : upcoming.first;
          _byDoctor = _groupByDoctor(rows);
        });
        _loadLabs();
      }));
    _newQuestion.addListener(() => setState(() {}));
  }

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  /// **الملخص من غير اسم الدكتور مش ملخص زيارة.** الصف بقى شايل الدكتور
  /// والعيادة وتاريخ الورقة من يوم ما شاشة المراجعة بقت بتقراهم، والشاشة
  /// دي كانت بتتجاهل التلاتة.
  ///
  /// بيتجمّع بالاسم **زي ما اتكتب** بعد تنضيف المسافات، والمقارنة بتتعمل
  /// على نسخة صغيرة الحروف عشان «د. هشام» و«د. هشام » ما يبقوش اتنين —
  /// من غير ما نحاول نخمّن إن «هشام» و«د. هشام» نفس الراجل؛ ده تخمين على
  /// بني آدمين، والغلط فيه بيلزّق زيارة بدكتور ما شافهاش.
  static List<(String?, List<_Visit>)> _groupByDoctor(List<RecordRow> rows) {
    const kinds = {RecordKind.visit, RecordKind.prescription};
    final wanted = [for (final r in rows) if (kinds.contains(r.kind)) r]
      ..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));
    final groups = <String?, List<_Visit>>{};
    final shown = <String?, String>{};
    for (final r in wanted.take(_maxVisits)) {
      final name = r.doctor?.trim();
      final key = (name == null || name.isEmpty) ? null : name.toLowerCase();
      shown.putIfAbsent(key, () => name ?? '');
      groups.putIfAbsent(key, () => []).add(_Visit(r.title, r.place, r.happenedAt));
    }
    return [
      for (final e in groups.entries)
        if (e.key != null) (shown[e.key], e.value),
      if (groups[null] case final unnamed?) (null, unnamed),
    ];
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
          // نطاق **الورقة بتاعة القراية دي** — مش بتاع القراية اللي قبلها.
          // كل ورقة بنطاقها، والمعمل ممكن يكون غيّره بين التقريرين.
          rangeOfRow(entries.first.$1),
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
    final body = TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5);
    final sub = TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4);

    return Scaffold(
      appBar: AppBar(title: const Text('ملخص زيارة الطبيب')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          if (_nextBooking case final b?)
            Text(
              'الميعاد الجاي: ${[b.title, ?b.doctor].join(' — ')} — ${arabicDate(b.happenedAt)}',
              key: const ValueKey('next-booking'),
              style: sub,
            ),
          const SizedBox(height: F.s10),
          _Section(
            title: 'الأدوية الحالية',
            children: _meds.isEmpty
                ? [Text('مفيش أدوية متسجّلة', style: sub)]
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
                              ].join(' — '),
                              style: sub,
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
          _Section(
            title: 'الزيارات والروشتات',
            children: _byDoctor.isEmpty
                ? [Text('مفيش زيارات ولا روشتات متسجّلة', style: sub)]
                : [
                    for (final (doctor, visits) in _byDoctor)
                      Container(
                        key: ValueKey('doctor-group-${doctor ?? 'مجهول'}'),
                        margin: const EdgeInsets.only(bottom: F.s8),
                        padding: const EdgeInsets.all(F.s12),
                        decoration: BoxDecoration(
                          color: F.railGround,
                          borderRadius: BorderRadius.circular(F.radiusCard),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // اسم الدكتور هو ترويسة اللي تحته. ومكتوبش؟
                            // بيتقال بالكلام، ما بيتخترعش ولا بيتساب فاضي.
                            Text(
                              doctor ?? 'من غير اسم دكتور على الورقة',
                              textDirection: doctor == null ? null : nameDirection(doctor),
                              style: body.copyWith(fontWeight: FontWeight.w700),
                            ),
                            for (final v in visits)
                              Padding(
                                padding: const EdgeInsets.only(top: F.s4),
                                child: Text(
                                  [v.title, ?v.place, arabicDate(v.at)].join(' — '),
                                  style: sub,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
          ),
          _Section(
            title: 'القياسات — آخر ${arabicNumber(30)} يوم',
            children: [
              if (recent.isEmpty) Text('مفيش قياسات سكر في آخر ٣٠ يوم', style: sub),
              for (final c in GlucoseContext.values)
                if (GlucoseStats.of([for (final r in recent) if (r.context == c) r.valueMgDl]) case final st?)
                  Container(
                    margin: const EdgeInsets.only(bottom: F.s8),
                    padding: const EdgeInsets.all(F.s12),
                    decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('سكر ${c.label} — ${arabicNumber(st.count)} قياس', style: body.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          'متوسط ${arabicNumber(st.average)} — أقل ${arabicNumber(st.lowest)} — أعلى ${arabicNumber(st.highest)} ملّيجرام/ديسيلتر',
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
                ? [Text('مفيش تحاليل متسجّلة', style: sub)]
                : [
                    for (final l in _labs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: F.s4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${l.name} ${arabicDecimal(l.value)}${l.unit == null ? '' : ' ${l.unit}'}',
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.right,
                                    style: body.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                // الشاشة دي بتتفتح والدكتور واقف — العلامة
                                // جنب الرقم نفسه، مش تحته.
                                if (labFlagWord(l.flag) != null) ...[
                                  const SizedBox(width: F.s8),
                                  LabFlagBadge(l.flag),
                                ],
                              ],
                            ),
                            // نطاق الورقة في سطره — زي شاشة الابن بالظبط،
                            // وسطر التاريخ فاضل زي ما هو.
                            Text(labRangeText(l.range) ?? labNoRangeText, style: sub),
                            Text(
                              [
                                arabicDate(l.at),
                                if (l.previous case (final v, final at)) 'كان ${arabicDecimal(v)} في ${arabicDate(at)}',
                              ].join(' — '),
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
                Text('لسه مفيش أسئلة. اكتب اللي عايزين تسألوا الدكتور فيه عشان ما يتنسيش.', style: sub),
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
                            side: BorderSide(color: F.line, width: 1.5),
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
                  hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  filled: true,
                  fillColor: F.fieldGround,
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
              Text(title, style: TextStyle(fontSize: F.sectionHeadSize, fontWeight: FontWeight.w700, color: F.green)),
              const SizedBox(height: F.s8),
              ...children,
            ],
          ),
        ),
      );
}
