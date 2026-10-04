// **تغيير دوا اقترحه ممرض** (المرحلة ب من تعليق المختبِر ٧) — دارت نقية.
//
// الممرض اللي الأب فتح له «يعدّل الأدوية» بيبعت تغيير **معلّق** للسيرفر؛
// موبايل الأب بيسحبه وبيطبّقه بنفس سكّة الإضافة/التعديل بتاعته، ويعيد
// الجدولة، ويقول «{اسم} ضاف دوا X». تعديل الأب المحلي بيكسب لو حصل بعد
// التغيير — والتعارض بيتسجّل مش بيتغطّى.

import '../escalation/alert_mode.dart';
import '../medication/medication_purpose.dart';
import '../scheduling/minute_of_day.dart';
import '../scheduling/dose_schedule.dart';

enum MedicationChangeKind {
  add('ضاف دوا'),
  stop('وقّف دوا'),
  amount('عدّل جرعة'),

  /// ٠٠٢٦: ورقة في الملف (روشتة/زيارة/تحليل/أشعة) من غير صورة.
  record('ضاف ورقة'),

  /// ٠٠٢٦: ميعاد دكتور أو معمل — بيبقى متابعة بميعادها وإشعاراتها على
  /// موبايل المريض، بنفس سكّة «ميعاد جديد».
  appointment('حط ميعاد'),

  /// ٠٠٢٨: «اشتريت علبة جديدة» من الممرض — كمية بتتزوّد على مخزون الدوا.
  restock('سجّل علبة جديدة من'),

  /// ٠٠٢٩: صورة جديدة للدوا من الممرض — بتترفع تحت `pending/` وموبايل
  /// المريض بيتحقق منها ويطبّقها بسكّته.
  photo('غيّر صورة'),

  /// ٠٠٣١: «اشتريته» من الممرض — بيشيل الدوا من «أدوية لسه ماتشترتش».
  bought('علّم إنه اشترى'),

  // ---- 0035: تطبيق الممرض نسخة من تطبيق المريض
  /// ساعات الدوا وأيامه من جديد: الجديد بيتكتب الأول والقديم بيتوقف —
  /// نفس `replaceDoses` بتاعة شاشة التعديل.
  timings('غيّر مواعيد'),

  /// «شيله خالص» — شيل ناعم (`removed_at`)، عمره ما مسح.
  remove('شال دوا'),

  /// رجوع دوا موقوف.
  resume('رجّع دوا'),

  /// قياس (ضغط / سكر / وزن / …) — صف في `vitals` على موبايل المريض.
  vital('سجّل قياس', stored: 'vital'),

  /// الكمية دلوقتي وأيام التحذير — بتتكتب فوق، عكس «علبة جديدة» اللي بتزوّد.
  stockSet('ظبّط مخزون', stored: 'stock_set'),

  /// «صيدليتي» بتاعة المريض: الاسم ورقم الاتصال والواتساب.
  pharmacy('غيّر صيدليتك', stored: 'pharmacy');

  const MedicationChangeKind(this.verb, {String? stored}) : _stored = stored; // ignore: prefer_initializing_formals

  final String verb;
  final String? _stored;

  /// الاسم في السحابة (قيد `medication_changes_kind_check`).
  String get stored => _stored ?? name;

  static MedicationChangeKind? fromStored(String? s) {
    for (final k in values) {
      if (k.stored == s) return k;
    }
    return null;
  }

  /// اللي المريض يقدر يرجّعه في ٢٤ ساعة. الصورة والقياس مالهمش رجوع
  /// (الصورة القديمة راحت، والقياس رقم اتقاس فعلاً).
  bool get undoable => switch (this) {
        MedicationChangeKind.photo || MedicationChangeKind.vital => false,
        _ => true,
      };
}

/// اللي بيتبعت للسيرفر: ملء الفورم عند الممرض بشكل يتخزّن ويتقرا من غير
/// Flutter ولا drift. المواعيد **مراسي أو ساعة** — الأب هو اللي بيحلّها
/// بروتينه هو لما يطبّقها (الممرض ما بيعرفش روتين المريض، وده الصح).
class MedicationChangePayload {
  const MedicationChangePayload({
    this.name,
    this.timings = const [],
    this.amountLabel,
    this.durationDays,
    this.purpose,
    this.instructions,
    this.alertMode,
    this.startDate,
    this.recordKind,
    this.happenedAt,
    this.doctor,
    this.place,
    this.notes,
    this.followKind,
    this.day,
    this.quantity,
    this.photoPath,
    this.weekdaysMask,
    this.everyDays,
    this.cycleOn,
    this.cycleOff,
    this.mealRelation,
    this.form,
    this.vitalKind,
    this.value,
    this.value2,
    this.pulse,
    this.measuredAt,
    this.warnDays,
    this.pharmacyName,
    this.pharmacyCall,
    this.pharmacyWhatsapp,
  });

