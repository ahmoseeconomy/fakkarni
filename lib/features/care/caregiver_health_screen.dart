import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../emergency/emergency_facts_card.dart';
import '../health/lab_flag.dart';
import '../records/record_kinds.dart' show RecordKindWords;
import 'caregiver_snapshot_holder.dart';
import 'caregiver_words.dart';

/// «الملف الصحي» عند الابن (D5.2) — نفس الصورة اللي «متابعة» بتقرا منها.
///
/// **قراية بس، من غير استثناء**: مفيش «ضيف» ولا «عدّل» ولا «امسح» — أي زرار
/// بيغيّر بيانات الأب مش موجود هنا خالص (`caregiver_shell_test`). الأرقام
/// بتتقال زي ما هي، من غير «المعتاد» ولا حكم (قاعدة D3.6). الصور جاية في
/// D5.3 — سجل ليه صورة ما بيعرضش مكان فاضي ولا صورة مكسورة.
class CaregiverHealthScreen extends StatefulWidget {
  const CaregiverHealthScreen({required this.holder, super.key});

  final CaregiverSnapshotHolder holder;

  /// ترتيب الأنواع على الشاشة — التحاليل والزيارات الأول.
  static const kindOrder = ['lab', 'visit', 'imaging', 'prescription', 'booking'];

  @override
  State<CaregiverHealthScreen> createState() => _CaregiverHealthScreenState();
}

class _CaregiverHealthScreenState extends State<CaregiverHealthScreen> {
  @override
  void initState() {
    super.initState();
    widget.holder.addListener(_changed);
  }

  @override
  void didUpdateWidget(CaregiverHealthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holder != widget.holder) {
      oldWidget.holder.removeListener(_changed);
      widget.holder.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.holder.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final holder = widget.holder;
    final snapshot = holder.snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الصحي')),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: holder.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: [
              if (holder.error != null) ...[
                _Panel(text: holder.error!),
                const SizedBox(height: F.gap),
              ],
              if (holder.loading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: F.green)),
                )
              else if (snapshot != null)
                ..._sections(snapshot)
              else
                const _Panel(text: 'لسه مفيش حاجة وصلت من موبايل والدك.'),
            ],
          ),
        ),
      ),
    );
  }

  /// **مداخل، مش لفّة واحدة على كل حاجة** — نفس تقسيم ملف الأب (جولة ٢٨).
  ///
  /// الشاشة كانت بترصّ الطوارئ والسكر وكل نوع سجل والأسئلة تحت بعض في
  /// سكرول واحد، والابن بيدوّر بعينه. دلوقتي كارت الطوارئ فوق (ده كارت
  /// بيتقرا بنظرة، مش قايمة)، وتحته مدخل لكل حاجة فيها محتوى — بعدده —
  /// وكل مدخل بيفتح قايمته.
  ///
  /// المدخل الفاضي مش بيظهر أصلاً: غيابه هو «مفيش حاجة هنا»، من غير لوحة
  /// بتقولها. ولو مفيش ولا حاجة خالص، جملة واحدة بدل خمس لوحات فاضية.
  List<Widget> _sections(CaregiverSnapshot snapshot) {
    final byKind = <String, List<CaregiverRecord>>{};
    for (final r in snapshot.records) {
      byKind.putIfAbsent(r.kind, () => []).add(r);
    }
    final kinds = [
      for (final k in CaregiverHealthScreen.kindOrder)
        if (byKind.containsKey(k)) k,
      for (final k in byKind.keys)
        if (!CaregiverHealthScreen.kindOrder.contains(k)) k,
    ];
    final emergency = snapshot.emergency;
    final entries = <Widget>[
      if (snapshot.readings.isNotEmpty)
        _Entry(
          key: const ValueKey('care-entry-readings'),
          icon: Icons.water_drop_outlined,
          label: 'قياسات السكر — آخر ٣٠ يوم',
          count: snapshot.readings.length,
          onTap: () => _open(CareListKind.readings),
        ),
      for (final kind in kinds)
        _Entry(
          key: ValueKey('care-entry-$kind'),
          icon: recordKindOf(kind)?.icon ?? Icons.description_outlined,
          label: recordKindPlural(kind),
          count: byKind[kind]!.length,
          onTap: () => _open(CareListKind.records, recordKind: kind),
        ),
      if (snapshot.questions.isNotEmpty)
        _Entry(
          key: const ValueKey('care-entry-questions'),
          icon: Icons.help_outline,
          label: 'أسئلة للدكتور',
          count: snapshot.questions.length,
          onTap: () => _open(CareListKind.questions),
        ),
    ];

    return [
      EmergencyFactsCard(
        bloodType: emergency?.bloodType,
        allergies: emergency?.allergies,
        chronicConditions: emergency?.chronicConditions,
      ),
      const SizedBox(height: F.gap),
      if (entries.isEmpty)
        const _Panel(text: 'لسه مفيش حاجة هنا.')
      else
        ...entries,
    ];
  }

  void _open(CareListKind kind, {String? recordKind}) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CareListScreen(holder: widget.holder, kind: kind, recordKind: recordKind),
        ),
      );
}

