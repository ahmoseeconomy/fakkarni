import 'package:drift/drift.dart';

import '../../core/format/arabic_time.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/emergency_repository.dart';
import '../../data/repositories/lab_results_repository.dart' show rangeOfRow;
import '../../data/repositories/vitals_repository.dart';
import '../../domain/health/glucose_summary.dart';
import '../../domain/health/vitals.dart';
import '../../domain/health/lab_range.dart';
import '../health/usual_words.dart'
    show GlucoseContextWords, arabicDecimal, labFlagWord, labRangeFooter, labRangeText;
import '../../domain/adherence/export_adherence.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/medication/medicine_form.dart';
import '../medication/med_groups.dart' show MedGroup;
import '../records/record_kinds.dart' show RecordPeriod, RecordPeriodWords;

/// أقسام الملف — بالترتيب اللي بتتكتب بيه.
enum ExportSection {
  medications('الأدوية والجرعات', visibleByDefault: true),
  labs('نتايج التحاليل', visibleByDefault: true),
  imaging('الأشعة', visibleByDefault: true),
  prescriptions('الروشتات', visibleByDefault: true),
  glucose('قراءات السكر', visibleByDefault: true),

  /// الضغط والنبض والوزن والأكسجين والحرارة — آخر قياس لكل نوع في الفترة.
  vitals('القياسات', visibleByDefault: true),
  visits('الزيارات والحجوزات', visibleByDefault: true),

  /// فصيلة الدم والحساسية والأمراض — **مخفي من الأول**. أرقام جهات الاتصال
  /// عمرها ما بتدخل الملف، مخفي ولا ظاهر.
  emergency('معلومات الطوارئ', visibleByDefault: false);

  const ExportSection(this.label, {required this.visibleByDefault});

  final String label;
  final bool visibleByDefault;

  /// الأدوية الحالية ومعلومات الطوارئ مش مربوطين بالفترة.
  bool get dated => this != medications && this != emergency;
}

class ExportOptions {
  const ExportOptions({required this.period, required this.visible});

  factory ExportOptions.defaults() => ExportOptions(
    period: RecordPeriod.threeMonths,
    visible: {
      for (final s in ExportSection.values)
        if (s.visibleByDefault) s,
    },
  );

  final RecordPeriod period;
  final Set<ExportSection> visible;
}

/// جدول في قسم — العنوان تاريخ التقرير، وبعده صفوفه.
///
/// التحاليل بقت جدول مش قايمة: الصف الواحد فيه اسم التحليل، الرقم بوحدته،
/// **نطاق الورقة**، والكلمة. الأعمدة بتخلي العين تقارن رأسياً بدل ما تقرا
/// جملة طويلة لكل سطر.
class ExportTable {
  const ExportTable({required this.caption, required this.headers, required this.rows});

  final String caption;
  final List<String> headers;
  final List<List<String>> rows;
}

/// قسم جاهز للكتابة: عنوان وسطور — و[tables] للأقسام اللي بتتكتب جداول.
///
/// [footnote] سطر واحد تحت القسم كله (التحاليل: النطاقات بتاعة المعمل).
class ExportBlock {
  const ExportBlock({required this.section, required this.lines, this.tables = const [], this.footnote});

  final ExportSection section;
  final List<String> lines;
  final List<ExportTable> tables;
  final String? footnote;
}

/// صف دوا في جدول الملف (المرحلة ٤): الدوا | لإيه (نقطة المجموعة بلونها
/// وكلمتها) | الجرعة (النوع — كام مرة) | المواعيد | الالتزام (شريط + ٪).
class ExportMedRow {
  const ExportMedRow({
    required this.name,
    required this.group,
    required this.doseLabel,
    required this.timesLabel,
    required this.pct,
  });

  final String name;
  final MedGroup group;
  final String doseLabel;
  final String timesLabel;

  /// null = مفيش جرعات متسجّلة للدوا ده في الفترة — العمود بيقول كده
  /// بالكلمة، مش بيخترع رقم.
  final int? pct;
}

/// ملخص أول صفحة: البلاطات التلاتة وجدول الأدوية وسطور الصدق.
class ExportSummary {
  const ExportSummary({
    required this.adherence,
    required this.currentMedsCount,
    required this.medRows,
    required this.dataStartLine,
  });

