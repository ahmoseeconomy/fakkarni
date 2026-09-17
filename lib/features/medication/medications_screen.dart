import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/medication_repository.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../../core/widgets/primitives.dart';
import '../nearby/nearby_screen.dart';
import 'edit_medication_screen.dart';

/// تبويب «الأدوية» (المخطط 09): الأدوية مجمّعة بالمرساة.
///
/// عنوان كل مجموعة المرساة ووقتها المحسوب من روتين الأب (ده جهازه — هو
/// الجدول الوحيد)، وتحتها كارت لكل جرعة: الاسم mono، الجرعة أو «الجرعة مش
/// معروفة» بهدوء، القاعدة، و«عدّل». الدوا الموقوف بيفضل باين في قسم
/// «موقوفة» رمادي — **ما يختفيش**، نفس مبدأ الجرعة المأخوذة في السكة.
/// مفيش زرار صوت: الإضافة من «ضيف» في الشريط السفلي.
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({this.today, super.key});

  /// للاختبارات — يوم حساب الأوقات.
  final DateTime? today;

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  Stream<List<MedicationSummary>>? _all;
  Stream<DayRoutine?>? _routine;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_all != null) return;
    final services = AppScope.of(context);
    _all = services.medications.watchAllSummaries(services.patientId);
    _routine = services.routines.watchRoutine(services.patientId);
  }

  void _edit(int medicationId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EditMedicationScreen(medicationId: medicationId),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DayRoutine?>(
      stream: _routine,
      builder: (context, routineSnap) {
        final routine = routineSnap.data ?? DayRoutine.fallback;
        return StreamBuilder<List<MedicationSummary>>(
          stream: _all,
          builder: (context, snap) {
            final all = snap.data ?? const <MedicationSummary>[];
            final active = [for (final m in all) if (m.medication.stoppedAt == null) m];
            final stopped = [for (final m in all) if (m.medication.stoppedAt != null) m];
            final groups = _groupByAnchor(active, routine, widget.today ?? DateTime.now());

            return ListView(
              padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s30 * 2),
              children: [
                Text(
                  'جدول الأدوية',
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.screenTitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                const SizedBox(height: F.s4),
                Text(
                  active.isEmpty
                      ? 'لسه مفيش أدوية. دوس «ضيف» تحت.'
                      : '${_count(active.length)} — مرتّبة على مواعيد يومك',
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                ),
                const SizedBox(height: F.s10),
                FSecondaryButton(
                  label: 'صيدليات ودكاترة قريب منك',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const NearbyScreen()),
                  ),
                ),
                for (final group in groups) ...[
                  const SizedBox(height: F.gap),
                  _GroupHead(label: group.label, time: group.time),
                  const SizedBox(height: F.s8),
                  for (final entry in group.entries) ...[
                    _MedCard(
                      summary: entry.summary,
                      schedule: entry.schedule,
                      onEdit: () => _edit(entry.summary.medication.id),
                    ),
                    const SizedBox(height: F.s8),
                  ],
                ],
                if (stopped.isNotEmpty) ...[
                  const SizedBox(height: F.gap),
                  const _GroupHead(label: 'موقوفة', time: null, muted: true),
                  const SizedBox(height: F.s8),
                  for (final m in stopped) ...[
                    _MedCard(summary: m, schedule: null, onEdit: () => _edit(m.medication.id), stopped: true),
                    const SizedBox(height: F.s8),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }

  static String _count(int n) => switch (n) {
        1 => 'دوا واحد',
        2 => 'دواءين',
        _ when n <= 10 => '${arabicNumber(n)} أدوية',
        _ => '${arabicNumber(n)} دوا',
      };

  /// كل جرعة تحت مرساتها (الدوا اللي بياخده ٣ مرات بيظهر ٣ مرات — ده جدول).
  /// الساعات الثابتة في مجموعة «ساعة ثابتة» في الآخر. الترتيب بالوقت.
  static List<_Group> _groupByAnchor(List<MedicationSummary> items, DayRoutine routine, DateTime today) {
    final engine = ScheduleEngine(routine);
    final byKey = <String, _Group>{};
    for (final m in items) {
      for (final s in m.schedules) {
        final (key, label, at) = switch (s.timing) {
          AnchorTiming(:final anchor) => (
              anchor.name,
              anchor.label,
              engine.resolveTime(anchor: anchor, offsetMinutes: 0, onDay: today),
            ),
          FixedTiming() => ('fixed', 'ساعة ثابتة', null),
        };
        byKey.putIfAbsent(key, () => _Group(label, at)).entries.add((summary: m, schedule: s));
      }
    }
    final groups = byKey.values.toList()
      ..sort((a, b) {
        if (a.time == null) return 1;
        if (b.time == null) return -1;
        return a.time!.compareTo(b.time!);
      });
    return groups;
  }
}

class _Group {
  _Group(this.label, this.time);
  final String label;
  final DateTime? time;
  final List<({MedicationSummary summary, DoseSchedule schedule})> entries = [];
}

/// عنوان مجموعة: المرساة · الوقت، وخط على الجنب زي التصميم.
class _GroupHead extends StatelessWidget {
  const _GroupHead({required this.label, required this.time, this.muted = false});

  final String label;
  final DateTime? time;
  final bool muted;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: Text(
            time == null ? label : '$label — ${arabicTime(time!)}',
            style: TextStyle(
              fontSize: F.sectionHeadSize,
              fontWeight: FontWeight.w700,
              color: muted ? F.mutedDark : F.green,
            ),
          ),
          ),
          const SizedBox(width: F.s10),
          Expanded(child: Container(height: 1, color: F.line)),
        ],
      );
}

/// كارت دوا: الاسم mono ٢٤+، الجرعة والقاعدة، و«عدّل». الموقوف رمادي.
class _MedCard extends StatelessWidget {
  const _MedCard({
    required this.summary,
    required this.schedule,
    required this.onEdit,
    this.stopped = false,
  });

  final MedicationSummary summary;

  /// الجرعة اللي الكارت بيمثّلها في مجموعته — null للموقوف (كل جداوله).
  final DoseSchedule? schedule;
  final VoidCallback onEdit;
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final med = summary.medication;
    final rule = schedule?.ruleLabel ?? summary.schedules.map((s) => s.ruleLabel).join(' + ');
    return Container(
      padding: const EdgeInsets.all(F.s14),
      decoration: BoxDecoration(
        color: stopped ? F.railGround : F.cardGround,
        borderRadius: BorderRadius.circular(F.radiusCard),
        border: Border.all(color: F.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    med.name,
                    textDirection: nameDirection(med.name),
                    style: TextStyle(
                      fontSize: F.medicationNameSize,
                      fontWeight: FontWeight.w700,
                      color: stopped ? F.mutedDark : F.ink,
                      fontFamily: F.monoFamily,
                      fontFamilyFallback: F.monoFallback,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: F.s4),
                Text(
                  // الجرعة مش معروفة — بهدوء، من غير لوم: سؤال للصيدلي مش غلطة
                  '${med.amountLabel ?? 'الجرعة مش معروفة'} — $rule',
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                ),
                if (stopped)
                  Padding(
                    padding: EdgeInsets.only(top: F.s4),
                    child: Text(
                      'موقوف — التذكيرات واقفة',
                      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: F.s8),
          SizedBox(
            height: F.minTapTarget,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: F.ink,
                minimumSize: const Size(0, F.minTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: F.s12),
                side: BorderSide(color: F.line, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusTile)),
              ),
              icon: const Icon(Icons.edit_outlined, size: 22),
              label: const Text('عدّل', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
