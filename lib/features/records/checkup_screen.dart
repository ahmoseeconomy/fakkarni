import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/services/checkup_service.dart';
import '../../domain/health/checkup.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/scheduling/day_routine.dart';
import '../onboarding/time_wheel.dart';

/// «متابعة التحليل» (المخطط ١١): سبع مراحل، والمستخدم بيقدّمها بإيده.
///
/// الخالصة ✓ خضرا، الحالية برقمها بالذهبي (الحالة اللي إنت عليها)، واللي
/// بعدها باهتة. السطر اللي تحت العنوان بيقول ليه الشاشة موجودة أصلاً.
///
/// **كل مرحلة بتسأل عن ميعادها، وما بنفترضش حاجة.** «حجزت إمتى؟»،
/// «النتيجة هتجهز إمتى؟»، «معاد الدكتور؟» — الإجابة بتجدول تذكير في اليوم
/// ده، والتخطّي عادي وبيتقال بسطر قصير مش بتحذير. مفيش مدة بتتحسب من عندنا.
///
/// «اضبط تذكير الصيام» بيجدول إشعار حقيقي — من الضغطة بس (القاعدة ٤)، بساعات
/// **المستخدم** كتبها (القاعدة ٦). مش مبني: صندوق «قاعدة: لا يمكن للفحص أن
/// يبقى…» (حكم على التأخير) و«المتوقع ٢٤ ساعة» (رقم ماحدش قاله).
class CheckupScreen extends StatefulWidget {
  const CheckupScreen({required this.recordId, this.now, super.key});

  final int recordId;

  /// للاختبارات.
  final DateTime Function()? now;

  @override
  State<CheckupScreen> createState() => _CheckupScreenState();
}