  final ExportAdherence adherence;
  final int currentMedsCount;
  final List<ExportMedRow> medRows;

  /// «البيانات المتسجّلة بتبدأ من …» — بس لما الفترة المطلوبة أقدم من أول
  /// تسجيل (التطبيق اتنصّب في النص مثلاً). null = الفترة كلها متغطّية.
  final String? dataStartLine;
}

/// **الملف زي ما هيتولّد بالظبط** — والقسم المخفي مش هنا أصلاً.
///
/// من المرحلة ٤: القسم **الفاضي** مش block — اسمه بيروح [emptySections]
/// وبيتكتب سطر شرايح واحد («مفيش تسجيلات في الفترة دي») بدل «مفيش حاجة
/// متسجّلة» مكرّرة تحت كل عنوان.
class ExportDocument {
  const ExportDocument({
    required this.patientLine,
    required this.rangeLine,
    required this.generatedLine,
    required this.blocks,
    this.summary,
    this.emptySections = const [],
  });

  final String patientLine;
  final String rangeLine;
  final String generatedLine;
  final List<ExportBlock> blocks;
  final ExportSummary? summary;
  final List<String> emptySections;
}

/// بيجمع **الأقسام الظاهرة بس**. القسم المخفي ما بيتقراش من القاعدة أصلاً —
/// الإخفاء بيتفرض هنا، وقت التوليد، مش وقت العرض.
Future<ExportDocument> collectExport(
  AppDatabase db, {
  required int patientId,
  required ExportOptions options,
  required DateTime now,
}) async {
  final patient = await (db.select(db.patients)..where((t) => t.id.equals(patientId))).getSingleOrNull();
  final name = patient?.name;
  final hasName = name != null && name.isNotEmpty && name != 'أنا';
  final age = patient?.age;

  bool inRange(DateTime at) => options.period.includes(at, now);
  final visible = options.visible;
  final blocks = <ExportBlock>[];
  // القسم الفاضي اسمه هنا — سطر شرايح واحد بدل «مفيش» مكرّرة (المرحلة ٤)
  final empty = <String>[];

  final from = switch (options.period) {
    RecordPeriod.month => DateTime(now.year, now.month - 1, now.day),
    RecordPeriod.threeMonths => DateTime(now.year, now.month - 3, now.day),
    RecordPeriod.year => DateTime(now.year - 1, now.month, now.day),
    RecordPeriod.all => null,
  };

  // الالتزام (المرحلة ٤، قرارات 4A/5A) — من صفوف الفترة، بحساب نقي.
  final summary = await _summary(db, patientId, from: from, now: now);

  for (final section in ExportSection.values) {
    if (!visible.contains(section)) continue; // المخفي: ولا سطر ولا استعلام
    // التحاليل جدول مش قايمة — نفس الفلترة، شكل تاني.
    if (section == ExportSection.labs) {
      final tables = await _labTables(db, patientId, inRange);
      if (tables.isEmpty) {
        empty.add(section.label);
      } else {
        blocks.add(ExportBlock(section: section, lines: const [], tables: tables, footnote: labRangeFooter));
      }
      continue;
    }
    // الأدوية بقت جدول الملخص (المرحلة ٤) — مش قايمة سطور هنا.
    if (section == ExportSection.medications) {
      if (summary.medRows.isEmpty) empty.add(section.label);
      continue;
    }
    final lines = switch (section) {
      ExportSection.medications || ExportSection.labs => const <String>[], // فوق
      ExportSection.imaging => await _records(db, patientId, RecordKind.imaging, inRange),
      ExportSection.prescriptions => await _records(db, patientId, RecordKind.prescription, inRange),
      ExportSection.glucose => await _glucose(db, patientId, inRange),
      ExportSection.vitals => await _vitals(db, patientId, inRange),
      ExportSection.visits => [
        ...await _records(db, patientId, RecordKind.visit, inRange),
        ...await _records(db, patientId, RecordKind.booking, inRange),
      ],
      ExportSection.emergency => await _emergency(db, patientId),
    };
    if (lines.isEmpty) {
      empty.add(section.label);
    } else {
      blocks.add(ExportBlock(section: section, lines: lines));
    }
  }

  return ExportDocument(
    patientLine: [hasName ? name : 'ملف صحي', if (age != null) '${arabicNumber(age)} سنة'].join(' — '),
    rangeLine: from == null ? 'الفترة: كل التاريخ' : 'الفترة: من ${arabicDate(from)} لـ ${arabicDate(now)}',
    generatedLine: 'اتعمل في ${arabicDate(now)}',
    blocks: blocks,
    summary: visible.contains(ExportSection.medications) ? summary : null,
    emptySections: empty,
  );
}

