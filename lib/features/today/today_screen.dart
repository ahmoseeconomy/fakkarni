import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/repositories/readings_repository.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../medication/edit_medication_screen.dart';
import '../health/glucose_screen.dart';
import '../reminder/reminder_screen.dart';
import 'dose_actions.dart';
import 'widgets/day_rail.dart';
import 'widgets/glucose_home_card.dart';
import 'widgets/now_card.dart';
import 'widgets/water_widget.dart';

/// «جدول النهاردة» (المخطط 24) — الجرعة الجاية مثبّتة فوق، وباقي اليوم
/// تحتها على سكة. العنوان في جسم الصفحة — الشريط العلوي للهيكل ([AppShell]).
class TodayScreen extends StatefulWidget {
  const TodayScreen({required this.routine, this.now, super.key});

  final DayRoutine routine;

  /// للاختبارات — الشاشة بتستخدم دلوقتي الحقيقي في التطبيق.
  final DateTime? now;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  StreamSubscription<List<DoseSchedule>>? _schedulesSub;
  List<DoseSchedule> _schedules = const [];

  /// البث بيتعمل مرة واحدة هنا مش جوّه build.
  ///
  /// لو اتعمل جوّه build، كل إشعار من البث بيعيد البناء، وإعادة البناء
  /// بتعمل بث جديد بيبعت إشعار تاني — لفة مالهاش آخر.
  Stream<List<DoseEventView>>? _events;

  /// جرعات بكرة — «خلال ٤٨ ساعة».
  Stream<List<DoseEventView>>? _tomorrow;

  /// الاسم والسن للترحيب.
  Stream<PatientRow?>? _patient;

  /// مجموعات اتأجّلت من الشاشة دي — بنقول «هنفكّرك تاني» تحتها.
  final Set<DateTime> _snoozed = {};

  /// الأدوية اللي جرعتها مش معروفة — سؤال هادي للصيدلي، مش تنبيه.
  Stream<List<MedicationRow>>? _amountUnknown;

