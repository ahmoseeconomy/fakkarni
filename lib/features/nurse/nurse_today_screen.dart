import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import 'nurse_controller.dart';
import 'nurse_widgets.dart';

/// لوحة تشغيلية للممرض: المرضى، التنبيهات التصعيدية، والجرعات المفتوحة.
class NurseTodayScreen extends StatelessWidget {
  const NurseTodayScreen({required this.controller, this.now, super.key});

  final NurseController controller;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.holder]),
    builder: (context, _) {
      final holder = controller.holder;
      final snapshot = holder.snapshot;
      final t = now ?? DateTime.now();
      if (snapshot == null) {
        return Center(
          child: holder.loading
              ? CircularProgressIndicator(color: F.green)
              : NurseQuietLine(holder.error ?? 'لسه مفيش حاجة من موبايله.'),
        );
      }
      final overdue =
          snapshot.events
              .where(
                (e) =>
                    (e.state == 'pending' || e.state == 'missed') &&
                    e.scheduledAt.isBefore(t),
              )
              .toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      return RefreshIndicator(
        onRefresh: holder.refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            F.gap,
            F.s8,
            F.gap,
            F.gap + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            NurseFamilyNotice(patientName: snapshot.patient.name, now: t),
            if (holder.error case final e?) GoldNote(e),
            const Text(
              'المرضى الذين تتابعهم',
              key: ValueKey('nurse-patients-title'),
            ),
            for (final patient in holder.patients)
              TextButton(
                onPressed: () => holder.selectPatient(patient.uuid),
                child: Text(
                  '${patient.uuid == snapshot.patient.uuid ? '● ' : ''}${patient.name}',
                ),
              ),
            const SizedBox(height: F.s8),
            const Text(
              'تنبيهات التصعيد',
              key: ValueKey('nurse-escalations-title'),
            ),
            for (final alert in currentOpenCaregiverAlerts(
              snapshot,
            ).where((a) => a.rung == 'nurse'))
              Padding(
                padding: const EdgeInsets.only(top: F.s8),
                child: GoldNote(
                  '${alert.medicationName} — الجرعة ما اتأكدتش لسه.',
                  key: ValueKey('nurse-alert-${alert.uuid}'),
                ),
              ),
            const SizedBox(height: F.gap),
            const Text('جرعات متأخرة', key: ValueKey('nurse-overdue-title')),
            if (overdue.isEmpty)
              const NurseQuietLine('لا توجد جرعات متأخرة مفتوحة.'),
            for (final event in overdue)
              NurseDoseRow(
                event: event,
                now: t,
                proxied: snapshot.proxied.containsKey(event.uuid),
                busy: controller.busy.contains(event.uuid),
                onConfirm: controller.canConfirm
                    ? () => controller.confirm(event)
                    : null,
              ),
            if (controller.error case final error?)
              GoldNote(error, key: const ValueKey('nurse-error')),
          ],
        ),
      );
    },
  );
}
