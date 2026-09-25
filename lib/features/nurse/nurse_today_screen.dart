import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/medication/medication_purpose.dart';
import '../care/caregiver_status.dart';
import '../care/caregiver_words.dart' show timeSince;
import '../adherence/adherence_card.dart';
import '../adherence/adherence_screen.dart';
import '../adherence/circle_adherence.dart';
import '../today/tips/tip_picker.dart';
import '../today/widgets/tip_card.dart';
import 'nurse_controller.dart';
import 'nurse_widgets.dart';

/// **«يومك» بتاع المريض على موبايل الممرض** — «الآن» وجدول النهارده
/// و«معلومة تهمك»، بمقاسات تطبيق المريض نفسه.
///
/// الأوقات هي اللي موبايل المريض حسبها (`dose_events.scheduled_at`) —
/// **الممرض ما بيحلّش مراسي**: جدول واحد في المنتج، على موبايل المريض.
class NurseTodayScreen extends StatelessWidget {
  const NurseTodayScreen({required this.controller, this.now, super.key});

  final NurseController controller;
  final DateTime? now;

  /// المعلومة نفسها اللي المريض شايفها النهارده — نفس الاختيار، من نفس
  /// البيانات اللي موبايله رفعها.
  static Tip tipFor(CaregiverSnapshot snapshot, DateTime now) => pickTip(
        today: now,
        medications: [
          for (final (i, m) in snapshot.medications.indexed)
            TipMedication(
              id: i,
              name: m.name,
              purpose: MedicationPurpose.fromStorage(m.purpose),
              instructions: m.instructions,
            ),
        ],
        lastWeek: [
          for (final e in snapshot.events)
            if (e.scheduledAt.isBefore(now))
              TipDose(
                scheduledAt: e.scheduledAt,
                taken: e.state == 'taken',
                missed: e.state == 'missed' || e.state == 'pending',
                actedAt: e.actedAt,
              ),
        ],
      );

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
                  : Padding(
                      padding: const EdgeInsets.all(F.gap),
                      child: NurseQuietLine(holder.error ?? 'لسه مفيش حاجة من موبايله.'),
                    ),
            );
          }
          final s = careDoseSections(snapshot, t);
          final nowEvent = s.missed.isNotEmpty ? s.missed.first : s.upcomingToday.firstOrNull;
          final day = [...s.missed, ...s.upcomingToday, ...s.taken, ...s.skipped]
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

          Widget row(CaregiverDoseEvent e, {bool big = false}) => NurseDoseRow(
                event: e,
                now: t,
                big: big,
                proxied: snapshot.proxied.containsKey(e.uuid),
                busy: controller.busy.contains(e.uuid),
                onConfirm: controller.canConfirm ? () => controller.confirm(e) : null,
              );

          return RefreshIndicator(
            onRefresh: holder.refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
              children: [
                NurseFamilyNotice(patientName: snapshot.patient.name, now: t),
                if (controller.error case final e?) ...[
                  GoldNote(e, key: const ValueKey('nurse-error')),
                  const SizedBox(height: F.s10),
                ],
                if (holder.error case final e?) ...[
                  GoldNote(e),
                  const SizedBox(height: F.s10),
                ],
                if (!snapshot.patient.permissions.canConfirm)
                  const NurseQuietLine('بتشوف يومه بس — التأكيد بداله محتاج المريض يسمح بيه من موبايله.',
                      key: ValueKey('nurse-read-only')),
                const FSectionHead('الآن'),
                const SizedBox(height: F.s8),
                if (nowEvent == null)
                  const NurseQuietLine('مفيش جرعة دلوقتي — كل حاجة في وقتها.')
                else
                  row(nowEvent, big: true),
                const SizedBox(height: F.s12),
                // «ماشي إزاي» — تحت «الآن»، قراية. «أخدتها متأخر» جوّه
                // التفاصيل بس لو التأكيد مسموح، وعلى نفس سكّة التأكيد نيابةً.
                if (circleAdherence(snapshot, t) case final a?) ...[
                  AdherenceCard(
                    adherence: a,
                    title: circleAdherenceTitle,
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => AdherenceDetailScreen(
                        initial: a,
                        title: circleAdherenceTitle,
                        missedTitle: 'فاته كام جرعة الأسبوع ده',
                        updates: circleAdherenceUpdates(holder, () => holder.snapshot),
                        onLateTake: controller.canConfirm
                            ? (m) async {
                                final e = holder.snapshot?.events.where((x) => x.uuid == m.id).firstOrNull;
                                if (e != null) await controller.confirm(e);
                              }
                            : null,
                      ),
                    )),
                  ),
                  const SizedBox(height: F.s12),
                ],
                const FSectionHead('جدول النهارده'),
                const SizedBox(height: F.s8),
                if (day.isEmpty)
                  const NurseQuietLine('مفيش جرعات متسجّلة النهارده لسه.')
                else
                  for (final e in day) row(e),
                const SizedBox(height: F.gap),
                TipCard(tip: tipFor(snapshot, t)),
                if (snapshot.lastUpdated case final at?) ...[
                  const SizedBox(height: F.s12),
                  NurseQuietLine('آخر تحديث من موبايله ${timeSince(t, at)}'),
                ],
              ],
            ),
          );
        },
      );
}
