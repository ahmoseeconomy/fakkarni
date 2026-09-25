import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/health/vitals.dart';
import '../health/vitals/vital_history.dart';
import 'caregiver_snapshot_holder.dart';
import 'caregiver_ui.dart';

/// **قياسات المريض عند عيلته — قراية بس.** آخر رقم لكل نوع، والدوسة
/// بتفتح تاريخه (نفس ودجت المريض من غير «سجّل قياس»). بتسمع لنفس الصورة
/// الحيّة، فالسؤال الدوري بيحدّثها وهي مفتوحة.
class CaregiverVitalsScreen extends StatelessWidget {
  const CaregiverVitalsScreen({required this.holder, this.now, this.kind, super.key});

  final CaregiverSnapshotHolder holder;
  final DateTime? now;

  /// null = الملخص؛ غير كده تاريخ النوع ده.
  final VitalKind? kind;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: careAppBar(kind?.label ?? 'القياسات'),
        body: ListenableBuilder(
          listenable: holder,
          builder: (context, _) {
            final vitals = holder.snapshot?.vitals ?? const <Vital>[];
            final t = now ?? DateTime.now();
            final k = kind;
            return ListView(
              padding: EdgeInsets.fromLTRB(F.carePad, F.careRowGap, F.carePad, F.carePad + MediaQuery.of(context).padding.bottom),
              children: [
                if (k == null)
                  VitalsSummary(
                    vitals: vitals,
                    onOpen: (kind) => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => CaregiverVitalsScreen(holder: holder, now: now, kind: kind),
                    )),
                  )
                else
                  VitalHistoryView(kind: k, vitals: vitals, now: t),
              ],
            );
          },
        ),
      );
}
