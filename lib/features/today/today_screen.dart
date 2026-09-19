import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/repositories/readings_repository.dart';
import '../../data/services/checkup_service.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/health/checkup.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../health/glucose_screen.dart';
import '../link/sign_in_screen.dart';
import '../medication/edit_medication_screen.dart';
import '../nearby/nearby_screen.dart';
import '../records/checkup_screen.dart';
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

  /// متابعات التحاليل المفتوحة — **متابعة محدش شايفها متابعة محدش بيعملها**.
  Stream<List<RecordRow>>? _followUps;

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
    _followUps = services.checkups.watchOpen(services.patientId);
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

  /// صف الدايرة بيفتح باب الربط الموجود — نفس الشاشة، نفس النداء الوحيد.
  void _openCircle() {
    final services = AppScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignInScreen(
          auth: services.auth,
          caregiver: services.caregiver,
          push: services.push,
        ),
      ),
    );
  }

  void _openNearby() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NearbyScreen()),
      );

  void _openGlucose() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GlucoseScreen()),
      );

  void _openCheckup(int recordId) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CheckupScreen(recordId: recordId)),
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
      // «القريب مني» عايم في آخر السطر (ناحية الشمال في RTL) — ثانوي، مش
      // أساسي: الأساسي الوحيد على الشاشة دي «تأكيد الجرعة».
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: F.s10 + MediaQuery.of(context).padding.bottom),
        child: _NearbyPill(onTap: _openNearby),
      ),
      body: StreamBuilder<List<DoseEventView>>(
        stream: _events,
        builder: (context, snapshot) {
          final events = snapshot.data ?? const <DoseEventView>[];
          final groups = _group(events);

          final nowCards = nowGroups(groups, _now);
          final glucoseNow = latestOutsideUsual(_readings);

          return ListView(
            // مساحة تحت عشان آخر كارت يعدّي من تحت الدوك من غير ما يتخبّى
            // تحته. `padding.bottom` جوّه جسم الـScaffold المفرود بيساوي
            // طول الدوك — Flutter بيحطه هناك بالظبط للسبب ده.
            padding: EdgeInsets.fromLTRB(
              F.gap,
              F.gap,
              F.gap,
              F.gap + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              StreamBuilder<PatientRow?>(
                stream: _patient,
                builder: (context, snap) => _HomeHeader(
                  patient: snap.data,
                  now: _now,
                  onOpenCircle: _openCircle,
                ),
              ),
              const SizedBox(height: F.gap),
              if (nowCards.isNotEmpty || glucoseNow) ...[
                const _SectionTitle('الآن', attention: true),
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
              // متابعات التحاليل المفتوحة: اسم التحليل والمرحلة، والدوسة
              // بتفتحها. مفيش حاجة بتتعرض لما مفيش متابعات.
              StreamBuilder<List<RecordRow>>(
                stream: _followUps,
                builder: (context, snap) {
                  final open = snap.data ?? const <RecordRow>[];
                  if (open.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: F.gap),
                    child: _OpenFollowUps(
                      records: open,
                      onOpen: _openCheckup,
                    ),
                  );
                },
              ),
              const WaterWidget(),
              const SizedBox(height: F.gap),
              Text(
                'جدول النهاردة',
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.subtitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
              const SizedBox(height: F.s4),
              Text(
                'المراسي ثابتة، والجرعات معلّقة عليها.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
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
                  return StreamBuilder<List<RecordRow>>(
                    stream: _followUps,
                    builder: (context, followSnap) {
                      // متابعة واقفة عند مرحلة بتسأل عن ميعاد، ومفيش ميعاد،
                      // وعدّى أسبوع. حد عرض — مش حكم على المعمل.
                      final stalled = [
                        for (final r in followSnap.data ?? const <RecordRow>[])
                          if (CheckupStage.fromNumber(r.checkupStage) case final stage?)
                            if (checkupIsStalled(
                              stage: stage,
                              stageSince: r.checkupStageSince,
                              stageDate: CheckupService.stageDateOf(r, stage),
                              now: _now,
                            ))
                              (
                                label: 'متابعة ${r.title} واقفة عند ${stage.label}',
                                onTap: () => _openCheckup(r.id),
                              ),
                      ];
                      final items = [
                        for (final m in meds)
                          (label: 'اسأل الصيدلي عن جرعة ${m.name}', onTap: () => _openEdit(m.id)),
                        ...stalled,
                      ];
                      if (items.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: F.gap),
                        child: _FollowUpPanel(items: items),
                      );
                    },
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
          color: F.railGround,
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
                          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                        ),
                      ),
                      Text(
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

/// الترحيب (المخطط 4): kicker، «صباح الخير يا محمد» بجنسه، وصف الدايرة.
///
/// **مفيش عنوان كبير**: لا «ماذا أفعل الآن؟» (فصحى) ولا «تعمل إيه دلوقتي؟» —
/// التحية بتوصّل للأقسام على طول. الشاشة دي بتاعة صاحب الموبايل، فالكلام
/// كله بيخاطبه هو («مين بيتابعك»)، مش «ملف والدك» بتاع التصميم.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.patient, required this.now, required this.onOpenCircle});

  final PatientRow? patient;
  final DateTime now;
  final VoidCallback onOpenCircle;

  @override
  Widget build(BuildContext context) {
    final name = patient?.name;
    final hasName = name != null && name.isNotEmpty && name != 'أنا';
    final greeting = now.hour >= 4 && now.hour < 12 ? 'صباح الخير' : 'مساء الخير';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // «يومك» بحجم العنوان — هي عنوان الشاشة، مش سطر فوقها.
        // `height` مش زينة: خط العناوين طالع فوق السطر، وبالارتفاع
        // الافتراضي كان نص «يومك» الأعلى بيتقص.
        Text(
          'يومك',
          style: TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.screenTitleSize,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: F.green,
          ),
        ),
        const SizedBox(height: F.s4),
        Text(
          hasName ? '$greeting يا $name' : greeting,
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink),
        ),
        if (hasName && patient?.age != null)
          Text(
            '$name — ${arabicNumber(patient!.age!)} سنة',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
          ),
        const SizedBox(height: F.s12),
        CareCircleRow(onOpen: onOpenCircle),
      ],
    );
  }
}

