import '../../core/format/arabic_time.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/health/glucose_summary.dart';
import '../../domain/health/lab_range.dart';
import '../../domain/health/vitals.dart';
import '../care/caregiver_words.dart' show glucoseContextLabel;
import '../export/export_document.dart';
import '../health/usual_words.dart' show arabicDecimal, labFlagWord, labRangeFooter, labRangeText;

/// **الملف اللي الممرض بيطبعه أو يبعته** — نفس شكل ملف المريض
/// ([ExportDocument] و`buildExportPdf`)، من اللي موبايل المريض رفعه.
///
/// معلومات الطوارئ **برّه** زي الافتراضي عند المريض، وأرقام التليفونات مش
/// في السحابة أصلاً. أرقام وحقايق بس — مفيش حكم (نفس قاعدة D3.6).
ExportDocument nurseExportDocument(CaregiverSnapshot s, DateTime now) {
  List<String> records(String kind) => [
        for (final r in s.records)
          if (r.kind == kind) ...[
            [r.title, ?r.doctor, ?r.place, arabicDate(r.happenedAt)].join(' — '),
            if (r.notes case final n? when n.trim().isNotEmpty) n.trim(),
          ],
      ];

  final labs = <DateTime, List<List<String>>>{};
  for (final r in s.records) {
    if (r.kind != 'lab' || r.labLines.isEmpty) continue;
    final day = DateTime(r.happenedAt.year, r.happenedAt.month, r.happenedAt.day);
    for (final l in r.labLines) {
      labs.putIfAbsent(day, () => []).add([
        l.testName,
        '${arabicDecimal(l.value)}${l.unit == null ? '' : ' ${l.unit}'}',
        labRangeText(l.range)?.replaceFirst('نطاق الورقة: ', '') ?? '—',
        labFlagWord(labFlagFor(l.value, l.range)) ?? '',
      ]);
    }
  }
  final days = labs.keys.toList()..sort((a, b) => b.compareTo(a));

  final glucose = <String>[
    for (final c in const ['fasting', 'afterMeal'])
      if (GlucoseStats.of([for (final r in s.readings) if (r.context == c) r.valueMgDl]) case final g?)
        '${glucoseContextLabel(c)}: ${arabicNumber(g.count)} قياس — أقل ${arabicNumber(g.lowest)} — '
            'أعلى ${arabicNumber(g.highest)} — متوسط ${arabicNumber(g.average)} ملّيجرام/ديسيلتر',
  ];

  const none = ['مفيش حاجة متسجّلة'];
  List<String> orNone(List<String> lines) => lines.isEmpty ? none : lines;

  return ExportDocument(
    patientLine: s.patient.name,
    rangeLine: 'من اللي موبايل المريض رفعه',
    generatedLine: 'اتعمل من تطبيق فكرني في ${arabicDate(now)}',
    blocks: [
      ExportBlock(
        section: ExportSection.medications,
        lines: orNone([
          for (final m in s.medications)
            [m.name, ?m.amountLabel, ...m.rules].join(' — '),
        ]),
      ),
      ExportBlock(
        section: ExportSection.labs,
        lines: days.isEmpty ? none : const [],
        tables: [
          for (final d in days) ExportTable(caption: arabicDate(d), headers: labExportHeaders, rows: labs[d]!),
        ],
        footnote: days.isEmpty ? null : labRangeFooter,
      ),
      ExportBlock(section: ExportSection.imaging, lines: orNone(records('imaging'))),
      ExportBlock(section: ExportSection.prescriptions, lines: orNone(records('prescription'))),
      ExportBlock(section: ExportSection.glucose, lines: orNone(glucose)),
      ExportBlock(
        section: ExportSection.vitals,
        lines: orNone([
          for (final v in latestVitals(s.vitals))
            '${v.kind.label}: ${vitalValueText(v)} — ${arabicDate(v.measuredAt)} ${arabicTime(v.measuredAt)}',
        ]),
      ),
      ExportBlock(section: ExportSection.visits, lines: orNone([...records('visit'), ...records('booking')])),
    ],
  );
}