  /// قياسات السكر (D3.6) — لكارت السكر.
  StreamSubscription<List<ReadingRow>>? _readingsSub;
  List<ReadingRow> _readings = const [];

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _routineDay => currentRoutineDay(widget.routine, _now);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_events != null) return;

    final services = AppScope.of(context);
    _events = services.events.watchDay(_routineDay);
    _tomorrow = services.events.watchDay(
      DateTime(_routineDay.year, _routineDay.month, _routineDay.day + 1),
    );
    _patient = services.routines.watchPatient(services.patientId);
    _amountUnknown = services.medications.watchAmountUnknown(services.patientId);
    _readingsSub = ReadingsRepository(services.db).watchRecent(services.patientId).listen((rows) {
      if (mounted) setState(() => _readings = rows);
    });

    // أول ما الأدوية تتغيّر بنولّد أحداث اليوم من جديد — الإضافة بتظهر
    // فوراً، والإيقاف بيختفي، من غير ما حد يعمل refresh.
    _schedulesSub = services.medications
        .watchActiveSchedules(services.patientId)
        .listen(_onSchedules);
  }

  Future<void> _onSchedules(List<DoseSchedule> schedules) async {
    if (!mounted) return;
    setState(() => _schedules = schedules);

    final services = AppScope.of(context);
    final engine = ScheduleEngine(widget.routine);
    await services.events.materializeDay(
      _routineDay,
      engine.remindersForDay(schedules, _routineDay),
    );
    // «خلال ٤٨ ساعة» بتقرا صفوف بكرة — rescheduleAll بينزّلها أصلاً، وده
    // idempotent لو الشاشة اتفتحت قبله.
    final tomorrow = DateTime(_routineDay.year, _routineDay.month, _routineDay.day + 1);
    await services.events.materializeDay(tomorrow, engine.remindersForDay(schedules, tomorrow));
  }

  @override
  void didUpdateWidget(TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // الروتين اتغيّر → ساعات اليوم بتتحرك، فبنعيد التوليد.
    if (oldWidget.routine != widget.routine) {
      unawaited(_onSchedules(_schedules));
    }
  }

  @override
  void dispose() {
    _schedulesSub?.cancel();
    _readingsSub?.cancel();
    super.dispose();
  }

  Future<void> _markTaken(List<DoseEventView> group) =>
      confirmGroup(AppScope.of(context), _routineDay, group);

  /// «لاحقًا» = التأجيل الحقيقي (ربع ساعة)، نفس «تأجيل ١٥ د» في شاشة التذكير.
  Future<void> _later(List<DoseEventView> group) async {
    await snoozeGroup(AppScope.of(context), _routineDay, group, now: _now);
    if (mounted) setState(() => _snoozed.add(group.first.scheduledAt));
  }

  void _openEdit(int medicationId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EditMedicationScreen(medicationId: medicationId),
        ),
      );

  String? _ruleLabelFor(int doseScheduleId) {
    for (final schedule in _schedules) {
      if (schedule.id == doseScheduleId.toString()) return schedule.ruleLabel;
    }
    return null;
  }

  List<AnchorMark> get _anchors {
    final engine = ScheduleEngine(widget.routine);
    return [
      for (final anchor in DayAnchor.values)
        AnchorMark(
          anchor,
          engine.resolveTime(
            anchor: anchor,
            offsetMinutes: 0,
            onDay: _routineDay,
          ),
        ),
    ];
  }

  void _openGlucose() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GlucoseScreen()),
      );

  List<List<DoseEventView>> _group(List<DoseEventView> events) => groupByMinute(events);

  /// الدوسة على كارت في السكة بتفتح شاشة التذكير بتاعته — أخدته / فكّرني /
  /// مش هاخده — بدل زرار أساسي على كل كارت.
  void _openReminder(List<DoseEventView> group) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReminderScreen(
            routineDay: _routineDay,
            scheduleIds: [for (final d in group) d.doseScheduleId.toString()],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Scaffold جوّه تبويب الهيكل: الأرضية، وMaterial للـInkWell لما الشاشة
    // تتبني لوحدها في الاختبار.
    return Scaffold(
      body: StreamBuilder<List<DoseEventView>>(
        stream: _events,
        builder: (context, snapshot) {
          final events = snapshot.data ?? const <DoseEventView>[];
          final groups = _group(events);

          final nowCards = nowGroups(groups, _now);
          final glucoseNow = latestOutsideUsual(_readings);

          return ListView(
            padding: const EdgeInsets.all(F.gap),
            children: [
              StreamBuilder<PatientRow?>(
                stream: _patient,
                builder: (context, snap) => _HomeHeader(patient: snap.data, now: _now),
              ),
              const SizedBox(height: F.gap),
              if (nowCards.isNotEmpty || glucoseNow) ...[
                const _SectionTitle('الآن'),
                const SizedBox(height: F.s8),
                for (final (i, group) in nowCards.indexed) ...[
                  NowCard(
                    doses: group,
                    now: _now,
                    primary: i == 0,
                    snoozed: _snoozed.contains(group.first.scheduledAt),
                    onConfirm: () => _markTaken(group),
                    onOpen: () => _openReminder(group),
                    onLater: () => _later(group),
                  ),
                  const SizedBox(height: F.s10),
                ],
                // سكر برّه المعتاد ليه هو — في «الآن»، ذهبي ومن غير لوم
                if (glucoseNow) ...[
                  GlucoseHomeCard(readings: _readings, onOpen: _openGlucose),
                  const SizedBox(height: F.s10),
                ],
                const SizedBox(height: F.s8),
              ],
              if (nowCards.isEmpty && events.isNotEmpty) ...[
                const _AllDonePanel(),
                const SizedBox(height: F.gap),
              ],
              StreamBuilder<List<DoseEventView>>(
                stream: _tomorrow,
                builder: (context, snap) {
                  final tomorrow = _group(snap.data ?? const []);
                  if (tomorrow.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: F.gap),
                    child: _Upcoming(groups: tomorrow),
                  );
                },
              ),
              if (_readings.isNotEmpty && !glucoseNow) ...[
                GlucoseHomeCard(readings: _readings, onOpen: _openGlucose),
                const SizedBox(height: F.gap),
              ],
              const WaterWidget(),
              const SizedBox(height: F.gap),
              const Text(
                'جدول النهاردة',
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.subtitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
              const SizedBox(height: F.s4),
              const Text(
                'المراسي ثابتة، والجرعات معلّقة عليها.',
                style: TextStyle(fontSize: F.minTextSize, color: F.muted),
              ),
              const SizedBox(height: F.s12),
              if (events.isEmpty)
                _EmptyPanel(hasMedications: _schedules.isNotEmpty)
              else
                DayRail(
                  anchors: _anchors,
                  groups: groups,
                  now: _now,
                  ruleLabelFor: _ruleLabelFor,
                  onOpen: _openReminder,
                ),
              // القاعدة ٤: مجهول اتسجّل لازم يفضل ظاهر هنا — سؤال هادي للصيدلي
              StreamBuilder<List<MedicationRow>>(
                stream: _amountUnknown,
                builder: (context, snapshot) {
                  final meds = snapshot.data ?? const <MedicationRow>[];
                  if (meds.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: F.gap),
                    child: _FollowUpPanel(
                      items: [
                        for (final m in meds)
                          (label: 'اسأل الصيدلي عن جرعة ${m.name}', onTap: () => _openEdit(m.id)),
                      ],
                    ),
                  );
                },
              ),
              // مسافة تحت عشان آخر سطر ما يستخبّاش ورا زرار «ضيف»
              const SizedBox(height: F.s30 * 2),
            ],
          );
        },
      ),
    );
  }
}