/// «مين بيتابعك» (المخطط ٤ — صف الصور تحت التحية).
///
/// دي الشفافية اللي الأب يستاهلها: مين شايف بياناته، على شاشته الأولى، من
/// غير ما يدوّر في الإعدادات. من غير حد مربوط بتبقى **دعوة** مش صف فاضي.
/// اللمسة بتفتح القايمة. الشارة اللي في التصميم جنب الصور مش مبنية — مش
/// واضح بتعدّ إيه.
class CareCircleRow extends StatelessWidget {
  const CareCircleRow({required this.onOpen, this.names = const [], super.key});

  /// أسماء اللي بيتابعوا — فاضية لحد ما الربط يحصل.
  final List<String> names;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
        color: F.cardGround,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(F.radiusCard),
          side: BorderSide(color: F.line),
        ),
        child: InkWell(
          key: const ValueKey('care-circle-row'),
          onTap: onOpen,
          borderRadius: BorderRadius.circular(F.radiusCard),
          child: Container(
            constraints: const BoxConstraints(minHeight: F.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s8),
            child: Row(
              children: [
                if (names.isEmpty)
                  Icon(Icons.person_add_alt, size: 26, color: F.green)
                else
                  for (final (i, name) in names.indexed)
                    Padding(
                      padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : F.s4),
                      child: _Avatar(name: name),
                    ),
                const SizedBox(width: F.s10),
                Expanded(
                  child: Text(
                    names.isEmpty
                        ? 'محدش بيتابعك لسه — اربط ابنك أو بنتك'
                        : 'بيتابعوك: ${names.join('، ')}',
                    style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4),
                  ),
                ),
                Icon(Icons.chevron_left, size: 24, color: F.mutedDark),
              ],
            ),
          ),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: F.greenDeep, shape: BoxShape.circle),
        child: Text(
          name.characters.first,
          style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.onDark),
        ),
      );
}