/// نوع القايمة اللي المدخل بيفتحها.
enum CareListKind { readings, records, questions }

/// قايمة نوع واحد عند الابن — **بتقرا من نفس الصورة الحيّة**.
///
/// بتسمع للـholder زي الشاشة اللي فتحتها، فالسؤال الدوري (كل ١٠ ثواني وهو
/// على تبويب بيانات) بيحدّثها وهي مفتوحة. لو كانت بتاخد نسخة ثابتة وقت
/// الفتح، الابن كان هيبص على قايمة واقفة من غير ما حاجة تقول له.
class CareListScreen extends StatefulWidget {
  const CareListScreen({required this.holder, required this.kind, this.recordKind, super.key});

  final CaregiverSnapshotHolder holder;
  final CareListKind kind;

  /// نوع السجل لما [kind] يكون [CareListKind.records].
  final String? recordKind;

  @override
  State<CareListScreen> createState() => _CareListScreenState();
}

class _CareListScreenState extends State<CareListScreen> {
  @override
  void initState() {
    super.initState();
    widget.holder.addListener(_changed);
  }

  @override
  void dispose() {
    widget.holder.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get _title => switch (widget.kind) {
        CareListKind.readings => 'قياسات السكر — آخر ٣٠ يوم',
        CareListKind.questions => 'أسئلة للدكتور',
        CareListKind.records => recordKindPlural(widget.recordKind ?? ''),
      };

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.holder.snapshot;
    final records = [
      for (final r in snapshot?.records ?? const <CaregiverRecord>[])
        if (r.kind == widget.recordKind) r,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: widget.holder.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: switch (widget.kind) {
              CareListKind.readings => [
                  _Box(children: [
                    for (final r in snapshot?.readings ?? const <CaregiverReading>[]) _ReadingRow(reading: r),
                  ]),
                ],
              CareListKind.questions => [
                  _Box(children: [
                    for (final q in snapshot?.questions ?? const <CaregiverQuestion>[]) _QuestionRow(question: q),
                  ]),
                ],
              CareListKind.records => [for (final r in records) _RecordCard(record: r)],
            },
          ),
        ),
      ),
    );
  }
}

/// مدخل واحد: أيقونة، اسم، وعدد — ونفس شكل مداخل ملف الأب.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s10),
        child: FCard(
          child: InkWell(
            borderRadius: BorderRadius.circular(F.radiusCard),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: F.minTapTarget),
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                children: [
                  Icon(icon, size: 22, color: F.green),
                  const SizedBox(width: F.s10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                    ),
                  ),
                  Text(
                    arabicNumber(count),
                    style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.mutedDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s8),
        decoration: BoxDecoration(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) Divider(height: F.s12, color: F.lineSoft),
              child,
            ],
          ],
        ),
      );
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.reading});
  final CaregiverReading reading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: F.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              glucoseValue(reading.valueMgDl),
              style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
            ),
            Text(
              '${glucoseContextLabel(reading.context)} — ${arabicDate(reading.measuredAt)} ${arabicTime(reading.measuredAt)}',
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
            ),
          ],
        ),
      );
}