/// نفس نبرة «التذكير هيفضل شغال لحد ما توقفه بنفسك»: سطر هادي، مش تنبيه.
///
/// مجهول اتسجّل ونقدر نتابعه كويس؛ اللي مش كويس هو مجهول اتنسي في صمت.
class _FollowUpPanel extends StatelessWidget {
  const _FollowUpPanel({required this.items});

  final List<({String label, VoidCallback onTap})> items;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              // الدوسة بتفتح التعديل — السؤال ليه مكان يتجاوب فيه.
              InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(F.radius),
                child: Container(
                  constraints: const BoxConstraints(minHeight: F.minTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: 10),
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.6),
                        ),
                      ),
                      const Text(
                        'اكتبها',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.green),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

/// الترحيب (المخطط 4): kicker، «صباح الخير يا محمد» بجنسه، والعنوان.
///
/// العنوان في التصميم «ماذا أفعل الآن؟» فصحى — والفصحى ممنوعة في الواجهة؛
/// «تعمل/تعملي إيه دلوقتي؟». سطر «الاسم · السن» بيظهر لو السن متسجّل.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.patient, required this.now});

  final PatientRow? patient;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final say = PatientVoice.of(context);
    final name = patient?.name;
    final hasName = name != null && name.isNotEmpty && name != 'أنا';
    final greeting = now.hour >= 4 && now.hour < 12 ? 'صباح الخير' : 'مساء الخير';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Kicker('يومك'),
        const SizedBox(height: F.s4),
        Text(
          hasName ? '$greeting يا $name' : greeting,
          style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink),
        ),
        if (hasName && patient?.age != null)
          Text(
            '$name — ${arabicNumber(patient!.age!)} سنة',
            style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
          ),
        const SizedBox(height: F.s6),
        Text(
          say.whatNow,
          style: const TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.screenTitleSize,
            fontWeight: FontWeight.w700,
            color: F.ink,
          ),
        ),
      ],
    );
  }
}

/// عنوان قسم بنقطة صغيرة — «الآن» / «خلال ٤٨ ساعة». النقطة خضرا، مش حمرا
/// زي التصميم.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: F.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: F.s8),
          Text(
            text,
            style: const TextStyle(fontSize: F.sectionHeadSize, fontWeight: FontWeight.w700, color: F.green),
          ),
        ],
      );
}

/// «خلال ٤٨ ساعة»: جرعات بكرة — صف لكل دقيقة. مفيش سكر ولا تحاليل هنا لسه
/// (D3.6).
class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.groups});

  final List<List<DoseEventView>> groups;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('خلال ٤٨ ساعة'),
          const SizedBox(height: F.s8),
          FCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, g) in groups.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: F.lineSoft),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
                    child: Row(
                      children: [
                        Text(
                          'بكرة ${arabicTime(g.first.scheduledAt)}',
                          style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                        ),
                        const SizedBox(width: F.s12),
                        Expanded(
                          child: Text(
                            g.map((d) => d.medicationName).join(' + '),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: F.minTextSize,
                              color: F.muted,
                              fontFamily: F.monoFamily,
                              fontFamilyFallback: F.monoFallback,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
}

class _AllDonePanel extends StatelessWidget {
  const _AllDonePanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: Text(
          PatientVoice.of(context).allDone,
          style: const TextStyle(
            fontSize: F.minBodySize,
            fontWeight: FontWeight.w600,
            color: F.greenDeep,
          ),
        ),
      );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.hasMedications});

  /// فيه دوا بس مفيش جرعة النهارده — اتضاف بعد ميعادها (`active_from`) أو
  /// بيبدأ بكرة. «مفيش أدوية» ساعتها كانت هتبقى كدب.
  final bool hasMedications;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: Text(
          hasMedications
              ? 'مفيش جرعات فاضلة النهارده. الجرعة الجاية مكتوبة فوق في «خلال ٤٨ ساعة».'
              : 'مفيش أدوية لسه. دوس «ضيف» تحت وإحنا نفكّرك بيه.',
          style: const TextStyle(
            fontSize: F.minBodySize,
            color: F.ink,
            height: 1.6,
          ),
        ),
      );
}