/// عنوان قسم بنقطة صغيرة — «الآن» / «خلال ٤٨ ساعة».
///
/// التصميم بيحط نقطة **حمرا** على «الآن». عندنا الأحمر للطوارئ بس، وجرعة
/// فايتة مش خطر — هو نسي، ما فشلش. فالنقطة ذهبي: «دي لسه عايزاك». والقسم
/// اللي جاي نقطته خضرا هادية.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.attention = false});
  final String text;
  final bool attention;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: attention ? F.gold : F.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: F.s8),
          Text(
            text,
            style: TextStyle(fontSize: F.sectionHeadSize, fontWeight: FontWeight.w700, color: F.green),
            key: ValueKey('section-$text'),
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
                  if (i > 0) Divider(height: 1, color: F.lineSoft),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
                    child: Row(
                      children: [
                        Text(
                          'بكرة ${arabicTime(g.first.scheduledAt)}',
                          style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                        ),
                        const SizedBox(width: F.s12),
                        Expanded(
                          child: Text(
                            g.map((d) => d.medicationName).join(' + '),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: F.minTextSize,
                              color: F.mutedDark,
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
          color: F.railGround,
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
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.line),
        ),
        child: Text(
          hasMedications
              ? 'مفيش جرعات فاضلة النهارده. الجرعة الجاية مكتوبة فوق في «خلال ٤٨ ساعة».'
              : 'مفيش أدوية لسه. دوس «ضيف» تحت وإحنا نفكّرك بيه.',
          style: TextStyle(
            fontSize: F.minBodySize,
            color: F.ink,
            height: 1.6,
          ),
        ),
      );
}

/// «القريب مني» — بيل عايم صغير تحت الشمال، **في الرئيسية وبس**.
///
/// دهبي مليان بحد زيتي زي ما المالك طلب. الدهبي هنا حالة «تقدر تروح
/// دلوقتي» مش تنبيه، وهو الزرار الوحيد بالشكل ده على الشاشة.
class _NearbyPill extends StatelessWidget {
  const _NearbyPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: F.gold,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(F.radiusChip),
          side: BorderSide(color: F.greenDeep, width: 1.5),
        ),
        child: InkWell(
          key: const ValueKey('nearby-pill'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radiusChip),
          // من غير `alignment` — Container بـalignment بياخد كل العرض المتاح،
          // والبيل كان بيتمدّ على الشاشة كلها
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: F.s12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_outlined, size: 20, color: F.greenDeep),
                const SizedBox(width: F.s6),
                Text(
                  'القريب مني',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenDeep),
                ),
              ],
            ),
          ),
        ),
      );
}

/// متابعات التحاليل المفتوحة: عنوان صغير، وسطر لكل واحدة باسمها ومرحلتها.
///
/// مش كارت ومش ذهبي — دي حاجة بتتعمل على مهل، مش جرعة فاتت. والدوسة
/// بتفتح شاشة المتابعة نفسها.
class _OpenFollowUps extends StatelessWidget {
  const _OpenFollowUps({required this.records, required this.onOpen});

  final List<RecordRow> records;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('open-follow-ups'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'متابعة التحاليل',
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.subtitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          const SizedBox(height: F.s8),
          Container(
            decoration: BoxDecoration(
              color: F.railGround,
              borderRadius: BorderRadius.circular(F.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in records)
                  InkWell(
                    key: ValueKey('follow-up-${r.id}'),
                    onTap: () => onOpen(r.id),
                    borderRadius: BorderRadius.circular(F.radius),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: F.minTapTarget),
                      padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  r.title,
                                  textDirection: nameDirection(r.title),
                                  style: TextStyle(
                                    fontSize: F.minBodySize,
                                    fontWeight: FontWeight.w700,
                                    color: F.ink,
                                  ),
                                ),
                                if (CheckupStage.fromNumber(r.checkupStage) case final stage?)
                                  Text(
                                    stage.label,
                                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            'افتح',
                            style: TextStyle(
                              fontSize: F.minTextSize,
                              fontWeight: FontWeight.w600,
                              color: F.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}
