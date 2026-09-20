import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.kind.plural)),
        body: StreamBuilder<List<RecordRow>>(
          stream: _records,
          builder: (context, snap) {
            final all = snap.data;
            if (all == null) return const SizedBox.shrink();
            final shown = [for (final r in all) if (r.kind == widget.kind) r];
            return ListView(
              padding: EdgeInsets.fromLTRB(
                F.gap,
                F.gap,
                F.gap,
                F.gap + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                if (shown.isEmpty)
                  const RecordsEmpty(how: 'اللي تسجّله هنا هتلاقيه في المكان ده.')
                else
                  for (final r in shown) RecordRowCard(record: r, today: widget.today),
              ],
            );
          },
        ),
      );
}
