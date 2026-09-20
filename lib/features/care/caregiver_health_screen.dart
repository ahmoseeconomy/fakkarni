import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../data/care/caregiver_remote.dart';
import '../emergency/emergency_facts_card.dart';
import '../health/lab_flag.dart';
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

    return [
      EmergencyFactsCard(
        bloodType: emergency?.bloodType,
        allergies: emergency?.allergies,
        chronicConditions: emergency?.chronicConditions,
      ),
      const SizedBox(height: F.gap),
      const _Head('قياسات السكر — آخر ٣٠ يوم'),
      if (snapshot.readings.isEmpty)
        const _Panel(text: 'لسه مفيش حاجة هنا.')
      else
        _Box(children: [for (final r in snapshot.readings) _ReadingRow(reading: r)]),
      const SizedBox(height: F.gap),
      const _Head('السجلات'),
      if (snapshot.records.isEmpty)
        const _Panel(text: 'لسه مفيش حاجة هنا.')
      else
        for (final kind in kinds) ...[
          _SubHead(recordKindPlural(kind)),
          for (final r in byKind[kind]!) _RecordCard(record: r),
        ],
      const SizedBox(height: F.gap),
      const _Head('أسئلة للدكتور'),
      if (snapshot.questions.isEmpty)
        const _Panel(text: 'لسه مفيش حاجة هنا.')
      else
        _Box(children: [for (final q in snapshot.questions) _QuestionRow(question: q)]),
    ];
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: Text(text, style: TextStyle(fontSize: F.sectionHeadSize, fontWeight: FontWeight.w700, color: F.ink)),
      );
}

class _SubHead extends StatelessWidget {
  const _SubHead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: F.s4, bottom: F.s6),
        child: Text(text, style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.green)),
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

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final CaregiverRecord record;

  @override
  Widget build(BuildContext context) => Container(
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
            if (record.notes != null && record.notes!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: F.s4),
                child: Text(record.notes!, style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5)),
              ),
            if (record.labLines.isNotEmpty) ...[
              const SizedBox(height: F.s8),
              for (final line in record.labLines)
                Container(
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
                      // نطاق الورقة والعلامة — نفس اللي على شاشة الأب
                      // بالحرف. الابن بيشوف الورقة، مش رأينا فيها.
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
                ),
            ],
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
