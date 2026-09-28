/// «تراجع» على تغيير جاي من ممرض (0035) — اللي «يومك» بتعرضه وتخزّنه.
///
/// كل تغيير اتطبّق بيسيب هنا اللي محتاجينه عشان نرجّعه في ٢٤ ساعة:
/// نوعه، الدوا (بالرقم المحلي)، واللي كان قبله. الرجوع نفسه في
/// [MedicationChangePuller.undo] وبيعدّي على `MedicationSaveService` زي أي
/// كتابة — فالتذكيرات بتتلغي بالجدولة، مش بإيدينا.
library;

import 'dart:convert';

import '../../domain/care/medication_change.dart';

/// جملة على «يومك»: «سارة ضافت دوا Concor — ٨ الصبح و٨ بالليل»، ومعاها
/// «تراجع» لو لسه في وقته.
class ChangeNotice {
  const ChangeNotice({
    required this.uuid,
    required this.line,
    this.kind,
    this.appliedAt,
    this.medicationId,
    this.previous = const {},
    this.recordId,
  });

  /// uuid التغيير في السحابة — أو رقم محلي لجملة من غير رجوع («خرج من الدايرة»).
  final String uuid;
  final String line;
  final MedicationChangeKind? kind;
  final DateTime? appliedAt;

  /// الدوا المحلي اللي اتغيّر (للرجوع).
  final int? medicationId;

  /// الورقة/الميعاد اللي اتعمل (للرجوع بالمسح).
  final int? recordId;

  /// اللي كان قبل التغيير — بحسب النوع: `amount`, `quantity`, `warn_days`,
  /// `pharmacy_*`, `stopped_schedule_ids`, `added_schedule_ids`, `not_bought`.
  final Map<String, Object?> previous;

  bool canUndoAt(DateTime now) {
    final k = kind;
    final at = appliedAt;
    if (k == null || at == null || !k.undoable) return false;
    return now.difference(at) < changeUndoWindow;
  }

  Map<String, Object?> toJson() => {
        'uuid': uuid,
        'line': line,
        if (kind != null) 'kind': kind!.stored,
        if (appliedAt != null) 'applied_at_ms': appliedAt!.millisecondsSinceEpoch,
        if (medicationId != null) 'medication_id': medicationId,
        if (recordId != null) 'record_id': recordId,
        if (previous.isNotEmpty) 'previous': previous,
      };

  static ChangeNotice? fromJson(Object? json) {
    if (json is! Map) return null;
    final uuid = json['uuid'];
    final line = json['line'];
    if (uuid is! String || line is! String) return null;
    final ms = json['applied_at_ms'];
    return ChangeNotice(
      uuid: uuid,
      line: line,
      kind: MedicationChangeKind.fromStored(json['kind'] as String?),
      appliedAt: ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
      medicationId: (json['medication_id'] as num?)?.toInt(),
      recordId: (json['record_id'] as num?)?.toInt(),
      previous: (json['previous'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  static String encodeList(List<ChangeNotice> list) => jsonEncode([for (final n in list) n.toJson()]);

  static List<ChangeNotice> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final json = jsonDecode(raw);
      if (json is! List) return const [];
      return [for (final e in json) ?fromJson(e)];
    } catch (_) {
      return const [];
    }
  }
}
