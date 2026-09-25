import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/files/med_photos.dart';
import 'med_photo.dart';
import 'every_hours_picker.dart';
import 'day_pattern_picker.dart';
import 'add_medication_screen.dart' show DosePattern;
import '../../domain/scheduling/day_pattern.dart';
import '../../core/widgets/f_sheet.dart';
import '../../domain/scheduling/every_hours.dart';

import 'stock_section.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../../domain/escalation/alert_mode.dart';
import 'alert_mode_chips.dart';
import 'dose_editor.dart';
import 'dose_row.dart';

/// تعديل دوا موجود: الجرعة زي ما الصيدلي قالها، توقيت كل جرعة من
/// [DoseEditor]، أو إيقافه.
///
/// الإيقاف **بإيد إنسان وبس** وبخطوتين — التطبيق عمره ما بيوقف دوا من نفسه.
/// وتغيير الروتين نفسه (الفطار الساعة كام) من «مواعيد يومك»، مش من هنا.
class EditMedicationScreen extends StatefulWidget {
  const EditMedicationScreen({required this.medicationId, super.key});

  final int medicationId;

  @override
  State<EditMedicationScreen> createState() => _EditMedicationScreenState();
}

class _EditMedicationScreenState extends State<EditMedicationScreen> {
  final _amount = TextEditingController();
  final _instructions = TextEditingController();
  bool _openEnded = true;
  int _days = 7;
  Stream<MedicationRow?>? _medication;
  List<DoseSchedule> _schedules = const [];
  DayRoutine _routine = DayRoutine.fallback;
  bool _seeded = false;
  bool _confirmingStop = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_medication != null) return;
    final services = AppScope.of(context);
    _medication = services.medications.watchMedication(widget.medicationId);
    _loadSchedules();
    services.routines.getRoutine(services.patientId).then((r) {
      if (mounted && r != null) setState(() => _routine = r);
    });
    services.preferences.get().then((p) {
      if (mounted) setState(() => _deviceMode = p.alertMode);
    });
  }

  AlertMode? _deviceMode;

  Future<void> _setAlertMode(AlertMode? mode) async {
    final services = AppScope.of(context);
    await services.medications.setAlertMode(widget.medicationId, mode);
    await services.scheduler.rescheduleAll();
  }

  /// ميعاد وجبة اتحدد من جوّه المحرّر — بيتكتب متحدد والشاشة بتشوفه.
  Future<void> _setAnchor(DayAnchor anchor, MinuteOfDay time) async {
    final services = AppScope.of(context);
    await services.routines.setAnchor(services.patientId, anchor, time);
    if (mounted) setState(() => _routine = _routine.withAnchor(anchor, time));
  }

  bool _durationSeeded = false;

  Future<void> _loadSchedules() async {
    final s = await AppScope.of(context).medications.schedulesFor(widget.medicationId);
    if (!mounted) return;
    setState(() {
      _schedules = s;
      // المدة بتيجي مع الجداول (مش مع صف الدوا) — بتتعبّى مرة، أول ما توصل
      if (!_durationSeeded) {
        _durationSeeded = true;
        final days = s.map((x) => x.durationDays).whereType<int>();
        if (days.isNotEmpty) {
          _openEnded = false;
          _days = days.first.clamp(1, 90);
        }
      }
    });
  }

  /// «عدّل» على جرعة: محرّر الجرعة بتوقيتها الحالي، والحفظ بيغيّر الصف
  /// نفسه (نفس id) وبيعيد الجدولة.
  Future<void> _editTiming(DoseSchedule schedule, String name) async {
    if (_busy) return;
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => DoseEditor(
          name: name,
          routine: _routine,
          onSetAnchor: _setAnchor,
          initialTiming: schedule.timing,
          onSave: (timing) async {
            await services.medications.updateTiming(int.parse(schedule.id), timing);
            await services.scheduler.rescheduleAll();
            navigator.pop();
          },
        ),
      ),
    );
    await _loadSchedules();
  }

  /// «أضف جرعة» لدوا موجود: محرّر الجرعة، والحفظ بيكتب **صف جديد** — نفس
  /// طريق الروشتة بالظبط (`addDoseSchedule`)، وبيتزامن زي أي جرعة تانية.
  ///
  /// الافتراضي أول مرساة لسه مش مستعملة، والإنسان بيأكّدها في المحرّر قبل ما
  /// تتكتب — مفيش جرعة بتتحفظ من غير دوسة. والمدة بتتاخد من جرعات الدوا
  /// الموجودة، مش بتتخمّن.
  Future<void> _addTiming(String name) async {
    if (_busy) return;
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    const order = [DayAnchor.breakfast, DayAnchor.lunch, DayAnchor.dinner, DayAnchor.wake, DayAnchor.sleep];
    final used = {
      for (final s in _schedules)
        if (s.timing case AnchorTiming(:final anchor)) anchor,
    };
    final next = order.firstWhere((a) => !used.contains(a), orElse: () => DayAnchor.dinner);
    final days = _schedules.map((s) => s.durationDays).whereType<int>();

    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => DoseEditor(
          name: name,
          routine: _routine,
          onSetAnchor: _setAnchor,
          initialTiming: AnchorTiming(next, -defaultOffsetBefore(next)),
          onSave: (timing) async {
            await services.medications.addDoseSchedule(
              widget.medicationId,
              timing: timing,
              startDate: DateTime.now(),
              durationDays: days.isEmpty ? null : days.first,
            );
            await services.scheduler.rescheduleAll();
            navigator.pop();
          },
        ),
      ),
    );
    await _loadSchedules();
  }

  /// «خليه كل كام ساعة» لدوا موجود: الساعات الجديدة بتتكتب **الأول**
  /// (`addDoseSchedule`، نفس «أضف جرعة»)، وبعدين القديمة بتتوقف إيقاف ناعم
  /// (`stopDoseSchedule`) — فمفيش لحظة الدوا فيها من غير جرعة، والتاريخ
  /// والسحابة زي أي «شيل». وبعدين `rescheduleAll` مرة.
  Future<void> _makeEveryHours(String name) async {
    if (_busy) return;
    final services = AppScope.of(context);
    var hours = 8;
    var first = MinuteOfDay.hm(8, 0);
    final fixed = [
      for (final s in _schedules)
        if (s.timing case FixedTiming(:final minuteOfDay)) minuteOfDay,
    ];
    final h = fixed.length == _schedules.length ? everyHoursOf(fixed) : null;
    if (h != null) {
      hours = h;
      first = (fixed..sort((a, b) => a.minutes.compareTo(b.minutes))).first;
    }
    final picked = await FSheet.show<(int, MinuteOfDay)>(
      context,
      title: 'كل كام ساعة',
      children: [
        StatefulBuilder(
          builder: (context, setSheet) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EveryHoursPicker(
                hours: hours,
                first: first,
                onChanged: (h, t) => setSheet(() {
                  hours = h;
                  first = t;
                }),
              ),
              const SizedBox(height: F.gap),
              FPrimaryButton(
                key: const ValueKey('every-hours-save'),
                label: 'احفظ',
                onPressed: () => Navigator.of(context).pop((hours, first)),
              ),
            ],
          ),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final days = _schedules.map((s) => s.durationDays).whereType<int>();
      final old = [..._schedules];
      for (final t in everyHoursTimes(picked.$2, picked.$1)) {
        await services.medications.addDoseSchedule(
          widget.medicationId,
          timing: FixedTiming(t),
          startDate: DateTime.now(),
          durationDays: days.isEmpty ? null : days.first,
        );
      }
      for (final s in old) {
        await services.medications.stopDoseSchedule(int.parse(s.id));
      }
      await services.scheduler.rescheduleAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _loadSchedules();
  }

  /// «غيّر الأيام» (الجولة ٢): كل جرعة بتتكتب من جديد بنفس معادها والأيام
  /// الجديدة (من النهارده)، **وبعدين** القديمة بتتوقف إيقاف ناعم — زي «كل
  /// كام ساعة» بالظبط.
  Future<void> _changeDays() async {
    if (_busy || _schedules.isEmpty) return;
    final services = AppScope.of(context);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    var kind = switch (_schedules.first.days) {
      OnWeekdays() => DosePattern.weekdays,
      EveryNDays() => DosePattern.everyNDays,
      OnOffCycle() => DosePattern.cycle,
      EveryDay() => DosePattern.daily,
    };
    var weekdays = switch (_schedules.first.days) {
      OnWeekdays(:final weekdays) => {...weekdays},
      _ => <int>{},
    };
    var everyN = switch (_schedules.first.days) {
      EveryNDays(:final days) => days,
      _ => 2,
    };
    var (cycleOn, cycleOff) = switch (_schedules.first.days) {
      OnOffCycle(:final on, :final off) => (on, off),
      _ => (21, 7),
    };
    DayPattern? picked() => switch (kind) {
          DosePattern.weekdays when weekdays.isNotEmpty => OnWeekdays(weekdays),
          DosePattern.weekdays => null,
          DosePattern.everyNDays => EveryNDays(everyN),
          DosePattern.cycle => OnOffCycle(cycleOn, cycleOff),
          _ => DayPattern.everyDay,
        };
    final result = await FSheet.show<DayPattern>(
      context,
      title: 'غيّر الأيام',
      children: [
        StatefulBuilder(
          builder: (context, setSheet) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: F.s8,
                runSpacing: F.s8,
                children: [
                  for (final (k, label) in const [
                    (DosePattern.daily, 'كل يوم'),
                    (DosePattern.weekdays, 'أيام معينة'),
                    (DosePattern.everyNDays, 'كل كام يوم'),
                    (DosePattern.cycle, 'فترة وراحة'),
                  ])
                    AnchorChip(
                      key: ValueKey('days-${k.name}'),
                      label: label,
                      selected: kind == k,
                      onTap: () => setSheet(() => kind = k),
                    ),
                ],
              ),
              const SizedBox(height: F.gap),
              if (kind != DosePattern.daily)
                DayPatternPicker(
                  pattern: kind,
                  weekdays: weekdays,
                  everyN: everyN,
                  cycleOn: cycleOn,
                  cycleOff: cycleOff,
                  start: day,
                  today: day,
                  onWeekdays: (d) => setSheet(() => weekdays = d),
                  onEveryN: (n) => setSheet(() => everyN = n),
                  onCycle: (on, off) => setSheet(() {
                    cycleOn = on;
                    cycleOff = off;
                  }),
                ),
              const SizedBox(height: F.gap),
              FPrimaryButton(
                key: const ValueKey('days-save'),
                label: 'احفظ',
                onPressed: picked() == null ? null : () => Navigator.of(context).pop(picked()),
              ),
            ],
          ),
        ),
      ],
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final old = [..._schedules];
      for (final s in old) {
        await services.medications.addDoseSchedule(
          widget.medicationId,
          timing: s.timing,
          startDate: day,
          durationDays: s.durationDays,
          days: result,
        );
      }
      for (final s in old) {
        await services.medications.stopDoseSchedule(int.parse(s.id));
      }
      await services.scheduler.rescheduleAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _loadSchedules();
  }

  /// «شيل» لجرعة **محفوظة** — إيقاف ناعم، مش مسح.
  ///
  /// `stopDoseSchedule` بيحط `stopped_at` وبيعلّم الأحداث الجاية
  /// `superseded`، فالتذكير بيقف والابن ما بيتنبّهش على جرعة مابقتش
  /// موجودة. المسح الحقيقي هنا ممنوع: المزامنة بترفع بس، والأحداث بتتشال
  /// بالـcascade — فالجهاز ينسى والسحابة تفضل فاكرة ويتصعّد على جرعة
  /// الأب شالها بنفسه.
  ///
  /// وبيتسأل مرة قبلها: دوسة بالغلط هنا معناها جرعة بتبطّل ترنّ، وهو مش
  /// هيعرف غير لما يفوّتها.
  Future<void> _removeTiming(DoseSchedule schedule) async {
    if (_busy || _schedules.length <= 1) return;
    final services = AppScope.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: Text(
          'تشيل جرعة «${schedule.timing.ruleLabel}»؟',
          style: const TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'هتبطّل ترنّ من دلوقتي. الجرعات اللي فاتت بتفضل في سجلك، وتقدر '
          'تضيفها تاني من «أضف جرعة».',
          style: TextStyle(fontSize: F.minBodySize, height: 1.5),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('remove-dose-confirm'),
                label: 'أيوه، شيلها',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: F.s8),
              FSecondaryButton(label: 'لأ، سيبها', onPressed: () => Navigator.of(context).pop(false)),
            ],
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await services.medications.stopDoseSchedule(int.parse(schedule.id));
      await services.scheduler.rescheduleAll();
      await _loadSchedules();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    await services.medications.updateAmount(widget.medicationId, _amount.text);
    await services.medications.updateDetails(
      widget.medicationId,
      instructions: _instructions.text,
      durationDays: _openEnded ? null : _days,
    );
    // نص التذكير فيه الجرعة — لازم يتعاد بناؤه بالنص الجديد.
    await services.scheduler.rescheduleAll();

    if (mounted) navigator.pop(true);
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    await services.medications.stopMedication(widget.medicationId);
    // تذكيراته بتتلغى هنا — جوّه نطاق الجرعات بس.
    await services.scheduler.rescheduleAll();

    if (mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الدوا',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<MedicationRow?>(
          stream: _medication,
          builder: (context, snapshot) {
            final med = snapshot.data;
            if (med == null) {
              return Center(child: CircularProgressIndicator(color: F.green));
            }
            if (!_seeded) {
              _seeded = true;
              _amount.text = med.amountLabel ?? '';
              _instructions.text = med.instructions ?? '';
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(F.gap),
                    children: [
                      Row(
                        children: [
                          // الصورة جنب الاسم — ولو مفيش، مفيش مربع فاضي
                          if (med.photoPath != null) ...[
                            MedPhotoThumb(path: med.photoPath, name: med.name, size: 72, fallback: const SizedBox.shrink()),
                            const SizedBox(width: F.s12),
                          ],
                          Expanded(
                            child: Text(
                              med.name,
                              style: TextStyle(
                                fontSize: F.questionSize,
                                fontWeight: FontWeight.w700,
                                color: F.ink,
                                fontFamily: F.monoFamily,
                                fontFamilyFallback: F.monoFallback,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: F.gap),
                      Text(
                        'إمتى؟',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                      ),
                      const SizedBox(height: F.s8),
                      for (final (i, schedule) in _schedules.indexed)
                        DoseRow(
                          key: ValueKey('dose-row-$i'),
                          timing: schedule.timing,
                          time: arabicTime(ScheduleEngine(_routine).resolve(schedule, DateTime.now())),
                          onEdit: () => _editTiming(schedule, med.name),
                          // الأرضية: آخر جرعة مالهاش «شيل» خالص — دوا من
                          // غير جرعة مش دوا، وزرار رمادي كان هيخلّيه يدوس
                          // ويستنى حاجة تحصل.
                          onRemove: _schedules.length > 1 && !_busy
                              ? () => _removeTiming(schedule)
                              : null,
                        ),
                      SizedBox(
                        height: F.minTapTarget,
                        child: FSecondaryButton(
                          label: 'أضف جرعة',
                          onPressed: _busy ? null : () => _addTiming(med.name),
                        ),
                      ),
                      const SizedBox(height: F.s8),
                      FSecondaryButton(
                        key: const ValueKey('make-every-hours'),
                        label: 'خليه كل كام ساعة',
                        onPressed: _busy ? null : () => _makeEveryHours(med.name),
                      ),
                      const SizedBox(height: F.s8),
                      if (dayPatternLabel(_schedules.firstOrNull?.days ?? DayPattern.everyDay) case final label?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: F.s8),
                          child: Text(label,
                              key: const ValueKey('days-label'),
                              style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                        ),
                      FSecondaryButton(
                        key: const ValueKey('change-days'),
                        label: 'غيّر الأيام',
                        onPressed: _busy ? null : _changeDays,
                      ),
                      const SizedBox(height: F.gap),
                      Text(
                        'الجرعة',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                      ),
                      const SizedBox(height: 8),
                      if (med.amountUnknown) ...[
                        // الذهبي هنا بمعناه الواحد: ده محتاج انتباهك.
                        const GoldNote('الورقة ما قالتش الجرعة — اسأل الصيدلي واكتبها هنا.'),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        textInputAction: TextInputAction.done,
                        controller: _amount,
                        style: const TextStyle(fontSize: F.minBodySize),
                        decoration: InputDecoration(
                          hintText: 'زي: قرص واحد',
                          hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                          filled: true,
                          fillColor: F.fieldGround,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(F.radius),
                            borderSide: BorderSide(color: F.line),
                          ),
                        ),
                      ),
                      const SizedBox(height: F.gap),
                      StockSection(medicationId: med.id, name: med.name, amountLabel: med.amountLabel),
                      const SizedBox(height: F.gap),
                      FutureBuilder<File?>(
                        future: AppScope.of(context).medPhotoStore.fileFor(med.photoPath ?? ''),
                        builder: (context, file) => MedPhotoSlot(
                          previewFile: med.photoPath == null ? null : file.data,
                          onPicked: (bytes) {
                            final services = AppScope.of(context);
                            MedPhotos(services.db, services.medPhotoStore)
                                .setFromBytes(med.id, bytes)
                                .then((_) => services.syncMedPhotosSoon());
                          },
                          onRemove: () {
                            final services = AppScope.of(context);
                            MedPhotos(services.db, services.medPhotoStore).clear(med.id).then((_) => services.syncMedPhotosSoon());
                          },
                        ),
                      ),
                      const SizedBox(height: F.gap),
                      // المدة والتعليمات هنا بس — «ضيف دوا» ما بتسألش عنهم
                      Text(
                        'المدة',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: AnchorChip(
                              key: const ValueKey('duration-open'),
                              label: 'مفتوحة',
                              selected: _openEnded,
                              onTap: () => setState(() => _openEnded = true),
                            ),
                          ),
                          const SizedBox(width: F.s8),
                          Expanded(
                            child: AnchorChip(
                              key: const ValueKey('duration-days'),
                              label: 'أيام محددة',
                              selected: !_openEnded,
                              onTap: () => setState(() => _openEnded = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: F.s10),
                      if (!_openEnded)
                        FNumberWheel(
                          key: const ValueKey('days-wheel'),
                          value: _days,
                          min: 1,
                          max: 90,
                          unit: 'يوم',
                          semanticsLabel: 'المدة بالأيام',
                          onChanged: (value) => setState(() => _days = value),
                        )
                      else
                        Text(
                          'التذكير هيفضل شغال لحد ما توقفه بنفسك.',
                          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                        ),
                      const SizedBox(height: F.gap),
                      Text(
                        'تعليمات (اختياري)',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('instructions-field'),
                        textInputAction: TextInputAction.newline,
                        controller: _instructions,
                        minLines: 1,
                        maxLines: 3,
                        style: const TextStyle(fontSize: F.minBodySize),
                        decoration: InputDecoration(
                          hintText: 'زي: مع كوباية مية كاملة',
                          hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                          filled: true,
                          fillColor: F.fieldGround,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(F.radius),
                            borderSide: BorderSide(color: F.line),
                          ),
                        ),
                      ),
                      const SizedBox(height: F.gap),
                      Text(
                        'نوع التنبيه',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                      ),
                      const SizedBox(height: 8),
                      // بيتحفظ على طول وبيعيد الجدولة — الإعادات بتتبني وقت الجدولة
                      AlertModeChips(
                        value: AlertMode.fromStorage(med.alertMode),
                        allowDefault: true,
                        defaultMode: _deviceMode,
                        onChanged: _busy ? (_) {} : (m) => _setAlertMode(m),
                      ),
                      const SizedBox(height: F.gap + 6),
                      if (_confirmingStop) _StopConfirm(
                        name: med.name,
                        busy: _busy,
                        onStop: _stop,
                        onKeep: () => setState(() => _confirmingStop = false),
                      ) else
                        SizedBox(
                          height: F.minTapTarget,
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => setState(() => _confirmingStop = true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: F.ink,
                              side: BorderSide(color: F.ink, width: 1.5),
                            ),
                            child: const Text(
                              'وقّف الدوا ده',
                              style: TextStyle(fontSize: F.minTextSize + 1, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'ملحوظة: خلّصت العلبة أو الدكتور غيّر الدوا؟ وقّفه من هنا. '
                        'التطبيق عمره ما بيوقف دوا لوحده'
                        '${_durationNote(med)}',
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(F.gap),
                  child: SizedBox(
                    width: double.infinity,
                    height: F.primaryButtonHeight,
                    child: FilledButton(
                      onPressed: _busy || _confirmingStop ? null : _save,
                      child: const Text('احفظ'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _durationNote(MedicationRow med) {
    final days = _schedules.map((s) => s.durationDays).whereType<int>();
    if (days.isEmpty) return '.';
    return ' — العلاج ده ${arabicNumber(days.first)} يوم وبعدها بيوقف لوحده.';
  }
}

/// خطوة التأكيد — سؤال واضح وجوابين بنفس الحجم. من غير أحمر.
class _StopConfirm extends StatelessWidget {
  const _StopConfirm({
    required this.name,
    required this.busy,
    required this.onStop,
    required this.onKeep,
  });

  final String name;
  final bool busy;
  final VoidCallback onStop;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.ink, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'توقّف $name؟ التذكيرات هتقف لحد ما تضيفه تاني.',
              style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: F.minTapTarget,
                    child: FilledButton(
                      onPressed: busy ? null : onStop,
                      style: FilledButton.styleFrom(
                        backgroundColor: F.ink,
                        foregroundColor: F.onDark,
                        minimumSize: const Size.fromHeight(F.minTapTarget),
                      ),
                      child: const Text('أيوه، وقّفه'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: F.minTapTarget,
                    child: OutlinedButton(
                      onPressed: busy ? null : onKeep,
                      child: const Text(
                        'لا، سيبه',
                        style: TextStyle(fontSize: F.minTextSize + 1, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
