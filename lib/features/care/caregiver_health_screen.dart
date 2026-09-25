import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';
import '../emergency/emergency_facts_card.dart';
import '../health/lab_flag.dart';
import '../../data/db/tables.dart' show RecordKind;
import '../records/record_kinds.dart' show RecordKindWords;
import 'caregiver_snapshot_holder.dart';
import 'caregiver_status.dart' show careStageDate;
import 'caregiver_ui.dart';
import 'caregiver_vitals_screen.dart';
import 'caregiver_words.dart';

/// «الملف الصحي» عند الابن (D5.2) — نفس الصورة اللي «متابعة» بتقرا منها.
///
/// **قراية بس، من غير استثناء**: مفيش «ضيف» ولا «عدّل» ولا «امسح» — أي زرار
/// بيغيّر بيانات الأب مش موجود هنا خالص (`caregiver_shell_test`). الأرقام
/// بتتقال زي ما هي، من غير «المعتاد» ولا حكم (قاعدة D3.6). الصور جاية في
/// D5.3 — سجل ليه صورة ما بيعرضش مكان فاضي ولا صورة مكسورة.
class CaregiverHealthScreen extends StatefulWidget {
  const CaregiverHealthScreen({required this.holder, this.now, super.key});

  final CaregiverSnapshotHolder holder;

  /// «دلوقتي» — بتتحقن من الاختبارات وبتتمرّر للقايمة اللي بتتفتح منها.
  final DateTime? now;

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
      appBar: careAppBar('الملف الطبي'),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: holder.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(F.carePad, F.careRowGap, F.carePad,
                F.carePad + MediaQuery.of(context).padding.bottom),
            children: [
              if (holder.error != null) ...[
                CarePanel(text: holder.error!, action: 'حاول تاني', onAction: holder.refresh),
              ],
              if (holder.loading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: F.green)),
                )
              else if (snapshot != null)
                ..._sections(snapshot)
              else
                const CarePanel(text: 'لسه مفيش حاجة وصلت من موبايل والدك.'),
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
  List<Widget> _notBought(CaregiverSnapshot snapshot) {
    final meds = [for (final m in snapshot.medications) if (m.notBoughtAt != null) m];
    if (meds.isEmpty) return const [];
    return [
      CareHead('أدوية لسه ماتشترتش', count: meds.length, accent: F.careAccentSkipped),
      CareCard(
        key: const ValueKey('care-not-bought'),
        border: F.careAccentSkipped,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in meds)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: F.s4),
                child: Text(
                  m.name,
                  style: TextStyle(
                    fontSize: F.careBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    fontFamily: F.monoFamily,
                    fontFamilyFallback: F.monoFallback,
                  ),
                ),
              ),
            Text('التذكير شغّال لها في ميعادها — دي بس لسه محتاجة تتشرى.',
                style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.4)),
          ],
        ),
      ),
      const SizedBox(height: F.careRowGap),
    ];
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
    final entries = <Widget>[
      if (snapshot.readings.isNotEmpty)
        _Entry(
          key: const ValueKey('care-entry-readings'),
          icon: Icons.water_drop_outlined,
          label: 'قياسات السكر — آخر ٣٠ يوم',
          count: snapshot.readings.length,
          accent: F.careAccentSkipped,
          onTap: () => _open(CareListKind.readings),
        ),
      for (final kind in kinds)
        _Entry(
          key: ValueKey('care-entry-$kind'),
          icon: recordKindOf(kind)?.icon ?? Icons.description_outlined,
          label: recordKindPlural(kind),
          count: byKind[kind]!.length,
          accent: careRecordAccent(kind),
          onTap: () => _open(CareListKind.records, recordKind: kind),
        ),
      // الضغط والنبض والوزن والأكسجين والحرارة (٠٠٢٧) — قراية بس
      if (snapshot.vitals.isNotEmpty)
        _Entry(
          key: const ValueKey('care-entry-vitals'),
          icon: Icons.monitor_heart_outlined,
          label: 'القياسات — الضغط والوزن وغيرهم',
          count: snapshot.vitals.length,
          accent: F.careAccentSkipped,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CaregiverVitalsScreen(holder: widget.holder, now: widget.now),
          )),
        ),
      if (snapshot.questions.isNotEmpty)
        _Entry(
          key: const ValueKey('care-entry-questions'),
          icon: Icons.help_outline,
          label: 'أسئلة للدكتور',
          count: snapshot.questions.length,
          accent: F.careAccentSkipped,
          onTap: () => _open(CareListKind.questions),
        ),
    ];

    return [
      EmergencyFactsCard(
        bloodType: emergency?.bloodType,
        allergies: emergency?.allergies,
        chronicConditions: emergency?.chronicConditions,
      ),
      const SizedBox(height: F.careRowGap),
      // ٠٠٣١: «أدوية لسه ماتشترتش» — قراية بس، ويختفي لو فاضي
      ..._notBought(snapshot),
      if (entries.isEmpty)
        const CarePanel(text: 'لسه مفيش حاجة هنا.')
      else
        ...entries,
    ];
  }

  void _open(CareListKind kind, {String? recordKind}) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CareListScreen(
            holder: widget.holder,
            kind: kind,
            recordKind: recordKind,
            now: widget.now,
          ),
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
  const CareListScreen({
    required this.holder,
    required this.kind,
    this.recordKind,
    this.now,
    super.key,
  });

  /// «دلوقتي» — بتتحقن من الاختبارات؛ منها «بكرة» و«بعد بكرة».
  final DateTime? now;

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

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.holder.snapshot;
    final records = [
      for (final r in snapshot?.records ?? const <CaregiverRecord>[])
        if (r.kind == widget.recordKind) r,
    ];
    // **نفس تقسيمة قايمة الأب بالحرف** — دالة واحدة، مش نسخة تانية.
    final sections = followSections<CaregiverRecord>(
      records,
      kindOf: (r) => FollowKind.fromStored(r.followKind),
      stageOf: (r) => FollowKind.fromStored(r.followKind).stageFromNumber(r.checkupStage),
      stageDateOf: (r) {
        final stage = FollowKind.fromStored(r.followKind).stageFromNumber(r.checkupStage);
        return stage == null ? null : careStageDate(r, stage);
      },
      newestFirst: (a, b) {
        final byDate = b.happenedAt.compareTo(a.happenedAt);
        return byDate != 0 ? byDate : b.uuid.compareTo(a.uuid);
      },
    );
    return Scaffold(
      appBar: careAppBar(_title),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: widget.holder.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(F.carePad, F.careRowGap, F.carePad,
                F.carePad + MediaQuery.of(context).padding.bottom),
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
              // قسم فاضي ما بيظهرش: غيابه هو «مفيش حاجة هنا».
              CareListKind.records => [
                  if (sections.waiting.isNotEmpty) ...[
                    CareHead(waitingSectionLabel(sections.waiting.length),
                        accent: careRecordAccent(widget.recordKind ?? '')),
                    for (final r in sections.waiting) _RecordCard(record: r, now: _now),
                  ],
                  if (sections.done.isNotEmpty) ...[
                    if (sections.waiting.isNotEmpty)
                      CareHead(doneSectionLabel(sections.done.length),
                          accent: careRecordAccent(widget.recordKind ?? '')),
                    for (final r in sections.done) _RecordCard(record: r, now: _now),
                  ],
                ],
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
    required this.accent,
    super.key,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  /// لون النوع — على الحد والشريط والأيقونة. شوف [careRecordAccent].
  final Color accent;

  @override
  Widget build(BuildContext context) => CareCard(
        border: accent,
        edge: accent,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: F.careTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.carePad),
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: F.s10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                        fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink),
                  ),
                ),
                Text(
                  arabicNumber(count),
                  style: TextStyle(
                      fontSize: F.careTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                ),
                const SizedBox(width: F.s4),
                Icon(Icons.chevron_left, size: 18, color: F.mutedDark),
              ],
            ),
          ),
        ),
      );
}

