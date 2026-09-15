import '../../core/format/arabic_time.dart';
import '../../data/care/caregiver_remote.dart';
import '../../data/db/tables.dart' show GlucoseContext, RecordKind;
import '../health/usual_words.dart' show GlucoseContextWords, arabicDecimal;
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

/// سطر «الجديد» — النوع والعنوان، والتاريخ تحته.
String newItemTitle(CaregiverNewItem item) => switch (item.type) {
      NewItemType.record => '${recordKindLabel(item.record!.kind)}: ${item.record!.title}',
      NewItemType.reading =>
        'قياس سكر ${glucoseContextLabel(item.reading!.context)}: ${glucoseValue(item.reading!.valueMgDl)}',
      NewItemType.question => 'سؤال للدكتور: ${item.question!.body}',
    };
