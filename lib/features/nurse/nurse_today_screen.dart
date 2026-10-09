import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart' show arabicTime;
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/medication/medication_purpose.dart';
import '../adherence/adherence_card.dart';
import '../adherence/adherence_screen.dart';
import '../adherence/circle_adherence.dart';
import '../adherence/weekly_summary_card.dart';
import '../adherence/weekly_summary_sources.dart';
import '../care/caregiver_words.dart' show timeSince;
import '../medication/pharmacy_sheet.dart' show PharmacyPrefill;
import '../nearby/nearby_screen.dart';
import '../today/tips/tip_picker.dart';
import '../today/widgets/day_rail.dart';
import '../today/widgets/tip_card.dart';
import 'nurse_actions.dart';
import 'nurse_controller.dart';
import 'nurse_day_look.dart';
import 'nurse_widgets.dart';

/// «يومك» على موبايل الممرض: نفس الجرعة الجاية، ملخص الأسبوع، وسكة اليوم.
/// التحية ومؤشر الالتزام اليومي خاصّان بصاحب حساب المريض، فلا يظهران هنا.
class NurseTodayScreen extends StatelessWidget {
  const NurseTodayScreen({required this.controller, this.now, super.key});

  final NurseController controller;
  final DateTime? now;

  /// نفس «معلومة تهمك» التي يراها المريض، محسوبة من صورة المريض السحابية.
  static Tip tipFor(CaregiverSnapshot snapshot, DateTime now) => pickTip(
    today: now,
    medications: [
      for (final (i, medication) in snapshot.medications.indexed)
        TipMedication(
          id: i,
          name: medication.name,
          purpose: MedicationPurpose.fromStorage(medication.purpose),
          instructions: medication.instructions,
        ),
    ],
    lastWeek: [
      for (final event in snapshot.events)
        if (event.scheduledAt.isBefore(now))
          TipDose(
            scheduledAt: event.scheduledAt,
            taken: event.state == 'taken',
            missed: event.state == 'missed' || event.state == 'pending',
            actedAt: event.actedAt,
          ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.holder]),
    builder: (context, _) {
      final holder = controller.holder;
      final snapshot = holder.snapshot;
      final time = now ?? DateTime.now();
      if (snapshot == null) {
        return Center(
          child: holder.loading
              ? CircularProgressIndicator(color: F.green)
              : Padding(
                  padding: const EdgeInsets.all(F.gap),
                  child: NurseQuietLine(
                    holder.error ?? 'لسه مفيش حاجة من موبايله.',
                  ),
                ),
        );
      }

      final todayRows = nurseTodayDoses(snapshot, time);
      final split = nurseDaySplit(
        [for (final row in todayRows) row.view],
        time,
      );
      final openAlerts = currentOpenCaregiverAlerts(
        snapshot,
      ).where((alert) => alert.rung == 'nurse');

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
            NurseFamilyNotice(patientName: snapshot.patient.name, now: time),
            if (controller.error case final error?) ...[
              GoldNote(error, key: const ValueKey('nurse-error')),
              const SizedBox(height: F.s10),
            ],
            if (holder.error case final error?) ...[
              GoldNote(error),
              const SizedBox(height: F.s10),
            ],
            if (!snapshot.patient.permissions.canConfirm)
              const NurseQuietLine(
                'بتشوف يومه بس — التأكيد بداله محتاج المريض يسمح بيه من موبايله.',
                key: ValueKey('nurse-read-only'),
              ),
            for (final alert in openAlerts)
              Padding(
                padding: const EdgeInsets.only(bottom: F.s10),
                child: GoldNote(
                  '${alert.medicationName} — معادها ${arabicTime(alert.scheduledAt)} وما اتأكدتش لسه. لو أخدها، أكّدها تحت.',
                  key: ValueKey('nurse-alert-${alert.uuid}'),
                ),
              ),
            SnapshotWeeklySummary(
              key: ValueKey('nurse-summary-${snapshot.patient.uuid}'),
              today: time,
              summaryFor: (range) => summaryFromSnapshot(
                snapshot,
                time,
                from: range.from,
                to: range.to,
              ),
            ),
            const SizedBox(height: F.gap),
            if (split.card.isNotEmpty) ...[
              NurseNowCard(
                groups: split.card,
                events: todayRows,
                now: time,
                canConfirm: controller.canConfirm,
                proxied: snapshot.proxied.keys.toSet(),
                busy: controller.busy,
                onConfirm: controller.confirm,
              ),
              const SizedBox(height: F.s12),
            ],
            if (todayRows.isEmpty) ...[
              const NurseQuietLine('مفيش أدوية النهارده'),
              const SizedBox(height: F.gap),
            ],
            if (circleAdherence(snapshot, time) case final adherence?) ...[
              AdherenceCard(
                adherence: adherence,
                title: circleAdherenceTitle,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdherenceDetailScreen(
                      initial: adherence,
                      title: circleAdherenceTitle,
                      missedTitle: 'فاته كام جرعة الأسبوع ده',
                      updates: circleAdherenceUpdates(
                        holder,
                        () => holder.snapshot,
                      ),
                      onLateTake: controller.canConfirm
                          ? (missed) async {
                              final event = holder.snapshot?.events
                                  .where((item) => item.uuid == missed.id)
                                  .firstOrNull;
                              if (event != null) {
                                await controller.confirm(event);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: F.s12),
            ],
            if (split.rest.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.format_list_bulleted, size: 26, color: F.green),
                  const SizedBox(width: F.s8),
                  Text(
                    'باقي اليوم',
                    key: const ValueKey('nurse-rest-title'),
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.subtitleSize,
                      fontWeight: FontWeight.w800,
                      color: F.ink,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: F.s4),
              DayRail(groups: split.rest, now: time, ruleLabelFor: (_) => null),
            ],
            const SizedBox(height: F.gap),
            FSecondaryButton(
              key: const ValueKey('nurse-nearby'),
              label: 'القريب مني',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (nearbyContext) => NearbyScreen(
                    onBookPlace: controller.canEdit
                        ? (place) => bookFromNearby(
                            nearbyContext,
                            controller,
                            place,
                          )
                        : null,
                    onPickPharmacy: controller.canEdit
                        ? (place) async {
                            Navigator.of(nearbyContext).pop();
                            await editPatientPharmacy(
                              context,
                              controller,
                              prefill: PharmacyPrefill.fromPlace(place),
                            );
                          }
                        : null,
                  ),
                ),
              ),
            ),
            if (controller.lastLine case final line?) ...[
              const SizedBox(height: F.s8),
              NurseQuietLine(line, key: const ValueKey('nurse-last-line')),
            ],
            const SizedBox(height: F.gap),
            TipCard(tip: tipFor(snapshot, time)),
            if (snapshot.lastUpdated case final updatedAt?) ...[
              const SizedBox(height: F.s12),
              NurseQuietLine(
                'آخر تحديث من موبايله ${timeSince(time, updatedAt)}',
              ),
            ],
          ],
        ),
      );
    },
  );
}
