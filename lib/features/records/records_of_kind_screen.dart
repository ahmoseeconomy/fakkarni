import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/app_database.dart';
import '../../core/format/arabic_time.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/tables.dart';
import '../../data/services/checkup_service.dart';
import '../../domain/health/follow_display.dart';
import '../../data/repositories/records_repository.dart';
import 'record_kinds.dart';
import 'record_row_card.dart';
import 'records_empty.dart';

/// قايمة نوع واحد — اللي مدخل «الملف الصحي» بيفتحه.
///
/// نفس صف السجل بتاع الملف بالظبط ([RecordRowCard])، فالمسح والصورة
/// والمتابعة كلهم شغّالين هنا زي ما كانوا هناك. مفيش فلاتر ولا بحث: إنت
/// اخترت النوع خلاص، والبحث في كل حاجة مكانه الملف نفسه.
class RecordsOfKindScreen extends StatefulWidget {
  const RecordsOfKindScreen({required this.kind, this.today, super.key});

  final RecordKind kind;

  /// للاختبارات.
  final DateTime? today;

  @override
  State<RecordsOfKindScreen> createState() => _RecordsOfKindScreenState();
}

class _RecordsOfKindScreenState extends State<RecordsOfKindScreen> {
  Stream<List<RecordRow>>? _records;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    _records ??= RecordsRepository(services.db).watchAll(services.patientId);
  }

  /// ميعاد المرحلة الحالية — مفتاح ترتيب «منتظر».
  static DateTime? _stageDate(RecordRow r) {
    final stage = CheckupService.stageOf(r);
    return stage == null ? null : CheckupService.stageDateOf(r, stage);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.kind.plural)),
        body: StreamBuilder<List<RecordRow>>(
          stream: _records,
          builder: (context, snap) {
            final all = snap.data;
            if (all == null) return const SizedBox.shrink();
            final now = widget.today ?? DateTime.now();
            final shown = [for (final r in all) if (r.kind == widget.kind) r];
            // **اللي لسه مستنّي فوق، واللي حصل تحت.** القايمة كانت مرتّبة
            // بتاريخ الورقة، فزيارة محجوزة بكرة كانت بتنزل تحت تقرير من
            // ٢٠٢٣ — الحاجة الوحيدة اللي محتاجة فعل بتختفي وسط الأرشيف.
            final waiting = [
              for (final r in shown)
                if (followIsOpen(CheckupService.kindOf(r), CheckupService.stageOf(r))) r,
            ]..sort((a, b) {
                final x = _stageDate(a), y = _stageDate(b);
                // من غير ميعاد بينزل آخر الخانة دي — لسه مفتوح، بس مفيش
                // رقم نرتّبه بيه، والسطر نفسه بيقول «لسه ما اتحددش ميعاد».
                if (x == null && y == null) return b.id.compareTo(a.id);
                if (x == null) return 1;
                if (y == null) return -1;
                return x.compareTo(y);
              });
            final waitingIds = {for (final r in waiting) r.id};
            final done = [for (final r in shown) if (!waitingIds.contains(r.id)) r];
            return ListView(
              padding: EdgeInsets.fromLTRB(
                F.gap,
                F.gap,
                F.gap,
                F.gap + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                if (shown.isEmpty)
                  const RecordsEmpty(how: 'اللي تسجّله هنا هتلاقيه في المكان ده.'),
                // قسم فاضي ما بيظهرش: غيابه هو «مفيش حاجة هنا».
                if (waiting.isNotEmpty) ...[
                  FSectionHead('منتظر (${arabicNumber(waiting.length)})'),
                  for (final r in waiting) RecordRowCard(record: r, today: now),
                  const SizedBox(height: F.s12),
                ],
                if (done.isNotEmpty) ...[
                  if (waiting.isNotEmpty) FSectionHead('تمت (${arabicNumber(done.length)})'),
                  for (final r in done) RecordRowCard(record: r, today: now),
                ],
              ],
            );
          },
        ),
      );
}