class _CheckupScreenState extends State<CheckupScreen> {
  Stream<RecordRow?>? _row;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  CheckupService get _checkups => AppScope.of(context).checkups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _row ??= _checkups.watch(widget.recordId);
  }

  Future<void> _fasting(RecordRow row) async {
    final checkups = _checkups;
    final messenger = ScaffoldMessenger.of(context);
    final input = await showModalBottomSheet<({DateTime draw, int hours})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: F.pageGround,
      builder: (_) => _FastingSheet(now: _now),
    );
    if (input == null) return;
    final result = await checkups.setFastingReminder(row.id, draw: input.draw, hours: input.hours, now: _now);
    final text = switch (result) {
      FastingResult.scheduled => null,
      FastingResult.inPast => 'وقت بداية الصيام ده عدّى — اختار ميعاد سحب تاني.',
      FastingResult.tooMany => 'فيه تذكيرين صيام متظبطين لفحوصات تانية — شيل واحد الأول.',
      FastingResult.badHours => 'اكتب عدد الساعات اللي المعمل قالها.',
    };
    if (text != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontSize: F.minBodySize)),
        ),
      );
    }
  }

  /// ميعاد المرحلة — **نفس منتقي اليوم بتاع شيت الصيام**، مش تاني.
  Future<void> _pickStageDate(RecordRow row, FollowStage stage) async {
    final checkups = _checkups;
    final messenger = ScaffoldMessenger.of(context);
    final day = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: F.pageGround,
      builder: (_) => _StageDateSheet(stage: stage, now: _now, initial: CheckupService.stageDateOf(row, stage)),
    );
    if (day == null) return;
    final result = await checkups.setStageDate(row.id, stage, day: day, now: _now);
    final text = switch (result) {
      StageDateResult.scheduled => null,
      StageDateResult.inPast => 'اليوم ده عدّى — اختار يوم جاي.',
      StageDateResult.tooMany => 'فيه ميعادين متظبطين في متابعات تانية — شيل واحد الأول.',
    };
    if (text != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontSize: F.minBodySize)),
        ),
      );
    }
  }

  /// التقدّم خطوة. **وفي الزيارة فيه سؤال واحد بس**، مرة واحدة: بعد
  /// «الزيارة تمت»، هل الدكتور طلب تحليل؟ أيوه → بتبدأ «تابع تحليل»
  /// باسم نفس الدكتور. لأ → الزيارة بتقفل عند «المتابعة» وخلاص.
  ///
  /// السؤال جزء من الدوسة مش من الشاشة، فهو **بيتسأل مرة** بطبيعته —
  /// مفيش عمود بيفتكر إننا سألنا، ومفيش سؤال بيتكرر كل مرة يفتحها.
  Future<void> _advance(RecordRow row, FollowStage stage) async {
    final checkups = _checkups;
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final asksAboutTest = CheckupService.kindOf(row) == FollowKind.visit && stage == VisitStage.done;
    await checkups.advance(row.id, now: _now);
    if (!asksAboutTest || !mounted) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: const Text(
          'الدكتور طلب تحليل؟',
          style: TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'لو طلب، نبدأ معاك متابعة للتحليل على طول. ولو مطلبش، الزيارة كده خلصت.',
          style: TextStyle(fontSize: F.minBodySize, height: 1.5),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('visit-test-yes'),
                label: 'أيوه، طلب تحليل',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: F.s8),
              FSecondaryButton(
                key: const ValueKey('visit-test-no'),
                label: 'لأ، مطلبش',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ],
      ),
    );
    if (!(yes ?? false)) return;

    // **الاسم بيتسأل بعدين على شاشة التحليل**: الورقة لسه في إيده، وإحنا
    // ما بنخترعش اسم فحص. اللي بنشيله هو الدكتور — ده اللي إحنا عارفينه.
    final id = await checkups.start(
      patientId: services.patientId,
      kind: FollowKind.lab,
      title: row.doctor?.trim().isNotEmpty ?? false ? 'تحليل طلبه ${row.doctor!.trim()}' : 'تحليل',
      doctor: row.doctor,
      today: _now,
    );
    if (mounted) {
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CheckupScreen(recordId: id, now: widget.now),
        ),
      );
    }
  }

  Future<void> _stop(RecordRow row) async {
    final checkups = _checkups;
    final navigator = Navigator.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: Text(
          'توقّف متابعة «${row.title}»؟',
          style: const TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'هتتمسح من الملف خالص ومش هتقدر ترجّعها، والتذكيرات بتاعتها — لو فيه — بتتلغي.',
          style: TextStyle(fontSize: F.minBodySize, height: 1.5),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('stop-confirm'),
                label: 'أيوه، وقّفها',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: F.s8),
              FSecondaryButton(label: 'لأ، كمّل', onPressed: () => Navigator.of(context).pop(false)),
            ],
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await checkups.delete(row.id);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // العنوان بيتقرا من الصف — «متابعة التحليل» ولا «متابعة الزيارة» —
    // فالـStreamBuilder لفّ الشاشة كلها مش الجسم بس.
    return StreamBuilder<RecordRow?>(
      stream: _row,
      builder: (context, snap) {
        final row = snap.data;
        final kind = row == null ? FollowKind.lab : CheckupService.kindOf(row);
        final stage = row == null ? null : CheckupService.stageOf(row);
        return Scaffold(
          appBar: AppBar(title: Text(kind.screenTitle)),
          body: Builder(
            builder: (context) {
              if (row == null || stage == null) return const SizedBox.shrink();
              final stages = kind.stages;
              final reminder = row.fastingReminderAt;
              return ListView(
                padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
                children: [
                  Text(
                    '${row.title} — ${arabicNumber(stages.length)} مراحل',
                    textDirection: nameDirection(row.title),
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.s4),
                  Text(
                    'التحليل مش ميعاد واحد — كل خطوة ليها وقتها، وهنا بتعرف وقفت فين.',
                    key: ValueKey('checkup-why'),
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                  ),
                  const SizedBox(height: F.gap),
                  for (final s in stages)
                    _StageRow(
                      stage: s,
                      current: stage,
                      last: s == stages.last,
                      detail: s == CheckupStage.sampleDraw && reminder != null
                          ? '${arabicDate(row.happenedAt)} — ${arabicTime(row.happenedAt)}'
                          : null,
                      children: s != stage
                          ? const []
                          : [
                              const SizedBox(height: F.s10),
                              if (kind.nextAfter(stage) case final next?)
                                FPrimaryButton(
                                  key: const ValueKey('checkup-advance'),
                                  label: 'خلصت — على «${next.label}»',
                                  onPressed: () => _advance(row, stage),
                                ),
                              if (kind.nextAfter(stage) == null)
                                const Text(
                                  'ده آخر مرحلة.',
                                  style: TextStyle(
                                    fontSize: F.minBodySize,
                                    fontWeight: FontWeight.w600,
                                    color: F.greenDeep,
                                  ),
                                ),
                              if (stage.asksForDate) ...[
                                const SizedBox(height: F.s8),
                                _StageDate(
                                  stage: stage,
                                  at: CheckupService.stageDateOf(row, stage),
                                  onPick: () => _pickStageDate(row, stage),
                                  onClear: () => _checkups.clearStageDate(row.id, stage),
                                ),
                              ],
                              // الصيام بتاع التحليل بس — الزيارة مالهاش صيام.
                              if (stage is CheckupStage && fastingReminderStillUseful(stage)) ...[
                                const SizedBox(height: F.s8),
                                if (reminder == null)
                                  FPrimaryButton(
                                    key: const ValueKey('fasting-set'),
                                    label: 'اضبط تذكير الصيام',
                                    gold: false,
                                    onPressed: () => _fasting(row),
                                  )
                                else ...[
                                  Text(
                                    'تذكير الصيام متظبط: ${arabicDate(reminder)} — ${arabicTime(reminder)}',
                                    key: const ValueKey('fasting-set-line'),
                                    style: TextStyle(
                                      fontSize: F.minBodySize,
                                      fontWeight: FontWeight.w600,
                                      color: F.ink,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: F.s6),
                                  FSecondaryButton(
                                    label: 'شيل تذكير الصيام',
                                    onPressed: () => _checkups.cancelFasting(row.id),
                                  ),
                                ],
                              ],
                              if (kind.beforeStage(stage) case final previous?) ...[
                                const SizedBox(height: F.s8),
                                FSecondaryButton(
                                  key: const ValueKey('checkup-back'),
                                  label: 'رجوع لـ«${previous.label}»',
                                  onPressed: () => _checkups.back(row.id),
                                ),
                              ],
                            ],
                    ),
                  const SizedBox(height: F.gap),
                  FSecondaryButton(label: 'وقّف المتابعة', onPressed: () => _stop(row)),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.current,
    required this.last,
    required this.children,
    this.detail,
  });

  final FollowStage stage;
  final FollowStage current;
  final bool last;
  final List<Widget> children;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final done = stage.number < current.number;
    final isCurrent = stage == current;
    final later = stage.number > current.number;

    final Widget node = Container(
      key: ValueKey('stage-${stage.number}'),
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? F.green : (isCurrent ? F.gold : F.pageGround),
        border: later ? Border.all(color: F.line, width: 1.5) : null,
      ),
      child: done
          ? const Icon(Icons.check, size: 24, color: F.onDark)
          : Text(
              arabicNumber(stage.number),
              style: TextStyle(
                fontSize: F.minTextSize,
                fontWeight: FontWeight.w700,
                color: later ? F.mutedLight : F.ink,
              ),
            ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                node,
                if (!last) Expanded(child: Container(width: 2, color: done ? F.green : F.line)),
              ],
            ),
          ),
          const SizedBox(width: F.s10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: F.gap, top: F.s6),
              child: Opacity(
                opacity: later ? 0.55 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      stage.label,
                      style: TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                        color: F.ink,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                      ),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «اضبط تذكير الصيام»: ميعاد السحب (يوم + ساعة) وعدد ساعات الصيام **زي ما
/// المعمل قال** — مفيش رقم افتراضي.
class _FastingSheet extends StatefulWidget {
  const _FastingSheet({required this.now});

  final DateTime now;

  @override
  State<_FastingSheet> createState() => _FastingSheetState();
}

class _FastingSheetState extends State<_FastingSheet> {
  late DateTime _day = DateTime(widget.now.year, widget.now.month, widget.now.day + 1);
  MinuteOfDay _time = MinuteOfDay.hm(8);
  final _hours = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hours.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  int? get _parsedHours => int.tryParse(
    _hours.text.trim().replaceAllMapped(
      RegExp('[٠-٩]'),
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x660 + 0x30),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final hours = _parsedHours;
    final ok = hours != null && isTypedFastingHours(hours);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(F.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تذكير الصيام',
                style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: F.s12),
              const SectionHead('ميعاد سحب العينة إمتى؟'),
              const SizedBox(height: F.s8),
              DayPicker(today: today, value: _day, onChanged: (d) => setState(() => _day = d)),
              const SizedBox(height: F.s8),
              SizedBox(
                height: 180,
                child: TimeWheel(value: _time, onChanged: (t) => setState(() => _time = t)),
              ),
              const SizedBox(height: F.s12),
              const SectionHead('المعمل قال صيام كام ساعة؟'),
              const SizedBox(height: F.s8),
              TextField(
                key: const ValueKey('fasting-hours'),
                controller: _hours,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'زي ما المعمل قال',
                  hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  suffixText: 'ساعة',
                  filled: true,
                  fillColor: F.fieldGround,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
                ),
              ),
              const SizedBox(height: F.s6),
              Text(
                'التطبيق مش بيحدد مدة الصيام — المعمل أو الدكتور هو اللي بيقولها.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
              const SizedBox(height: F.gap),
              FPrimaryButton(
                key: const ValueKey('fasting-save'),
                label: 'اضبط التذكير',
                onPressed: !ok
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop((draw: DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute), hours: hours)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// منتقي يوم: شريحتين سريعتين وشريحة بتفتح التقويم.
///
/// **واحد لكل الشاشة**: شيت الصيام وشيت ميعاد المرحلة بيستعملوه — منتقي
/// تاني معناه مكانين لنفس السلوك، وفي يوم هيختلفوا.
class DayPicker extends StatelessWidget {
  const DayPicker({required this.today, required this.value, required this.onChanged, super.key});

  final DateTime today;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final quick = [
      ('بكرة', DateTime(today.year, today.month, today.day + 1)),
      ('بعد بكرة', DateTime(today.year, today.month, today.day + 2)),
    ];
    final onQuick = quick.any((q) => q.$2 == value);
    return Wrap(
      spacing: F.s8,
      runSpacing: F.s8,
      children: [
        for (final (label, day) in quick) AnchorChip(label: label, selected: value == day, onTap: () => onChanged(day)),
        AnchorChip(
          key: const ValueKey('day-other'),
          label: onQuick ? 'يوم تاني' : arabicDate(value),
          selected: !onQuick,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value.isBefore(today) ? today : value,
              firstDate: today,
              lastDate: DateTime(today.year + 1, today.month, today.day),
            );
            if (picked != null) onChanged(picked);
          },
        ),
      ],
    );
  }
}

/// ميعاد المرحلة على الشاشة: السؤال، وإجابته لو فيه، والتخطّي بسطر قصير.
class _StageDate extends StatelessWidget {
  const _StageDate({required this.stage, required this.at, required this.onPick, required this.onClear});

  final FollowStage stage;
  final DateTime? at;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (at case final picked?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${stage.dateQuestion} ${arabicDate(picked)}',
            key: ValueKey('stage-date-line-${stage.number}'),
            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
          ),
          const SizedBox(height: F.s6),
          Row(
            children: [
              Expanded(
                child: FSecondaryButton(
                  key: ValueKey('stage-date-edit-${stage.number}'),
                  label: 'غيّر الميعاد',
                  onPressed: onPick,
                ),
              ),
              const SizedBox(width: F.s8),
              Expanded(
                child: FSecondaryButton(
                  key: ValueKey('stage-date-clear-${stage.number}'),
                  label: 'شيل الميعاد',
                  onPressed: onClear,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FPrimaryButton(
          key: ValueKey('stage-date-set-${stage.number}'),
          label: stage.dateQuestion!,
          gold: false,
          onPressed: onPick,
        ),
        const SizedBox(height: F.s6),
        // التخطّي عادي — سطر قصير، مش تحذير ولا ذهبي
        Text(
          'لو لسه ما تحدّدش، عدّي — من غير ميعاد مفيش تذكير وبس.',
          key: ValueKey('stage-date-skip-${stage.number}'),
          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
        ),
      ],
    );
  }
}

/// شيت ميعاد المرحلة: سؤال واحد ومنتقي يوم واحد — نفس [DayPicker].
class _StageDateSheet extends StatefulWidget {
  const _StageDateSheet({required this.stage, required this.now, this.initial});

  final FollowStage stage;
  final DateTime now;
  final DateTime? initial;

  @override
  State<_StageDateSheet> createState() => _StageDateSheetState();
}

class _StageDateSheetState extends State<_StageDateSheet> {
  late DateTime _day = widget.initial ?? DateTime(widget.now.year, widget.now.month, widget.now.day + 1);

  @override
  Widget build(BuildContext context) {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(F.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.stage.dateQuestion!,
                style: const TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.subtitleSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: F.s12),
              DayPicker(
                today: today,
                value: DateTime(_day.year, _day.month, _day.day),
                onChanged: (d) => setState(() => _day = d),
              ),
              const SizedBox(height: F.gap),
              FPrimaryButton(
                key: const ValueKey('stage-date-save'),
                label: 'احفظ الميعاد',
                onPressed: () => Navigator.of(context).pop(DateTime(_day.year, _day.month, _day.day)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
