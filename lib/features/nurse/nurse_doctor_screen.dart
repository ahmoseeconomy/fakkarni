import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/health/glucose_summary.dart';
import '../../domain/health/vitals.dart';
import '../care/caregiver_snapshot_holder.dart';
import '../care/caregiver_words.dart' show glucoseContextLabel, labLineText;
import '../export/export_actions.dart';
import '../export/export_pdf.dart';
import '../export/export_preview_screen.dart';
import 'nurse_export.dart';
import 'nurse_header.dart';
import 'nurse_widgets.dart';

/// **«للدكتور»** — الورقة اللي الممرض بيفتحها والدكتور واقف: أدويته
/// بمواعيدها، ملخص السكر، آخر قيمة لكل تحليل، وأسئلة العيلة. أرقام
/// وحقايق بس (قاعدة D3.6)، والقسم الفاضي ما بيظهرش.
class NurseDoctorScreen extends StatefulWidget {
  const NurseDoctorScreen({required this.holder, this.now, this.fonts, this.actions, super.key});

  final CaregiverSnapshotHolder holder;
  final DateTime? now;

  /// للاختبارات — الحقيقي بيتحمّل من الأصول.
  final PdfFonts? fonts;
  final ExportActions? actions;

  @override
  State<NurseDoctorScreen> createState() => _NurseDoctorScreenState();
}

class _NurseDoctorScreenState extends State<NurseDoctorScreen> {
  bool _busy = false;

  Future<void> _export(CaregiverSnapshot s) async {
    setState(() => _busy = true);
    final now = widget.now ?? DateTime.now();
    final doc = nurseExportDocument(s, now);
    final bytes = await buildExportPdf(doc, widget.fonts ?? await PdfFonts.fromAssets());
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ExportPreviewScreen(
        pdf: bytes,
        document: doc,
        filename: 'fakkarni-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf',
        actions: widget.actions ?? const DeviceExportActions(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.holder.snapshot;
    final text = TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5);
    final children = <Widget>[];
    if (s != null) {
      if (s.medications.isNotEmpty) {
        children.addAll([
          const FSectionHead('أدويته'),
          const SizedBox(height: F.s6),
          for (final m in s.medications)
            Padding(
              padding: const EdgeInsets.only(bottom: F.s6),
              child: Text([m.name, ?m.amountLabel, ...m.rules].join(' — '), style: text),
            ),
          const SizedBox(height: F.s12),
        ]);
      }
      final glucose = [
        for (final c in const ['fasting', 'afterMeal'])
          if (GlucoseStats.of([for (final r in s.readings) if (r.context == c) r.valueMgDl]) case final g?)
            '${glucoseContextLabel(c)}: ${arabicNumber(g.count)} قياس — أقل ${arabicNumber(g.lowest)} — '
                'أعلى ${arabicNumber(g.highest)} — متوسط ${arabicNumber(g.average)}',
      ];
      if (glucose.isNotEmpty) {
        children.addAll([
          const FSectionHead('السكر — آخر ٣٠ يوم'),
          const SizedBox(height: F.s6),
          for (final g in glucose) Text(g, style: text),
          const SizedBox(height: F.s12),
        ]);
      }
      final vitals = latestVitals(s.vitals);
      if (vitals.isNotEmpty) {
        children.addAll([
          const FSectionHead('آخر قياس لكل نوع'),
          const SizedBox(height: F.s6),
          for (final v in vitals) Text('${v.kind.label}: ${vitalValueText(v)} — ${arabicDate(v.measuredAt)}', style: text),
          const SizedBox(height: F.s12),
        ]);
      }
      // آخر قيمة لكل تحليل — السجلات جاية الأحدث وصولاً الأول، فبنرتّب بالتاريخ
      final latest = <String, (DateTime, CaregiverLabLine)>{};
      for (final r in [...s.records]..sort((a, b) => b.happenedAt.compareTo(a.happenedAt))) {
        for (final l in r.labLines) {
          latest.putIfAbsent(l.testName.toLowerCase(), () => (r.happenedAt, l));
        }
      }
      if (latest.isNotEmpty) {
        children.addAll([
          const FSectionHead('آخر التحاليل'),
          const SizedBox(height: F.s6),
          for (final (at, l) in latest.values)
            Text('${labLineText(l)} — ${arabicDate(at)}', style: text),
          const SizedBox(height: F.s12),
        ]);
      }
      if (s.questions.isNotEmpty) {
        children.addAll([
          const FSectionHead('أسئلة العيلة'),
          const SizedBox(height: F.s6),
          for (final q in s.questions) Text(q.asked ? '${q.body} — اتسأل ✓' : q.body, style: text),
          const SizedBox(height: F.s12),
        ]);
      }
      if (children.isEmpty) {
        children.add(const NurseQuietLine('لسه مفيش حاجة للدكتور — أول ما المريض يصوّر روشتة أو تحليل هتظهر هنا.'));
      }
      children.addAll([
        const SizedBox(height: F.s8),
        FSecondaryButton(
          key: const ValueKey('nurse-export'),
          label: _busy ? 'ثواني…' : 'اطبع أو ابعت الملف',
          onPressed: _busy ? null : () => _export(s),
        ),
      ]);
    }
    return Scaffold(
      appBar: NurseHeader(holder: widget.holder),
      body: ListView(padding: const EdgeInsets.all(F.gap), children: [const NurseScreenTitle('للدكتور'), ...children]),
    );
  }
}
