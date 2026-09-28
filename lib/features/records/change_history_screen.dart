import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/care_circle_service.dart' show CareCircleException;
import '../../data/care/medication_changes.dart';
import '../../domain/care/medication_change.dart';

/// **«التعديلات»** (0035) — مين غيّر إيه وإمتى، وإيه اللي حصل له: اتطبّق /
/// اترجع / لسه مستني موبايل المريض. المريض والممرض بيشوفوا نفس القايمة من
/// السحابة (RLS: الدايرة). قراية بس.
class ChangeHistoryScreen extends StatefulWidget {
  const ChangeHistoryScreen({required this.patientUuid, required this.remote, this.now, super.key});

  final String patientUuid;
  final MedicationChangeRemote remote;
  final DateTime? now;

  @override
  State<ChangeHistoryScreen> createState() => _ChangeHistoryScreenState();
}

class _ChangeHistoryScreenState extends State<ChangeHistoryScreen> {
  List<MedicationChange>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.remote.history(widget.patientUuid);
      if (mounted) setState(() => _rows = rows);
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نجيب التعديلات دلوقتي.');
    }
  }

  static String outcomeLine(MedicationChange c) {
    if (c.appliedAt == null) return 'مستني موبايل المريض';
    return switch (c.outcome) {
      ChangeOutcome.applied => 'اتطبّق ${arabicDate(c.appliedAt!)} ${arabicTime(c.appliedAt!)}',
      ChangeOutcome.reverted => 'المريض رجّعه',
      ChangeOutcome.conflict => 'ما اتطبّقش — المريض كان عدّل قبله',
      ChangeOutcome.missing => 'ما اتطبّقش — الدوا مش موجود',
      null => 'اتطبّق',
    };
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('التعديلات')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
          children: [
            if (_error case final e?) GoldNote(e),
            if (rows == null && _error == null)
              Padding(
                padding: const EdgeInsets.all(F.gap),
                child: Center(child: CircularProgressIndicator(color: F.green)),
              ),
            if (rows != null && rows.isEmpty)
              Text('مفيش تعديلات لسه.', key: const ValueKey('changes-empty'), style: TextStyle(fontSize: F.minBodySize, color: F.mutedDark, height: 1.5)),
            if (rows != null)
              for (final c in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: F.s10),
                  child: FCard(
                    key: ValueKey('change-${c.uuid}'),
                    padding: const EdgeInsets.all(F.s14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          medicationChangeNotice(c.actorName, c.kind, changeSubject(c)),
                          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.4),
                        ),
                        Text('${arabicDate(c.createdAt)} ${arabicTime(c.createdAt)}',
                            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                        Text(outcomeLine(c), style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4)),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
