// **تغيير دوا اقترحه ممرض** (المرحلة ب من تعليق المختبِر ٧) — دارت نقية.
//
// الممرض اللي الأب فتح له «يعدّل الأدوية» بيبعت تغيير **معلّق** للسيرفر؛
// موبايل الأب بيسحبه وبيطبّقه بنفس سكّة الإضافة/التعديل بتاعته، ويعيد
// الجدولة، ويقول «{اسم} ضاف دوا X». تعديل الأب المحلي بيكسب لو حصل بعد
// التغيير — والتعارض بيتسجّل مش بيتغطّى.

import '../escalation/alert_mode.dart';
import '../medication/medication_purpose.dart';
import '../scheduling/day_routine.dart';
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
  bought('علّم إنه اشترى');

  const MedicationChangeKind(this.verb);

  final String verb;

  static MedicationChangeKind? fromStored(String? s) => values.asNameMap()[s];
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
  });

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
  final List<DoseTiming> timings;
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
            switch (t) {
              AnchorTiming(:final anchor, :final offsetMinutes) => {'kind': 'anchor', 'anchor': anchor.name, 'offset': offsetMinutes},
              FixedTiming(:final minuteOfDay) => {'kind': 'fixed', 'minute': minuteOfDay.minutes},
            },
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
      };

  static String? _date(DateTime? d) => d == null ? null : '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static MedicationChangePayload fromJson(Map<String, dynamic> json) {
    final timings = <DoseTiming>[];
    if (json['timings'] case final List<dynamic> list) {
      for (final t in list) {
        if (t is! Map) continue;
        if (t['kind'] == 'anchor') {
          final anchor = DayAnchor.values.asNameMap()[t['anchor'] as String?];
          final offset = t['offset'];
          if (anchor != null && offset is num) timings.add(AnchorTiming(anchor, offset.toInt()));
        } else if (t['kind'] == 'fixed') {
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
  });

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
enum ChangeOutcome { applied, conflict, missing }

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
    case MedicationChangeKind.add || MedicationChangeKind.stop || MedicationChangeKind.amount || MedicationChangeKind.restock || MedicationChangeKind.photo || MedicationChangeKind.bought:
      return (name == null || name.isEmpty) ? (change.medicationName ?? 'دوا') : name;
  }
}

/// تعديل الأب المحلي بيكسب: لو الدوا اتعدّل على الموبايل **بعد** ما الممرض
/// بعت التغيير، التغيير ما بيتطبّقش.
bool localEditWins({required DateTime localUpdatedAt, required DateTime changeCreatedAt}) =>
    localUpdatedAt.isAfter(changeCreatedAt);
