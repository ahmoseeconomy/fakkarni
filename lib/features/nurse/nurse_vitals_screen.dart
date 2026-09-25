import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/health/vitals.dart';
import '../care/caregiver_snapshot_holder.dart';
import '../health/vitals/vital_history.dart';
import 'nurse_header.dart';

/// تاريخ نوع قياس واحد للمريض — عند الممرض، **قراية بس**: القياس بيتسجّل
/// على موبايل المريض (مفيش طلب معلّق للقياسات — الرقم بيطلع من الجهاز
/// اللي في إيد المريض).
class NurseVitalsScreen extends StatelessWidget {
  const NurseVitalsScreen({required this.holder, required this.kind, this.now, super.key});

  final CaregiverSnapshotHolder holder;
  final VitalKind kind;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: NurseHeader(holder: holder),
        body: ListenableBuilder(
          listenable: holder,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(F.gap),
            children: [
              NurseScreenTitle(kind.label),
              VitalHistoryView(kind: kind, vitals: holder.snapshot?.vitals ?? const [], now: now ?? DateTime.now()),
            ],
          ),
        ),
      );
}
