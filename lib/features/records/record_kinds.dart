import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';

/// كلمة كل نوع — المفرد للاستمارة والصف، والجمع لشرايح الفلتر.
extension RecordKindWords on RecordKind {
  String get label => switch (this) {
        RecordKind.imaging => 'أشعة',
        RecordKind.visit => 'زيارة',
        RecordKind.lab => 'تحليل',
        RecordKind.prescription => 'روشتة',
        RecordKind.booking => 'حجز',
      };

  String get plural => switch (this) {
        RecordKind.imaging => 'أشعة',
        RecordKind.visit => 'زيارات',
        RecordKind.lab => 'تحاليل',
        RecordKind.prescription => 'روشتات',
        RecordKind.booking => 'حجوزات',
      };

  IconData get icon => switch (this) {
        RecordKind.imaging => Icons.monitor_heart_outlined,
        RecordKind.visit => Icons.local_hospital_outlined,
        RecordKind.lab => Icons.science_outlined,
        RecordKind.prescription => Icons.receipt_long_outlined,
        RecordKind.booking => Icons.event_outlined,
      };
}

/// الفترة في «الحالات السابقة».
enum RecordPeriod { month, threeMonths, year, all }

extension RecordPeriodWords on RecordPeriod {
  String get label => switch (this) {
        RecordPeriod.month => 'شهر',
        RecordPeriod.threeMonths => '٣ شهور',
        RecordPeriod.year => 'سنة',
        RecordPeriod.all => 'الكل',
      };

  /// من [now] لورا المدة دي — والحجوزات الجاية (بعد النهارده) جوّه دايماً.
  /// التقويم بالـconstructor مش Duration (التوقيت الصيفي).
  bool includes(DateTime at, DateTime now) {
    final from = switch (this) {
      RecordPeriod.month => DateTime(now.year, now.month - 1, now.day),
      RecordPeriod.threeMonths => DateTime(now.year, now.month - 3, now.day),
      RecordPeriod.year => DateTime(now.year - 1, now.month, now.day),
      RecordPeriod.all => null,
    };
    return from == null || !at.isBefore(from);
  }
}

String _western(String s) => s.replaceAllMapped(
      RegExp('[٠-٩]'),
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x660 + 0x30),
    );

/// البحث في «الملف الصحي»: الاسم، الدكتور، المكان، الملاحظات، والتاريخ —
/// بالأرقام العربي أو الإنجليزي («٢٨ أغسطس» أو «2026» أو «28/8»).
bool matchesQuery(RecordRow r, String query) {
  final q = _western(query.trim().toLowerCase());
  if (q.isEmpty) return true;
  final d = r.happenedAt;
  final haystack = [
    r.title,
    r.doctor ?? '',
    r.place ?? '',
    r.notes ?? '',
    r.kind.label,
    _western(arabicDate(d)),
    '${d.day}/${d.month}/${d.year}',
  ].map((s) => _western(s.toLowerCase())).join('\n');
  return haystack.contains(q);
}