  // ---- 0035
  /// نمط الأيام للساعات الجديدة (v29 خام — null كله = كل يوم).
  final int? weekdaysMask;
  final int? everyDays;
  final int? cycleOn;
  final int? cycleOff;

  /// كلمة الأكل (`MealRelation.storageName`).
  final String? mealRelation;

  /// نوع الدوا (`MedicineForm.wire`) — جوّه الـJSON، مفيش عمود ولا هجرة.
  final String? form;

  /// القياس: النوع بالاسم، الرقم (الانقباضي أو القيمة)، الانبساطي، النبض، والوقت.
  final String? vitalKind;
  final double? value;
  final double? value2;
  final int? pulse;
  final DateTime? measuredAt;

  /// المخزون: أيام التحذير (مع [quantity]).
  final int? warnDays;

  /// «صيدليتي».
  final String? pharmacyName;
  final String? pharmacyCall;
  final String? pharmacyWhatsapp;

  /// الكمية الجديدة — «علبة جديدة».
  final double? quantity;

  /// ٠٠٢٩: مسار الصورة المرفوعة في الباكت — `{patient}/med-photos/pending/…`.
  /// موبايل المريض **بيتحقق منه** قبل ما يلمسه.
  final String? photoPath;

  // ---- ورقة/ميعاد (٠٠٢٦)
  /// اسم نوع السجل المخزّن (`RecordKind.name`) — «ورقة».
  final String? recordKind;

  /// تاريخ الورقة.
  final DateTime? happenedAt;
  final String? doctor;
  final String? place;
  final String? notes;

  /// `visit` / `lab` — «ميعاد».
  final String? followKind;

  /// يوم الميعاد — الساعة بتيجي من صحيان المريض على موبايله.
  final DateTime? day;

  final String? name;
  final List<FixedTiming> timings;
  final String? amountLabel;
  final int? durationDays;
  final MedicationPurpose? purpose;
  final String? instructions;
  final AlertMode? alertMode;
  final DateTime? startDate;

  Map<String, Object?> toJson() => {
        'name': name,
        'timings': [
          for (final t in timings)
            {'kind': 'fixed', 'minute': t.minuteOfDay.minutes},
        ],
        'amount': amountLabel,
        'duration_days': durationDays,
        'purpose': purpose?.storageName,
        'instructions': instructions,
        'alert_mode': alertMode?.storageName,
        'start_date': _date(startDate),
        if (recordKind != null) 'record_kind': recordKind,
        if (happenedAt != null) 'happened_at': _date(happenedAt),
        if (doctor != null) 'doctor': doctor,
        if (place != null) 'place': place,
        if (notes != null) 'notes': notes,
        if (followKind != null) 'follow_kind': followKind,
        if (day != null) 'day': _date(day),
        if (quantity != null) 'quantity': quantity,
        if (photoPath != null) 'photo_path': photoPath,
        if (weekdaysMask != null) 'weekdays_mask': weekdaysMask,
        if (everyDays != null) 'every_days': everyDays,
        if (cycleOn != null) 'cycle_on': cycleOn,
        if (cycleOff != null) 'cycle_off': cycleOff,
        if (mealRelation != null) 'meal_relation': mealRelation,
        if (form != null) 'form': form,
        if (vitalKind != null) 'vital_kind': vitalKind,
        if (value != null) 'value': value,
        if (value2 != null) 'value2': value2,
        if (pulse != null) 'pulse': pulse,
        if (measuredAt != null) 'measured_at': measuredAt!.toUtc().toIso8601String(),
        if (warnDays != null) 'warn_days': warnDays,
        if (pharmacyName != null) 'pharmacy_name': pharmacyName,
        if (pharmacyCall != null) 'pharmacy_call': pharmacyCall,
        if (pharmacyWhatsapp != null) 'pharmacy_whatsapp': pharmacyWhatsapp,
      };

