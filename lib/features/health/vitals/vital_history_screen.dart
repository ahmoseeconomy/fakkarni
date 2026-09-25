import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/vitals_repository.dart';
import '../../../domain/health/vitals.dart';
import 'vital_entry_sheet.dart';
import 'vital_history.dart';

/// شاشة نوع واحد عند المريض — من قاعدته، بتتحدّث لوحدها بعد أي قياس.
class VitalHistoryScreen extends StatefulWidget {
  const VitalHistoryScreen({required this.kind, this.now, super.key});

  final VitalKind kind;
  final DateTime? now;

  @override
  State<VitalHistoryScreen> createState() => _VitalHistoryScreenState();
}

class _VitalHistoryScreenState extends State<VitalHistoryScreen> {
  Stream<List<Vital>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    _stream ??= VitalsRepository(services.db).watch(services.patientId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.kind.label)),
        body: StreamBuilder<List<Vital>>(
          stream: _stream,
          builder: (context, snap) => ListView(
            padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: [
              VitalHistoryView(
                kind: widget.kind,
                vitals: snap.data ?? const [],
                now: widget.now ?? DateTime.now(),
                onAdd: () => showVitalEntrySheet(context, initial: widget.kind, now: widget.now),
              ),
            ],
          ),
        ),
      );
}