/// ملخص الالتزام وجدول الأدوية — الصفوف من `dose_events` الفترة،
/// والحساب كله في [exportAdherence] النقية (4A/5A).
Future<ExportSummary> _summary(AppDatabase db, int patientId, {required DateTime? from, required DateTime now}) async {
  final eventsQuery = db.select(db.doseEvents).join([
    innerJoin(db.doseSchedules, db.doseSchedules.id.equalsExp(db.doseEvents.doseScheduleId)),
    innerJoin(db.medications, db.medications.id.equalsExp(db.doseSchedules.medicationId)),
  ])..where(db.medications.patientId.equals(patientId));
  final rows = <ExportDoseRow>[];
  for (final row in await eventsQuery.get()) {
    final e = row.readTable(db.doseEvents);
    final m = row.readTable(db.medications);
    rows.add(ExportDoseRow(
      medicationId: m.id,
      medicationName: m.name,
      routineDay: e.routineDay,
      scheduledAt: e.scheduledAt,
      state: ExportDoseState.values.asNameMap()[e.state.name] ?? ExportDoseState.superseded,
      actedAt: e.actedAt,
    ));
  }

  final start = from ?? DateTime(2000);
  final adherence = exportAdherence(rows: rows, from: start, to: now, now: now);

  // «البيانات بتبدأ من …» — الفترة المطلوبة أقدم من أول تسجيل (4A: بنقولها
  // بالكلمة، ما بنكمّلش الفراغ بتخمين).
  String? dataStart;
  if (adherence.firstRecordedDay case final first?) {
    final askedFrom = DateTime(start.year, start.month, start.day);
    if (first.isAfter(askedFrom.add(const Duration(days: 1)))) {
      dataStart = 'البيانات المتسجّلة بتبدأ من ${arabicDate(first)} — قبلها مفيش تسجيل.';
    }
  }

  final meds =
      await (db.select(db.medications)
            ..where((t) => t.patientId.equals(patientId) & t.stoppedAt.isNull() & t.removedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();
  final byMed = {for (final a in adherence.perMedicine) a.medicationId: a};
  final medRows = <ExportMedRow>[];
  for (final m in meds) {
    final schedules = await (db.select(
      db.doseSchedules,
    )..where((t) => t.medicationId.equals(m.id) & t.stoppedAt.isNull())).get();
    final times = <String>[];
    for (final sch in schedules) {
      final fixed = await (db.select(db.fixedTimings)..where((t) => t.doseScheduleId.equals(sch.id))).getSingleOrNull();
      if (fixed != null) times.add(arabicTime(DateTime(2026, 1, 1, 0, fixed.minuteOfDay)));
    }
    final form = MedicineForm.fromWire(m.form);
    medRows.add(ExportMedRow(
      name: m.name,
      group: MedGroup.of(MedicationPurpose.fromStorage(m.purpose)),
      doseLabel: [
        if (form != null) form.label,
        '${arabicNumber(schedules.length)}× في اليوم',
      ].join(' — '),
      timesLabel: times.join('، '),
      pct: byMed[m.id]?.pct,
    ));
  }

  return ExportSummary(
    adherence: adherence,
    currentMedsCount: meds.length,
    medRows: medRows,
    dataStartLine: dataStart,
  );
}

/// أعمدة جدول التحاليل — **الكلمة عمود لوحدها**، مش لون جنب الرقم: الملف
/// بيتطبع وبيتصوّر أبيض وأسود.
const labExportHeaders = ['التحليل', 'النتيجة', 'نطاق الورقة', ''];

/// جدول لكل تقرير، مجمّع بتاريخه، الأحدث الأول.
Future<List<ExportTable>> _labTables(AppDatabase db, int patientId, bool Function(DateTime) inRange) async {
  final query =
      db.select(db.labResults).join([innerJoin(db.records, db.records.id.equalsExp(db.labResults.recordId))])
        ..where(db.records.patientId.equals(patientId) & db.records.deletedAt.isNull())
        ..orderBy([OrderingTerm.desc(db.records.happenedAt), OrderingTerm.asc(db.labResults.id)]);

  final byDate = <DateTime, List<List<String>>>{};
  for (final row in await query.get()) {
    final at = row.readTable(db.records).happenedAt;
    if (!inRange(at)) continue;
    final r = row.readTable(db.labResults);
    final day = DateTime(at.year, at.month, at.day);
    final range = rangeOfRow(r);
    byDate.putIfAbsent(day, () => []).add([
      r.testName,
      '${arabicDecimal(r.value)}${r.unit == null ? '' : ' ${r.unit}'}',
      // الورقة ما طبعتش نطاق؟ شرطة — وعمود الكلمة بيفضل فاضي.
      labRangeText(range)?.replaceFirst('نطاق الورقة: ', '') ?? '—',
      labFlagWord(labFlagFor(r.value, range)) ?? '',
    ]);
  }
  return [
    for (final day in byDate.keys)
      ExportTable(caption: arabicDate(day), headers: labExportHeaders, rows: byDate[day]!),
  ];
}

Future<List<String>> _records(
  AppDatabase db,
  int patientId,
  RecordKind kind,
  bool Function(DateTime) inRange,
) async {
  final rows =
      await (db.select(db.records)
            ..where((t) => t.patientId.equals(patientId) & t.kind.equalsValue(kind) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.happenedAt)]))
          .get();
  return [
    for (final r in rows)
      if (inRange(r.happenedAt)) ...[
        [r.title, ?r.doctor, ?r.place, arabicDate(r.happenedAt)].join(' — '),
        if (r.notes != null) r.notes!,
      ],
  ];
}

