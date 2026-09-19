import 'package:drift/drift.dart';

import '../../core/format/arabic_time.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/emergency_repository.dart';
import '../../domain/health/glucose_summary.dart';
import '../health/usual_words.dart' show GlucoseContextWords, arabicDecimal;
import '../records/record_kinds.dart' show RecordPeriod, RecordPeriodWords;

/// أقسام الملف — بالترتيب اللي بتتكتب بيه.
enum ExportSection {
  medications('الأدوية والجرعات', visibleByDefault: true),
  labs('نتايج التحاليل', visibleByDefault: true),
  imaging('الأشعة', visibleByDefault: true),
  prescriptions('الروشتات', visibleByDefault: true),
  glucose('قراءات السكر', visibleByDefault: true),
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
        visible: {for (final s in ExportSection.values) if (s.visibleByDefault) s},
      );

  final RecordPeriod period;
  final Set<ExportSection> visible;
}

/// قسم جاهز للكتابة: عنوان وسطور.
class ExportBlock {
  const ExportBlock({required this.section, required this.lines});

  final ExportSection section;
  final List<String> lines;
}

/// **الملف زي ما هيتولّد بالظبط** — والقسم المخفي مش هنا أصلاً.
class ExportDocument {
  const ExportDocument({
    required this.patientLine,
    required this.rangeLine,
    required this.generatedLine,
    required this.blocks,
  });

  final String patientLine;
  final String rangeLine;
  final String generatedLine;
  final List<ExportBlock> blocks;
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

  for (final section in ExportSection.values) {
    if (!visible.contains(section)) continue; // المخفي: ولا سطر ولا استعلام
    final lines = switch (section) {
      ExportSection.medications => await _medications(db, patientId),
      ExportSection.labs => await _labs(db, patientId, inRange),
      ExportSection.imaging => await _records(db, patientId, RecordKind.imaging, inRange),
      ExportSection.prescriptions => await _records(db, patientId, RecordKind.prescription, inRange),
      ExportSection.glucose => await _glucose(db, patientId, inRange),
      ExportSection.visits => [
          ...await _records(db, patientId, RecordKind.visit, inRange),
          ...await _records(db, patientId, RecordKind.booking, inRange),
        ],
      ExportSection.emergency => await _emergency(db, patientId),
    };
    blocks.add(ExportBlock(section: section, lines: lines.isEmpty ? const ['مفيش حاجة متسجّلة في الفترة دي'] : lines));
  }

  final from = switch (options.period) {
    RecordPeriod.month => DateTime(now.year, now.month - 1, now.day),
    RecordPeriod.threeMonths => DateTime(now.year, now.month - 3, now.day),
    RecordPeriod.year => DateTime(now.year - 1, now.month, now.day),
    RecordPeriod.all => null,
  };

  return ExportDocument(
    patientLine: [
      hasName ? name : 'ملف صحي',
      if (age != null) '${arabicNumber(age)} سنة',
    ].join(' — '),
    rangeLine: from == null ? 'الفترة: كل التاريخ' : 'الفترة: من ${arabicDate(from)} لـ ${arabicDate(now)}',
    generatedLine: 'اتعمل من تطبيق فكرني في ${arabicDate(now)}',
    blocks: blocks,
  );
}

Future<List<String>> _medications(AppDatabase db, int patientId) async {
  final meds = await (db.select(db.medications)
        // الموقوف مش دوا حالي، والمتشال مش موجود أصلاً
        ..where((t) => t.patientId.equals(patientId) & t.stoppedAt.isNull() & t.removedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
  final lines = <String>[];
  for (final m in meds) {
    final schedules = await (db.select(db.doseSchedules)
          ..where((t) => t.medicationId.equals(m.id) & t.stoppedAt.isNull()))
        .get();
    lines.add([
      m.name,
      if (m.amountLabel != null) m.amountLabel!,
      '${arabicNumber(schedules.length)}× في اليوم',
    ].join(' — '));
  }
  return lines;
}

Future<List<String>> _labs(AppDatabase db, int patientId, bool Function(DateTime) inRange) async {
  final query = db.select(db.labResults).join([
    innerJoin(db.records, db.records.id.equalsExp(db.labResults.recordId)),
  ])
    ..where(db.records.patientId.equals(patientId) & db.records.deletedAt.isNull())
    ..orderBy([OrderingTerm.desc(db.records.happenedAt), OrderingTerm.asc(db.labResults.id)]);
  return [
    for (final row in await query.get())
      if (inRange(row.readTable(db.records).happenedAt))
        () {
          final r = row.readTable(db.labResults);
          final unit = r.unit == null ? '' : ' ${r.unit}';
          return '${r.testName} ${arabicDecimal(r.value)}$unit — ${arabicDate(row.readTable(db.records).happenedAt)}';
        }(),
  ];
}

Future<List<String>> _records(AppDatabase db, int patientId, RecordKind kind, bool Function(DateTime) inRange) async {
  final rows = await (db.select(db.records)
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
  final rows = await (db.select(db.readings)
        ..where((t) => t.patientId.equals(patientId))
        ..orderBy([(t) => OrderingTerm.desc(t.measuredAt)]))
      .get();
  final shown = [for (final r in rows) if (inRange(r.measuredAt)) r];
  return [
    for (final c in GlucoseContext.values)
      if (GlucoseStats.of([for (final r in shown) if (r.context == c) r.valueMgDl]) case final s?)
        '${c.label}: ${arabicNumber(s.count)} قياس — أقل ${arabicNumber(s.lowest)} — أعلى ${arabicNumber(s.highest)} — متوسط ${arabicNumber(s.average)} ملّيجرام/ديسيلتر',
    for (final r in shown.take(30))
      '${arabicNumber(r.valueMgDl)} ${r.context.label} — ${arabicDate(r.measuredAt)} ${arabicTime(r.measuredAt)}',
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