/// سجل واحد — **تمثيل واحد للنتايج، مش اتنين**.
///
/// الكارت كان بيكتب `notes` كفقرة («… APTT 23.4 sec — Haemoglobin 11.6
/// g/dL — …») وبعدين يعيد **نفس** النتايج تحتها كسطور. الفقرة دي حيطة:
/// محدش بيقراها، وهي أصلاً نفس اللي تحتها متكتوب بشكل أوحش. اتشالت لما
/// يكون فيه سطور تحاليل؛ السجل اللي مالوش سطور (زيارة، أشعة) لسه بيعرض
/// ملاحظته عادي — هي المحتوى الوحيد عنده.
class _RecordCard extends StatefulWidget {
  const _RecordCard({required this.record});
  final CaregiverRecord record;

  /// كام سطر سليم بيبانوا قبل ما نطوي.
  ///
  /// تقرير صورة دم فيه عشرين سطر بيبلع الشاشة كلها، والابن جاي يشوف
  /// **اللي برّه النطاق**. الرقم صغير عن قصد: التقرير الكامل على بعد دوسة.
  static const previewClean = 3;

  @override
  State<_RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<_RecordCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final lines = record.labLines;

    // **المتعلّم عمره ما بينطوي.** قيمة برّه نطاق الورقة لازم تبان من غير
    // ما حد يفتح حاجة — لو اتخبّت ورا زرار، الطي بقى إخفاء.
    final flagged = [for (final l in lines) if (labFlagWordOf(l) != null) l];
    final clean = [for (final l in lines) if (labFlagWordOf(l) == null) l];
    final hidden = _expanded ? 0 : (clean.length - _RecordCard.previewClean).clamp(0, clean.length);
    final shownClean = _expanded ? clean : clean.take(_RecordCard.previewClean).toList();
    // ترتيب الورقة محفوظ جوّه كل مجموعة؛ المتعلّم فوق عشان يتشاف الأول.
    final shown = [...flagged, ...shownClean];

    return Container(
      margin: const EdgeInsets.only(bottom: F.s8),
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: F.cardGround,
        borderRadius: BorderRadius.circular(F.radius),
        border: Border.all(color: F.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(record.title, style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
          Text(
            [arabicDate(record.happenedAt), ?record.doctor, ?record.place].join(' — '),
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          // الملاحظة بتتعرض بس لما ما يكونش فيه سطور — غير كده هي نفس
          // الكلام مرتين.
          if (lines.isEmpty && record.notes != null && record.notes!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: F.s4),
              child: Text(record.notes!, style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5)),
            ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: F.s8),
            for (final line in shown) _LabLineRow(line: line),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: F.s8),
                child: FSecondaryButton(
                  key: ValueKey('all-results-${record.uuid}'),
                  label: 'كل النتايج (${arabicNumber(lines.length)})',
                  onPressed: () => setState(() => _expanded = true),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// سطر نتيجة: الاسم والرقم بوحدته، وتحتهم نطاق الورقة وعلامته.
class _LabLineRow extends StatelessWidget {
  const _LabLineRow({required this.line});

  final CaregiverLabLine line;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: F.s4),
        padding: const EdgeInsetsDirectional.only(start: F.s12),
        decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: F.line, width: 3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              labLineText(line),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: F.minBodySize, color: F.ink),
            ),
            // نطاق الورقة والعلامة — نفس اللي على شاشة الأب بالحرف.
            // الابن بيشوف الورقة، مش رأينا فيها.
            Row(
              children: [
                Expanded(
                  child: Text(
                    labRangeLine(line),
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                  ),
                ),
                if (labFlagWordOf(line) != null) ...[
                  const SizedBox(width: F.s8),
                  LabFlagBadge(labFlagOf(line)),
                ],
              ],
            ),
          ],
        ),
      );
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.question});
  final CaregiverQuestion question;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: F.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(question.body, style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
            Text(
              question.asked ? 'اتسأل ✓' : 'لسه ما اتسألش',
              style: TextStyle(
                fontSize: F.minTextSize,
                fontWeight: FontWeight.w600,
                color: question.asked ? F.greenDeep : F.mutedDark,
              ),
            ),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.s14),
        decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
        child: Text(text, style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6)),
      );
}