class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CareCard(
        // القياسات والأسئلة صنف تاني عن ورقة في ملف — محايد، زي مدخلهم.
        border: F.careAccentSkipped,
        edge: F.careAccentSkipped,
        padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) Divider(height: F.s10, color: F.lineSoft),
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
        padding: const EdgeInsets.symmetric(vertical: F.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              glucoseValue(reading.valueMgDl),
              style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink),
            ),
            Text(
              '${glucoseContextLabel(reading.context)} — ${arabicDate(reading.measuredAt)} ${arabicTime(reading.measuredAt)}',
              style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark),
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
  const _RecordCard({required this.record, required this.now});
  final CaregiverRecord record;
  final DateTime now;

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
    final kind = FollowKind.fromStored(record.followKind);
    // المتابعة **المفتوحة** بس هي اللي بتتعرض بقواعدها؛ اللي خلصت سجل
    // عادي بتاريخه، زي أي ورقة في الأرشيف.
    final openStage = kind.stageFromNumber(record.checkupStage);
    final stage = followIsOpen(kind, openStage) ? openStage : null;
    final lines = record.labLines;

    // **المتعلّم عمره ما بينطوي.** قيمة برّه نطاق الورقة لازم تبان من غير
    // ما حد يفتح حاجة — لو اتخبّت ورا زرار، الطي بقى إخفاء.
    final flagged = [for (final l in lines) if (labFlagWordOf(l) != null) l];
    final clean = [for (final l in lines) if (labFlagWordOf(l) == null) l];
    final hidden = _expanded ? 0 : (clean.length - _RecordCard.previewClean).clamp(0, clean.length);
    final shownClean = _expanded ? clean : clean.take(_RecordCard.previewClean).toList();
    // ترتيب الورقة محفوظ جوّه كل مجموعة؛ المتعلّم فوق عشان يتشاف الأول.
    final shown = [...flagged, ...shownClean];
    final labels = recordFieldLabels(record.kind);
    final medicines = recordKindOf(record.kind) == RecordKind.prescription
        ? prescriptionMedicines(record.notes ?? '')
        : const <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: F.careRowGap),
      padding: const EdgeInsets.all(F.carePad),
      decoration: BoxDecoration(
        color: F.cardGround,
        borderRadius: BorderRadius.circular(F.careRadius),
        // نفس لون نوعه اللي على المدخل اللي فتح القايمة — اللون بيمشي
        // مع الورقة، مش مع الشاشة.
        border: Border.all(color: careRecordAccent(record.kind), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            // **الاسم باللي بنتابعه** لو ده متابعة مفتوحة — «متابعة CBC»
            // مش «تقرير تحليل — ٦ نتايج».
            stage == null ? record.title : followDisplayTitle(kind, record.title),
            style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink),
          ),
          // **ترويسة بحقول مسمّاة، مش سطر واحد مربوط بشَرطات.**
          // «١٢ سبتمبر — د. طارق — معمل البرج» بيسيب اللي بيقرا يخمّن إيه
          // إيه؛ والاسم بيختلف بنوع الورقة كمان: «المعمل» على تقرير تحليل،
          // و«العيادة» على روشتة.
          const SizedBox(height: F.s6),
          // **متابعة مفتوحة عمرها ما تعرض `happenedAt`.** ده تاريخ بداية
          // المتابعة (أو تاريخ الورقة في الصفوف القديمة)، ومن جهاز حقيقي:
          // زيارة محجوزة بكرة كانت بتتعرض بتاريخ الروشتة. الميعاد ميعاد
          // المرحلة، ومن **نفس الدالة** اللي الأب و«متابعة» بيقروا منها.
          if (stage != null)
            _Field(
              label: 'الميعاد',
              value: followDateFull(careStageDate(record, stage), widget.now),
            )
          else
            _Field(label: labels.date, value: arabicDate(record.happenedAt)),
          if (stage != null)
            _Field(label: 'المرحلة', value: 'متابعة ${kind.word} — ${stage.label}'),
          if (record.doctor?.trim().isNotEmpty ?? false)
            _Field(label: labels.doctor, value: record.doctor!),
          if (record.place?.trim().isNotEmpty ?? false)
            _Field(label: labels.place, value: record.place!),
          // **أدوية الروشتة سطر لكل واحد** — كانت فقرة واحدة مربوطة
          // بشَرطات («Concor 5mg — Telfast — Augmentin»)، وهي نفس حيطة
          // نتايج التحليل اللي اتشالت قبل كده.
          if (lines.isEmpty && medicines.isNotEmpty) ...[
            const SizedBox(height: F.s8),
            _BodyHead('الأدوية', count: medicines.length),
            for (final m in medicines)
              Padding(
                padding: const EdgeInsets.only(top: F.s4),
                child: Text(
                  m,
                  textDirection: nameDirection(m),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: F.careTextSize, color: F.ink),
                ),
              ),
          ]
          // ملاحظة إنسان كتبها بإيده (زيارة، أشعة) — بتتعرض زي ما هي.
          else if (lines.isEmpty && record.notes != null && record.notes!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: F.s8),
              child: Text(record.notes!,
                  style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.5)),
            ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: F.s8),
            _BodyHead('النتايج', count: lines.length),
            for (final line in shown) _LabLineRow(line: line),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: F.s8),
                child: CareTextAction(
                  key: ValueKey('all-results-${record.uuid}'),
                  label: 'كل النتايج (${arabicNumber(lines.length)})',
                  icon: Icons.expand_more,
                  onPressed: () => setState(() => _expanded = true),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// حقل في ترويسة السجل: اسمه وقيمته.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: F.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark, height: 1.4),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textDirection: nameDirection(value),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: F.careTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

/// عنوان جسم السجل — «النتايج (٦)» / «الأدوية (٣)».
///
/// العدد جنبه عشان اللي بيقرا يعرف قد إيه قدامه قبل ما يبدأ.
class _BodyHead extends StatelessWidget {
  const _BodyHead(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: F.s6, bottom: F.s4),
        child: Text(
          '$text (${arabicNumber(count)})',
          style: TextStyle(fontSize: F.careHeadSize, fontWeight: FontWeight.w700, color: F.green),
        ),
      );
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
              style: TextStyle(fontSize: F.careBodySize, color: F.ink),
            ),
            // نطاق الورقة والعلامة — نفس اللي على شاشة الأب بالحرف.
            // الابن بيشوف الورقة، مش رأينا فيها.
            Row(
              children: [
                Expanded(
                  child: Text(
                    labRangeLine(line),
                    style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark, height: 1.5),
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
            Text(question.body, style: TextStyle(fontSize: F.careBodySize, color: F.ink, height: 1.4)),
            Text(
              question.asked ? 'اتسأل ✓' : 'لسه ما اتسألش',
              style: TextStyle(
                fontSize: F.careTextSize,
                fontWeight: FontWeight.w600,
                color: question.asked ? F.green : F.mutedDark,
              ),
            ),
          ],
        ),
      );
}
