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
  amount('عدّل جرعة');

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
  });

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
        'start_date': startDate == null ? null : '${startDate!.year}-${_two(startDate!.month)}-${_two(startDate!.day)}',
      };

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
    return MedicationChangePayload(
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

/// تعديل الأب المحلي بيكسب: لو الدوا اتعدّل على الموبايل **بعد** ما الممرض
/// بعت التغيير، التغيير ما بيتطبّقش.
bool localEditWins({required DateTime localUpdatedAt, required DateTime changeCreatedAt}) =>
    localUpdatedAt.isAfter(changeCreatedAt);
