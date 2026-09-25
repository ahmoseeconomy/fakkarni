import '../../domain/care/circle_departure.dart';
import '../../core/format/arabic_time.dart';
import '../../data/care/caregiver_remote.dart';
import '../../data/db/tables.dart' show GlucoseContext, RecordKind;
import '../../domain/health/lab_range.dart';
import '../health/usual_words.dart'
    show GlucoseContextWords, arabicDecimal, labFlagWord, labNoRangeText, labRangeText;
import '../records/record_kinds.dart' show RecordKindWords;

/// كلام الابن عن الملف الصحي — **نفس الكلمات** اللي الأب بيشوفها (مفيش نسخة
/// تانية تختلف): اسم النوع من `record_kinds`، والسياق من `usual_words`.
/// القيم جاية من السحابة بالحرف المخزّن.

RecordKind? recordKindOf(String stored) => RecordKind.values.asNameMap()[stored];

/// «تحليل» — ولو نوع جديد مش معروف لسه: الكلمة المخزّنة، مش استثناء.
String recordKindLabel(String stored) => recordKindOf(stored)?.label ?? stored;

String recordKindPlural(String stored) => recordKindOf(stored)?.plural ?? stored;

/// «صايم» / «بعد الأكل».
String glucoseContextLabel(String stored) =>
    GlucoseContext.values.asNameMap()[stored]?.label ?? stored;

/// «١٢٨ ملّيجرام/ديسيلتر» — الرقم بس. مفيش «عالي» ولا «طبيعي» (قاعدة D3.6).
String glucoseValue(int mgDl) => '${arabicNumber(mgDl)} ملّيجرام/ديسيلتر';

/// «HbA1c ٧٫١ %».
String labLineText(CaregiverLabLine line) =>
    '${line.testName} ${arabicDecimal(line.value)}${line.unit == null ? '' : ' ${line.unit}'}';

/// سطر النطاق تحت الرقم — نطاق الورقة، أو إن الورقة مفيهاش نطاق.
///
/// **نفس الكلام اللي الأب شافه بالحرف** (`usual_words`)، مش نسخة تانية:
/// الاتنين بيبصّوا على نفس الورقة، ولازم يقروا نفس الجملة.
String labRangeLine(CaregiverLabLine line) => labRangeText(line.range) ?? labNoRangeText;

/// العلامة زي ما الأب شافها — مقارنة رقمين مطبوعين، مش حكم من عندنا.
LabFlag labFlagOf(CaregiverLabLine line) => labFlagFor(line.value, line.range);

/// الكلمة، أو null لو السطر ما بياخدش علامة.
String? labFlagWordOf(CaregiverLabLine line) => labFlagWord(labFlagOf(line));

/// أسامي حقول ترويسة السجل **حسب نوعه**.
///
/// «المكان» على تقرير تحليل معناها المعمل، وعلى روشتة معناها العيادة.
/// الكلمة الصح بتخلّي الواحد يعرف بيبص على إيه من غير ما يفكّر؛ كلمة
/// واحدة عامة بتخلّيه يخمّن.
({String place, String date, String doctor}) recordFieldLabels(String kind) =>
    switch (recordKindOf(kind)) {
      RecordKind.lab => (place: 'المعمل', date: 'تاريخ التقرير', doctor: 'الدكتور'),
      RecordKind.prescription => (place: 'العيادة', date: 'تاريخ الورقة', doctor: 'الدكتور'),
      RecordKind.imaging => (place: 'المركز', date: 'تاريخ الأشعة', doctor: 'الدكتور'),
      _ => (place: 'المكان', date: 'التاريخ', doctor: 'الدكتور'),
    };

/// أسامي أدوية الروشتة، سطر لكل واحد.
///
/// `notes` بتاعة الروشتة **إحنا** اللي كتبناها بالشكل ده
/// (`names.join(' — ')` في شاشة المراجعة)، فتقسيمها على نفس الفاصل قراية
/// لصيغتنا مش تخمين في نص إنسان. ولاحظ إنها بتتقسم **للروشتة بس**:
/// ملاحظة زيارة أو أشعة بيكتبها إنسان بإيده، وتقسيمها هيقطّع جملته.
List<String> prescriptionMedicines(String notes) => [
      for (final n in notes.split(' — '))
        if (n.trim().isNotEmpty) n.trim(),
    ];

/// سطر «الجديد» — النوع والعنوان، والتاريخ تحته.
String newItemTitle(CaregiverNewItem item) => switch (item.type) {
      NewItemType.record => '${recordKindLabel(item.record!.kind)}: ${item.record!.title}',
      NewItemType.reading =>
        'قياس سكر ${glucoseContextLabel(item.reading!.context)}: ${glucoseValue(item.reading!.valueMgDl)}',
      NewItemType.question => 'سؤال للدكتور: ${item.question!.body}',
      NewItemType.departure => departureLine(item.departure!),
    };

// ---------------------------------------------------------------- «كمان …»
//
// **الوقت النسبي هو اللي الابن بيقراه فعلاً.** «٨:٠٠ م» بيخلّيه يحسب؛
// «كمان ٦ ساعات» بيدّيه الإجابة. الساعة بتفضل مكتوبة جنبها — هو بيبص
// بسرعة، بس ساعات بيحتاج الرقم نفسه.
//
// العربي بيعدّ تلات صيغ (واحد، اتنين، جمع)، والكسر بينهم بيخلّي الجملة
// تقرا غلط. الصيغ هنا مكتوبة بالإيد لكل وحدة بدل قاعدة عامة بتغلط.

String _count(int n, String one, String two, String few, String many) => switch (n) {
      1 => one,
      2 => two,
      >= 3 && <= 10 => '${arabicNumber(n)} $few',
      _ => '${arabicNumber(n)} $many',
    };

/// «كمان ٤٠ دقيقة» — أو «دلوقتي» لو باقي أقل من دقيقة.
///
/// بتتحسب بالأيام التقويمية مش بالضرب في ٢٤ ساعة: مصر بتغيّر الساعة،
/// و«كمان يومين» المفروض تعدّ أيام مش ساعات.
String timeAhead(DateTime from, DateTime to) {
  final minutes = to.difference(from).inMinutes;
  if (minutes < 1) return 'دلوقتي';
  if (minutes < 60) {
    return 'كمان ${_count(minutes, 'دقيقة', 'دقيقتين', 'دقايق', 'دقيقة')}';
  }
  final days = DateTime(to.year, to.month, to.day)
      .difference(DateTime(from.year, from.month, from.day))
      .inDays;
  if (days == 0) {
    final hours = minutes ~/ 60;
    return 'كمان ${_count(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
  }
  if (days == 1) return 'بكرة';
  if (days == 2) return 'بعد بكرة';
  return 'كمان ${_count(days, 'يوم', 'يومين', 'أيام', 'يوم')}';
}

/// «من ٣ أيام» — للي عدّى. بتتنده على متابعة واقفة وعلى جرعة فاتت.
String timeSince(DateTime from, DateTime at) {
  final minutes = from.difference(at).inMinutes;
  if (minutes < 1) return 'دلوقتي';
  if (minutes < 60) {
    return 'من ${_count(minutes, 'دقيقة', 'دقيقتين', 'دقايق', 'دقيقة')}';
  }
  final days = DateTime(from.year, from.month, from.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days == 0) {
    final hours = minutes ~/ 60;
    return 'من ${_count(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
  }
  if (days == 1) return 'من امبارح';
  return 'من ${_count(days, 'يوم', 'يومين', 'أيام', 'يوم')}';
}