Future<List<String>> _glucose(AppDatabase db, int patientId, bool Function(DateTime) inRange) async {
  final rows =
      await (db.select(db.readings)
            ..where((t) => t.patientId.equals(patientId))
            ..orderBy([(t) => OrderingTerm.desc(t.measuredAt)]))
          .get();
  final shown = [
    for (final r in rows)
      if (inRange(r.measuredAt)) r,
  ];
  return [
    for (final c in GlucoseContext.values)
      if (GlucoseStats.of([
            for (final r in shown)
              if (r.context == c) r.valueMgDl,
          ])
          case final s?)
        '${c.label}: ${arabicNumber(s.count)} قياس — أقل ${arabicNumber(s.lowest)} — أعلى ${arabicNumber(s.highest)} — متوسط ${arabicNumber(s.average)} ملّيجرام/ديسيلتر',
    for (final r in shown.take(30))
      '${arabicNumber(r.valueMgDl)} ${r.context.label} — ${arabicDate(r.measuredAt)} ${arabicTime(r.measuredAt)}',
  ];
}

Future<List<String>> _vitals(AppDatabase db, int patientId, bool Function(DateTime) inRange) async {
  final all = await VitalsRepository(db).all(patientId);
  return [
    for (final v in latestVitals([for (final v in all) if (inRange(v.measuredAt)) v]))
      '${v.kind.label}: ${vitalValueText(v)} — ${arabicDate(v.measuredAt)} ${arabicTime(v.measuredAt)}',
  ];
}

Future<List<String>> _emergency(AppDatabase db, int patientId) async {
  final info = await EmergencyRepository(db).get(patientId);
  // جهات الاتصال (أرقام تليفونات) **مش هنا عن قصد**.
  return [
    'فصيلة الدم: ${info.bloodType ?? 'لسه ما اتملاش'}',
    'الحساسية: ${info.allergies ?? 'لسه ما اتملاش'}',
    'الأمراض المزمنة: ${info.chronicConditions ?? 'لسه ما اتملاش'}',
  ];
}