  static String? _date(DateTime? d) => d == null ? null : '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static MedicationChangePayload fromJson(Map<String, dynamic> json) {
    final timings = <FixedTiming>[];
    if (json['timings'] case final List<dynamic> list) {
      for (final t in list) {
        if (t is! Map) continue;
        // 'anchor' (تغييرات قديمة من قبل v30) بتتعدّى: مفيش روتين يحلّها
        if (t['kind'] == 'fixed') {
          final minute = t['minute'];
          if (minute is num && minute >= 0 && minute < 1440) timings.add(FixedTiming(MinuteOfDay(minute.toInt())));
        }
      }
    }
    final start = json['start_date'];
    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return MedicationChangePayload(
      recordKind: json['record_kind'] as String?,
      happenedAt: date(json['happened_at']),
      doctor: json['doctor'] as String?,
      place: json['place'] as String?,
      notes: json['notes'] as String?,
      followKind: json['follow_kind'] as String?,
      day: date(json['day']),
      quantity: (json['quantity'] as num?)?.toDouble(),
      photoPath: json['photo_path'] as String?,
      weekdaysMask: (json['weekdays_mask'] as num?)?.toInt(),
      everyDays: (json['every_days'] as num?)?.toInt(),
      cycleOn: (json['cycle_on'] as num?)?.toInt(),
      cycleOff: (json['cycle_off'] as num?)?.toInt(),
      mealRelation: json['meal_relation'] as String?,
      form: json['form'] as String?,
      vitalKind: json['vital_kind'] as String?,
      value: (json['value'] as num?)?.toDouble(),
      value2: (json['value2'] as num?)?.toDouble(),
      pulse: (json['pulse'] as num?)?.toInt(),
      measuredAt: json['measured_at'] is String ? DateTime.tryParse(json['measured_at'] as String)?.toLocal() : null,
      warnDays: (json['warn_days'] as num?)?.toInt(),
      pharmacyName: json['pharmacy_name'] as String?,
      pharmacyCall: json['pharmacy_call'] as String?,
      pharmacyWhatsapp: json['pharmacy_whatsapp'] as String?,
      name: json['name'] as String?,
      timings: timings,
      amountLabel: json['amount'] as String?,
      durationDays: json['duration_days'] is num ? (json['duration_days'] as num).toInt() : null,
      purpose: MedicationPurpose.fromStorage(json['purpose'] as String?),
      instructions: json['instructions'] as String?,
      alertMode: AlertMode.fromStorage(json['alert_mode'] as String?),
      startDate: start is String ? DateTime.tryParse(start) : null,
    );
  }
}

/// صف واحد من `medication_changes`.
class MedicationChange {
  const MedicationChange({
    required this.uuid,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.medicationUuid,
    this.medicationName,
    this.actorName,
    this.appliedAt,
    this.outcome,
  });

  /// 0035 — لقايمة «التعديلات»: إمتى اتطبّق وبإيه انتهى. null = لسه معلّق.
  final DateTime? appliedAt;
  final ChangeOutcome? outcome;

  final String uuid;
  final MedicationChangeKind kind;

  /// الدوا المقصود للإيقاف/تعديل الجرعة — null في الإضافة.
  final String? medicationUuid;

  /// اسمه وقت الاقتراح — للجملة عند الأب لو الدوا اتشال بعدها.
  final String? medicationName;
  final MedicationChangePayload payload;
  final String? actorName;
  final DateTime createdAt;
}

/// نتيجة التطبيق على موبايل الأب — بتتكتب على الصف في السحابة.
/// `reverted` (0035): اتطبّق وبعدين المريض داس «تراجع» في ٢٤ ساعة.
enum ChangeOutcome { applied, conflict, missing, reverted }

/// المدة اللي «تراجع» متاح فيها على «يومك».
const Duration changeUndoWindow = Duration(hours: 24);

/// «سارة ضافت دوا Concor» — الجملة على «يومك» بعد التطبيق. من غير اسم:
/// «حد بيتابعك».
String medicationChangeNotice(String? actorName, MedicationChangeKind kind, String medicationName) {
  final who = (actorName?.trim().isEmpty ?? true) ? 'حد بيتابعك' : actorName!.trim();
  return '$who ${kind.verb} $medicationName';
}

/// اللي الجملة بتتكلم عنه: اسم الدوا، أو عنوان الورقة، أو «زيارة/معمل
/// {الاسم}» للميعاد — عمره ما يقول «دوا» عن ميعاد.
String changeSubject(MedicationChange change) {
  final name = change.payload.name?.trim();
  switch (change.kind) {
    case MedicationChangeKind.appointment:
      final what = change.payload.followKind == 'lab' ? 'معمل' : 'زيارة';
      return name == null || name.isEmpty ? what : '$what $name';
    case MedicationChangeKind.record:
      return name == null || name.isEmpty ? 'ورقة' : name;
    case MedicationChangeKind.vital:
      return name == null || name.isEmpty ? 'قياس' : name;
    case MedicationChangeKind.pharmacy:
      final p = change.payload.pharmacyName?.trim();
      return (p == null || p.isEmpty) ? 'لصيدلية تانية' : 'لـ$p';
    case MedicationChangeKind.add ||
          MedicationChangeKind.stop ||
          MedicationChangeKind.amount ||
          MedicationChangeKind.restock ||
          MedicationChangeKind.photo ||
          MedicationChangeKind.bought ||
          MedicationChangeKind.timings ||
          MedicationChangeKind.remove ||
          MedicationChangeKind.resume ||
          MedicationChangeKind.stockSet:
      return (name == null || name.isEmpty) ? (change.medicationName ?? 'دوا') : name;
  }
}

/// تعديل الأب المحلي بيكسب: لو الدوا اتعدّل على الموبايل **بعد** ما الممرض
/// بعت التغيير، التغيير ما بيتطبّقش.
bool localEditWins({required DateTime localUpdatedAt, required DateTime changeCreatedAt}) =>
    localUpdatedAt.isAfter(changeCreatedAt);
