import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/app_database.dart';
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
            // **اللي لسه مستنّي فوق، واللي حصل تحت** — والتقسيمة دي
            // مشتركة مع شاشة الابن حرفياً ([followSections]). نسختين
            // منها معناهم قايمتين يترتبوا بشكل مختلف على نفس الداتا.
            final sections = followSections<RecordRow>(
              shown,
              kindOf: CheckupService.kindOf,
              stageOf: CheckupService.stageOf,
              stageDateOf: _stageDate,
              newestFirst: (a, b) {
                final byDate = b.happenedAt.compareTo(a.happenedAt);
                return byDate != 0 ? byDate : b.id.compareTo(a.id);
              },
            );
            final waiting = sections.waiting;
            final done = sections.done;
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
                  FSectionHead(waitingSectionLabel(waiting.length)),
                  for (final r in waiting) RecordRowCard(record: r, today: now),
                  const SizedBox(height: F.s12),
                ],
                if (done.isNotEmpty) ...[
                  if (waiting.isNotEmpty) FSectionHead(doneSectionLabel(done.length)),
                  for (final r in done) RecordRowCard(record: r, today: now),
                ],
              ],
            );
          },
        ),
      );
}
