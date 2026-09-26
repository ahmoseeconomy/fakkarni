import 'dart:async';
import '../voice/help_button.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/repositories/stock_repository.dart';
import '../../domain/medication/stock.dart' show stockUnitOf;

import '../../ai/package_reading.dart';
import 'scan_package_screen.dart' show unreadablePackage;
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/escalation/alert_mode.dart';
import '../../domain/medication/duplicate_check.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../../domain/wording/rule_wording.dart';
import '../../core/widgets/f_wheels.dart';
import 'alert_mode_chips.dart';
import 'dose_editor.dart' show DoseEditor;
import '../../data/files/med_photos.dart';
import 'med_photo.dart';
import '../../domain/scheduling/every_hours.dart';
import 'day_pattern_picker.dart';
import 'every_hours_picker.dart';
import '../../domain/scheduling/day_pattern.dart';
import 'medication_draft.dart';

/// «ضيف دوا» — **فورم واحد بيتلف من فوق لتحت، وكل حاجة ظاهرة.**
///
/// كان: حقول، وبعدين «كمّل»، وبعدين محرّر لكل جرعة ورا بعض، والحفظ بعد
/// الأخير. المختبِر قال «خطوات كتير ومقيّدة» — وكان معاه حق: تلات جرعات
/// = أربع شاشات لحاجة العُرف كان مظبّطها من الأول. دلوقتي كل الجرعات
/// **صفوف ظاهرة** في الفورم بساعتها المحسوبة، والدوسة على صف بتفتح
/// [DoseEditor] لـ**الصف ده بس** وبترجع. مفيش مشي إجباري، والرجوع عمره
/// ما يضيّع حاجة اتكتبت.
///
/// الترتيب من فوق: الاسم (الكيبورد مفتوح على طول) ← «لإيه؟» (اختياري) ←
/// «كام مرة» ← «قبل/مع/بعد الأكل» أو «ساعة محددة» ← مواعيد الجرعات ←
/// نوع التنبيه ← «تفاصيل أكتر» (الجرعة، المدة، التعليمات) ← «احفظ».
///
/// «كام مرة» → مراسي عُرف تشغيلي مش ورقة: ١× الفطار، ٢× الفطار والعشا،
/// ٣× الفطار والغدا والعشا، ٤× وكمان قبل النوم، ٥× وكمان الصحيان. و«ساعة
/// محددة»: أول ساعة يختارها، والباقي بيتوزّع على يومه بالتساوي — **قدّامه،
/// في الصفوف، ومش بيتحفظ غير بدوسة «احفظ»**.
///
/// **ولا حاجة بتتحفظ قبل «احفظ»**، وفي وضع المسوّدة ولا بعده.
class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({
    required this.routine,
    this.today,
    this.initialName,
    this.initialAmount,
    this.initialAmountUnknown = false,
    this.initialStartDate,
    this.initialTimings = const [],
    this.initialDurationDays,
    this.initialOnce = false,
    this.initialAlertMode,
    this.initialPurpose,
    this.initialInstructions,
    this.packageReading,
    this.packageImage,
    this.draft = false,
    super.key,
  });

  final DayRoutine routine;
  final DateTime? today;

  /// قيم مبدئية — من قراءة الروشتة. بتتعرض للتعديل، ما بتتحفظش لوحدها.
  final String? initialName;
  final String? initialAmount;

  /// الورقة ما قالتش الجرعة: لو سابها فاضية تفضل «مش معروفة» — الإدخال
  /// اليدوي الفاضي مش كده (شوف [_save]).
  final bool initialAmountUnknown;

  /// تاريخ بداية جاي من مسوّدة — null = النهارده.
  final DateTime? initialStartDate;

  /// **وضع المسوّدة**: بترجّع [MedicationDraft] من غير ما تكتب أي حاجة.
  ///
  /// شاشة مراجعة الروشتة بتستعملها كده: «عدّل» بتعدّل سطر في الذاكرة
  /// وبترجع، والكتابة كلها مرة واحدة عند «تمام».
  final bool draft;

  /// جرعات الروشتة **كلها** — فاضية يعني إدخال بإيد من الأول.
  final List<DoseTiming> initialTimings;
  final int? initialDurationDays;

  /// الدوا ده «مرة واحدة» (`DoseRepeat.once`).
  final bool initialOnce;
  final AlertMode? initialAlertMode;
  final MedicationPurpose? initialPurpose;
  final String? initialInstructions;

  /// اللي اتقرا من صورة علبة — **حقول وبس، ولا موعد فيهم**.
  final PackageReading? packageReading;

  /// صورة العلبة اللي اتقرت — بتتعرض «استخدم صورة العلبة» في خانة الصورة.
  final Uint8List? packageImage;

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

/// «قبل / مع / بعد الأكل» — أو ساعة محددة لكل جرعة.
enum TimingChoice { before, with_, after, fixed }

/// بياخده إزاي: كل يوم (المراسي أو ساعات)، كل كام ساعة (بيتفرد لساعات
/// ثابتة)، أو مرة واحدة (`DoseRepeat.once`).
enum DosePattern { daily, everyHours, weekdays, everyNDays, cycle, once }

/// مع الأكل: قبل / مع / بعد — بتحدد إزاحة المرساة الافتراضية. (اسم قديم
/// بيفضل عشان اللي بيقرا التاريخ.)
typedef FoodRelation = TimingChoice;

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _amount = TextEditingController(text: widget.initialAmount ?? '');
  late final _instructions = TextEditingController(text: widget.initialInstructions ?? '');
  int _timesPerDay = 1;
  TimingChoice _choice = TimingChoice.before;

  /// «كل يوم» افتراضياً — نفس الفورم اللي كان.
  DosePattern _pattern = DosePattern.daily;

  /// «كل كام ساعة»: الفاصل وأول جرعة (العجلة بتقف على ٨ الصبح).
  int _everyHours = 8;
  MinuteOfDay _firstDose = MinuteOfDay.hm(8, 0);

  /// الجولة ٢ — أنماط الأيام (من يوم البداية).
  Set<int> _weekdays = {};
  int _everyN = 2;
  int _cycleOn = 21;
  int _cycleOff = 7;

  /// الأيام اللي هتتسجّل على كل جدول. «كل كام ساعة» و«كل يوم» = كل يوم.
  DayPattern get _dayPattern => switch (_pattern) {
        DosePattern.weekdays when _weekdays.isNotEmpty => OnWeekdays(_weekdays),
        DosePattern.everyNDays => EveryNDays(_everyN),
        DosePattern.cycle => OnOffCycle(_cycleOn, _cycleOff),
        _ => DayPattern.everyDay,
      };

  /// الأنماط اللي بتحتاج «كام مرة» و«مع الأكل» زي «كل يوم».
  bool get _dailyLike =>
      _pattern == DosePattern.daily ||
      _pattern == DosePattern.weekdays ||
      _pattern == DosePattern.everyNDays ||
      _pattern == DosePattern.cycle;
  MedicationPurpose? _purpose;

  /// الروتين الحي: لما المحرّر يسأل «بتفطر الساعة كام؟» ويتحفظ الفطار،
  /// الصفوف بتشوفه متحدد.
  late DayRoutine _routine = widget.routine;

  /// جرعات اليوم — صف لكل واحدة، **في الذاكرة، ولسه ما اتحفظتش**.
  /// null = ساعة محددة لسه ما اتختارتش.
  List<DoseTiming?> _doses = const [];

  bool _customCount = false;
  bool _openEnded = true;
  int _days = 7;
  bool _busy = false;

  /// الصفوف التانية لسه ماشية ورا عجلة أول جرعة (اتوزّعت منها ومحدش لمسها
  /// بإيده) — فلفّ العجلة بيعيد توزيعها بدل ما أول دقيقة تثبّتها.
  bool _spreadLive = false;

  /// «هتبدأ الدوا من إمتى؟» — النهارده افتراضياً، أو يوم تاني لحد ٦٠ يوم.
  late DateTime _startDate = _today;

  /// المخزون الاختياري — null لحد ما العجلة تتحرّك.
  bool _askStock = false;
  int? _stock;

  /// صورة الدوا اللي اختارها — بايتس لحد الحفظ (بتتصغّر ويتشال الـEXIF
  /// وقت الحفظ). null = من غير صورة.
  Uint8List? _photo;

  DateTime get _today {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  /// آخر يوم مسموح يبدأ فيه.
  static const startDateSpanDays = 60;

  bool get _startsLater => _startDate.isAfter(_today);
  AlertMode? _alertMode;
  AlertMode? _deviceMode;

  /// دوا في القايمة بنفس الاسم أو نفس المادة — بيتعرض، ومش بيمنع.
  DuplicateMatch? _duplicate;
  bool _duplicateChecked = false;

  @override
  void initState() {
    super.initState();
    final days = widget.initialDurationDays;
    if (days != null) {
      _openEnded = false;
      _days = days.clamp(1, 90);
    }
    _alertMode = widget.initialAlertMode;
    _purpose = widget.initialPurpose;
    if (widget.initialStartDate case final d?) _startDate = DateTime(d.year, d.month, d.day);
    // «اليوم فقط» من الورقة = «مرة واحدة» (نفس السلوك بالظبط، بكلمته)
    if (widget.initialOnce || widget.initialDurationDays == 1) {
      _pattern = DosePattern.once;
      _openEnded = true;
    }
    final fixedTimes = [
      for (final t in widget.initialTimings)
        if (t case FixedTiming(:final minuteOfDay)) minuteOfDay,
    ];
    final hours = _pattern == DosePattern.daily && fixedTimes.length == widget.initialTimings.length
        ? everyHoursOf(fixedTimes)
        : null;
    if (hours != null) {
      _pattern = DosePattern.everyHours;
      _everyHours = hours;
      _firstDose = (fixedTimes..sort((a, b) => a.minutes.compareTo(b.minutes))).first;
    }
    if (widget.initialTimings.isNotEmpty) {
      _timesPerDay = widget.initialTimings.length;
      _customCount = _timesPerDay > _countChips.last;
      _doses = [...widget.initialTimings];
      if (widget.initialTimings.every((t) => t is FixedTiming)) {
        _choice = TimingChoice.fixed;
      } else if (widget.initialTimings.firstOrNull case AnchorTiming(:final offsetMinutes)) {
        _choice = offsetMinutes == 0
            ? TimingChoice.with_
            : offsetMinutes < 0
                ? TimingChoice.before
                : TimingChoice.after;
      }
    } else {
      _doses = _fromConvention();
    }
    if (widget.packageReading != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkDuplicate());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final device = (await AppScope.of(context).preferences.get()).alertMode;
      if (mounted) setState(() => _deviceMode = device);
    });
  }

  Future<void> _checkDuplicate() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      if (mounted && _duplicate != null) setState(() => _duplicate = null);
      return;
    }
    final services = AppScope.of(context);
    final rows = await services.medications.currentMedicines(services.patientId);
    if (!mounted) return;
    final match = findDuplicate(
      name: name,
      activeIngredient: widget.packageReading?.ingredientField,
      existing: rows,
    );
    setState(() {
      _duplicate = match;
      _duplicateChecked = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _instructions.dispose();
    super.dispose();
  }

  static const _countChips = [1, 2, 3, 4];
  static const _maxCount = 12;

  static const _pickOrder = [
    DayAnchor.breakfast,
    DayAnchor.dinner,
    DayAnchor.lunch,
    DayAnchor.sleep,
    DayAnchor.wake,
  ];

  static const _dayOrder = [
    DayAnchor.wake,
    DayAnchor.breakfast,
    DayAnchor.lunch,
    DayAnchor.dinner,
    DayAnchor.sleep,
  ];

  /// عُرف «كام مرة» + «مع الأكل» — مش الورقة. «ساعة محددة» = صفوف فاضية
  /// لحد ما يختار أول ساعة.
  List<DoseTiming?> _fromConvention() {
    if (_choice == TimingChoice.fixed) return List<DoseTiming?>.filled(_timesPerDay, null);
    final picked = [
      for (var i = 0; i < _timesPerDay; i++) _pickOrder[i % _pickOrder.length],
    ]..sort((a, b) => _dayOrder.indexOf(a).compareTo(_dayOrder.indexOf(b)));
    return [for (final anchor in picked) _withFood(anchor)];
  }

  DoseTiming _withFood(DayAnchor anchor) => AnchorTiming(
        anchor,
        switch (_choice) {
          TimingChoice.before => -defaultOffsetBefore(anchor),
          TimingChoice.with_ => 0,
          TimingChoice.after => 30,
          TimingChoice.fixed => 0,
        },
      );

  void _reseed(VoidCallback change) => setState(() {
        change();
        _doses = _fromConvention();
        _spreadLive = false;
      });

  void _pickCount(int n) {
    if (_timesPerDay == n && !_customCount) return;
    _reseed(() {
      _timesPerDay = n;
      _customCount = false;
    });
  }

  void _pickCustomCount(int n) => _reseed(() => _timesPerDay = n.clamp(_countChips.last + 1, _maxCount));

  static String _timesLabel(int n) => n <= 10 ? '${arabicNumber(n)} مرات' : '${arabicNumber(n)} مرة';

  void _pickChoice(TimingChoice c) {
    if (_choice == c) return;
    _reseed(() => _choice = c);
  }

  void _pickPattern(DosePattern p) {
    if (_pattern == p) return;
    // بين «كل يوم» وأنماط الأيام: الأيام بس بتتغيّر، والمواعيد زي ما هي
    final keepTimes = _dailyLike;
    setState(() {
      _pattern = p;
      switch (p) {
        case DosePattern.everyHours:
          _choice = TimingChoice.fixed;
          _customCount = false;
          _expandEveryHours();
        case DosePattern.once:
          _timesPerDay = 1;
          _customCount = false;
          _openEnded = true;
          _doses = _fromConvention();
        case DosePattern.daily:
        case DosePattern.weekdays:
        case DosePattern.everyNDays:
        case DosePattern.cycle:
          if (keepTimes) break;
          _choice = TimingChoice.before;
          _timesPerDay = 1;
          _doses = _fromConvention();
      }
    });
  }

  /// «كل كام ساعة» → ٢٤÷ن جرعة بساعة ثابتة — **في الصفوف قدّامه**، وكل
  /// صف لسه بيتعدّل لوحده.
  void _expandEveryHours() {
    final times = everyHoursTimes(_firstDose, _everyHours);
    _timesPerDay = times.length;
    _doses = [for (final t in times) FixedTiming(t)];
  }

  Future<void> _setAnchor(DayAnchor anchor, MinuteOfDay time) async {
    final services = AppScope.of(context);
    await services.routines.setAnchor(services.patientId, anchor, time);
    if (mounted) setState(() => _routine = _routine.withAnchor(anchor, time));
  }

  /// الدوسة على صف: محرّر **الجرعة دي بس**، وبيرجع.
  Future<void> _editDose(int i) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    DoseTiming? picked;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => DoseEditor(
          name: _name.text.trim().isEmpty ? 'الدوا' : _name.text.trim(),
          routine: _routine,
          today: widget.today,
          initialTiming: _doses[i],
          startFixed: _choice == TimingChoice.fixed,
          kicker: _doses.length == 1
              ? null
              : 'الجرعة ${arabicNumber(i + 1)} من ${arabicNumber(_doses.length)}',
          onSetAnchor: _setAnchor,
          onSave: (timing) async {
            picked = timing;
            navigator.pop();
          },
        ),
      ),
    );
    if (picked == null || !mounted) return; // رجع من غير ما يختار — الصف زي ما هو
    setState(() {
      _doses[i] = picked;
      _spreadLive = false; // صف اتعدّل بإيده — العجلة ما بتلمسوش تاني
      if (picked case FixedTiming(:final minuteOfDay)) _spreadFrom(i, minuteOfDay);
    });
  }

  /// **أول ساعة محددة بتوزّع الباقي على يومه بالتساوي** — قدّامه في الصفوف،
  /// وكل صف بيتعدّل. نافذة اليوم من صحيانه لنومه لو محددين، وإلا ٧ ص
  /// لـ١١ م كعُرف تشغيلي (مش من روتين افتراضي — هو اللي اختار أول ساعة).
  void _spreadFrom(int index, MinuteOfDay first, {bool force = false}) {
    if (_doses.length < 2) return;
    for (final (i, d) in _doses.indexed) {
      if (!force && i != index && d != null) return; // فيه صفوف اتحددت قبل كده — ما نلمسهاش
    }
    final wake = _routine.isSet(DayAnchor.wake) ? _routine.wake.minutes : 7 * 60;
    final sleep = _routine.isSet(DayAnchor.sleep) ? _routine.sleep.minutes : 23 * 60;
    var waking = (sleep - wake + 1440) % 1440;
    if (waking == 0) waking = 1440;
    final step = waking ~/ _doses.length;
    for (var k = 0; k < _doses.length; k++) {
      if (k == index) continue;
      _doses[k] = FixedTiming(MinuteOfDay((first.minutes + (k - index) * step + 1440 * 2) % 1440));
    }
  }

  /// عجلة «ساعة محددة» تحت الشرايح على طول: بتكتب **أول جرعة**، والباقي
  /// بيتوزّع وراها طول ما محدش عدّله بإيده. من غير لفّ مفيش ساعة اتاختارت.
  void _pickFirstFixed(MinuteOfDay m) => setState(() {
        final othersEmpty = _doses.skip(1).every((d) => d == null);
        final live = _spreadLive || othersEmpty;
        _doses[0] = FixedTiming(m);
        if (live) {
          _spreadFrom(0, m, force: true);
          _spreadLive = _doses.length > 1;
        }
      });

  bool _rowReady(DoseTiming? t) => switch (t) {
        null => false,
        AnchorTiming(:final anchor) => _routine.isSet(anchor),
        FixedTiming() => true,
      };

  bool get _ready =>
      !_busy &&
      _name.text.trim().isNotEmpty &&
      _doses.isNotEmpty &&
      _doses.every(_rowReady) &&
      // «أيام معينة» من غير ولا يوم = مفيش جرعة ترن
      (_pattern != DosePattern.weekdays || _weekdays.isNotEmpty);

  Future<void> _save() async {
    if (!_ready) return;
    setState(() => _busy = true);
    try {
      final services = AppScope.of(context);
      final navigator = Navigator.of(context);
      final amount = _amount.text.trim();
      final instructions = _instructions.text.trim();
      final result = MedicationDraft(
        name: _name.text.trim(),
        amountLabel: amount.isEmpty ? null : amount,
        // إدخال يدوي فاضي = «ما قالش»، مش «مش معروفة»: «اسأل الصيدلي» لجرعة
        // ورقة ما اتقرتش بس
        amountUnknown: amount.isEmpty && widget.initialAmountUnknown,
        timings: [for (final d in _doses) d!],
        durationDays: _pattern == DosePattern.once || _openEnded ? null : _days,
        once: _pattern == DosePattern.once,
        alertMode: _alertMode,
        purpose: _purpose,
        instructions: instructions.isEmpty ? null : instructions,
        startDate: _startDate,
      );

      if (widget.draft) {
        if (mounted) navigator.pop(result);
        return;
      }

      final medicationId = await services.medications.addMedicationWithDoses(
        patientId: services.patientId,
        name: result.name,
        amountLabel: result.amountLabel,
        amountUnknown: result.amountUnknown,
        timings: result.timings,
        startDate: _startDate,
        durationDays: result.durationDays,
        repeat: result.once ? DoseRepeat.once : DoseRepeat.daily,
        days: _dayPattern,
        activeIngredient: widget.packageReading?.ingredientField,
        alertMode: result.alertMode,
        purpose: result.purpose,
        instructions: result.instructions,
      );
      if (_stock case final stock?) {
        await StockRepository(services.db).setQuantity(medicationId, stock.toDouble());
      }
      if (_photo case final photo?) {
        // صورة ما اتفكّتش = الدوا بيتحفظ من غيرها، من غير كلام تقني
        await MedPhotos(services.db, services.medPhotoStore).setFromBytes(medicationId, photo);
        // للدائرة (٠٠٢٩): في الخلفية، من غير ما حد يستنى
        services.syncMedPhotosSoon();
      }
      await services.scheduler.rescheduleAll();
      // «تمام، اتحفظ» — بعد الحفظ والجدولة، مش قبلهم
      unawaited(services.voice?.speakLine('gen_saved'));
      if (mounted) navigator.pop(result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsLater ? _startDate : _today.add(const Duration(days: 1)),
      firstDate: _today,
      lastDate: _today.add(const Duration(days: startDateSpanDays)),
      helpText: 'هيبدأ يوم',
      confirmText: 'تمام',
      cancelText: 'رجوع',
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = DateTime(picked.year, picked.month, picked.day));
  }

  String _rowText(DoseTiming? t) {
    final engine = ScheduleEngine(_routine);
    final day = widget.today ?? DateTime.now();
    return switch (t) {
      null => 'اختار الساعة',
      AnchorTiming(:final anchor) when !_routine.isSet(anchor) => '${anchor.label} — مش متحدد',
      // بكلام البيت: «قبل الفطار بنص ساعة — ٧:٠٠ ص»، مش «الفطار − ٣٠ د»
      AnchorTiming(:final anchor, :final offsetMinutes) =>
        '${spokenTimingWording(anchor.label, offsetMinutes)} — ${arabicTime(engine.resolveTime(anchor: anchor, offsetMinutes: offsetMinutes, onDay: day))}',
      FixedTiming(:final minuteOfDay) =>
        spokenFixedWording(arabicTime(engine.resolveFixed(minuteOfDay: minuteOfDay, onDay: day))),
    };
  }

  @override
  Widget build(BuildContext context) {
    final fromPaper = widget.initialTimings.isNotEmpty;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
                children: [
                  Kicker(widget.packageReading == null ? 'إضافة يدوية' : 'من صورة العلبة'),
                  const SizedBox(height: F.s4),
                  Text(
                    'ضيف دوا وجرعته',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.gap),
                  if (widget.packageReading case final read?) ...[
                    _FromPhoto(reading: read),
                    const SizedBox(height: F.s12),
                  ],
                  if (_duplicate case final dup?) ...[
                    GoldNote(
                      key: const ValueKey('duplicate-warning'),
                      '${dup.message} لو ده نفس الدوا، ارجع وكمّل على اللي '
                      'عندك بدل ما تضيفه تاني.',
                    ),
                    const SizedBox(height: F.s12),
                  ],
                  // ---------------------------------------------- الاسم
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('اسم الدوا والتركيز'),
                        _Field(
                          controller: _name,
                          hint: 'زي Concor 5mg',
                          mono: true,
                          // الكيبورد مفتوح على طول — اسم فاضي = أول حاجة بيكتبها
                          autofocus: (widget.initialName ?? '').isEmpty,
                          onChanged: (_) {
                            setState(() {});
                            if (_duplicateChecked) _checkDuplicate();
                          },
                        ),
                        const SizedBox(height: F.gap),
                        // --------------------------------------- لإيه؟
                        const _FieldLabel('الدوا ده لإيه؟ (لو حابب)', help: 'help_purpose'),
                        Wrap(
                          spacing: F.s8,
                          runSpacing: F.s8,
                          children: [
                            for (final p in MedicationPurpose.values)
                              AnchorChip(
                                key: ValueKey('purpose-${p.name}'),
                                label: p.label,
                                selected: _purpose == p,
                                // دوسة تانية بتشيله — اختياري فعلاً
                                onTap: () => setState(() => _purpose = _purpose == p ? null : p),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  // --------------------------------------- كام مرة + الأكل
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('بياخده إزاي؟', help: 'help_pattern'),
                        Wrap(
                          spacing: F.s8,
                          runSpacing: F.s8,
                          children: [
                            for (final p in DosePattern.values)
                              // المراجعة (مسوّدة الروشتة) من غير أنماط الأيام — الجولة دي «ضيف دوا» والتعديل
                              if (!widget.draft ||
                                  !const {DosePattern.weekdays, DosePattern.everyNDays, DosePattern.cycle}.contains(p))
                              AnchorChip(
                                key: ValueKey('pattern-${p.name}'),
                                label: switch (p) {
                                  DosePattern.daily => 'كل يوم',
                                  DosePattern.everyHours => 'كل كام ساعة',
                                  DosePattern.weekdays => 'أيام معينة',
                                  DosePattern.everyNDays => 'كل كام يوم',
                                  DosePattern.cycle => 'فترة وراحة',
                                  DosePattern.once => 'مرة واحدة',
                                },
                                selected: _pattern == p,
                                onTap: () => _pickPattern(p),
                              ),
                          ],
                        ),
                        const SizedBox(height: F.gap),
                        if (_pattern == DosePattern.everyHours) ...[
                          EveryHoursPicker(
                            hours: _everyHours,
                            first: _firstDose,
                            onChanged: (h, t) => setState(() {
                              _everyHours = h;
                              _firstDose = t;
                              _expandEveryHours();
                            }),
                          ),
                        ] else ...[
                        if (_pattern == DosePattern.weekdays ||
                            _pattern == DosePattern.everyNDays ||
                            _pattern == DosePattern.cycle) ...[
                          DayPatternPicker(
                            pattern: _pattern,
                            weekdays: _weekdays,
                            everyN: _everyN,
                            cycleOn: _cycleOn,
                            cycleOff: _cycleOff,
                            start: _startDate,
                            today: _today,
                            onWeekdays: (d) => setState(() => _weekdays = d),
                            onEveryN: (n) => setState(() => _everyN = n),
                            onCycle: (on, off) => setState(() {
                              _cycleOn = on;
                              _cycleOff = off;
                            }),
                          ),
                          const SizedBox(height: F.gap),
                        ],
                        if (_dailyLike) ...[
                        const _FieldLabel('كام مرة في اليوم؟'),
                        Wrap(
                          spacing: F.s8,
                          runSpacing: F.s8,
                          children: [
                            for (final n in _countChips)
                              AnchorChip(
                                key: ValueKey('count-$n'),
                                label: switch (n) {
                                  1 => 'مرة',
                                  2 => 'مرتين',
                                  _ => '${arabicNumber(n)} مرات',
                                },
                                selected: !_customCount && _timesPerDay == n,
                                onTap: () => _pickCount(n),
                              ),
                            AnchorChip(
                              key: const ValueKey('count-more'),
                              label: 'أكتر',
                              selected: _customCount,
                              onTap: () {
                                if (_customCount) return;
                                setState(() => _customCount = true);
                                _pickCustomCount(_countChips.last + 1);
                              },
                            ),
                          ],
                        ),
                        if (_customCount) ...[
                          const SizedBox(height: F.s10),
                          FNumberWheel(
                            key: const ValueKey('count-field'),
                            value: _timesPerDay,
                            min: _countChips.last + 1,
                            max: _maxCount,
                            labelOf: _timesLabel,
                            semanticsLabel: 'كام مرة في اليوم',
                            onChanged: _pickCustomCount,
                          ),
                        ],
                        const SizedBox(height: F.gap),
                        ],
                        const _FieldLabel('مع الأكل؟'),
                        // شبكة ٢×٢ بعرض متساوي: أربعة في صف واحد كانوا بيقصّوا
                        // «ساعة محددة» على SE — والكلمة كاملة أهم من الصف الواحد.
                        for (final pair in const [
                          [TimingChoice.before, TimingChoice.with_],
                          [TimingChoice.after, TimingChoice.fixed],
                        ]) ...[
                          Row(
                            children: [
                              for (final c in pair) ...[
                                Expanded(
                                  child: _CompactChip(
                                    key: ValueKey('timing-${c.name}'),
                                    label: switch (c) {
                                      TimingChoice.before => 'قبل الأكل',
                                      TimingChoice.with_ => 'مع الأكل',
                                      TimingChoice.after => 'بعد الأكل',
                                      TimingChoice.fixed => 'ساعة محددة',
                                    },
                                    selected: _choice == c,
                                    onTap: () => _pickChoice(c),
                                  ),
                                ),
                                if (c != pair.last) const SizedBox(width: F.s8),
                              ],
                            ],
                          ),
                          if (pair.first != TimingChoice.after) const SizedBox(height: F.s8),
                        ],
                        // الساعة تحت الشرايح على طول (من الآيفون، ٢٦ سبتمبر
                        // ٢٠٢٦): كانت مستخبية في محرّر ورا صف «مواعيد الجرعات».
                        if (_choice == TimingChoice.fixed && _doses.isNotEmpty) ...[
                          const SizedBox(height: F.s12),
                          _InlineFixedClock(
                            key: const ValueKey('inline-fixed-clock'),
                            label: _doses.length == 1 ? 'الساعة' : 'ساعة الجرعة الأولى',
                            chosen: switch (_doses.first) {
                              FixedTiming(:final minuteOfDay) => minuteOfDay,
                              _ => null,
                            },
                            onChanged: _pickFirstFixed,
                          ),
                        ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  // -------------------------------------- مواعيد الجرعات
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('مواعيد الجرعات', help: 'help_timing'),
                        for (final (i, t) in _doses.indexed) ...[
                          _DoseRowTile(
                            key: ValueKey('dose-row-$i'),
                            title: 'الجرعة ${arabicNumber(i + 1)}',
                            subtitle: _rowText(t),
                            ready: _rowReady(t),
                            onTap: () => _editDose(i),
                          ),
                          if (i != _doses.length - 1) const SizedBox(height: F.s8),
                        ],
                        const SizedBox(height: F.s10),
                        Text(
                          fromPaper
                              ? 'دي اللي الورقة قالتها — دوس على أي جرعة لو مش مظبوطة.'
                              : _choice == TimingChoice.fixed
                                  ? 'البكرة فوق بتختار أول ساعة، والباقي بيتوزّع على يومك — دوس على أي جرعة لو عايز تغيّرها.'
                                  : _routine.isComplete
                                      ? 'الأوقات محسوبة من مراسي يومك — دوس على أي جرعة لو عايز تغيّرها.'
                                      : 'ما حدّدتش مواعيد يومك كلها — دوس على الجرعة وقول ميعاد الأكل مرة، أو اختار ساعة.',
                          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  // ----------------------------------------- نوع التنبيه
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('نوع التنبيه', help: 'help_alert_mode'),
                        AlertModeChips(
                          value: _alertMode,
                          allowDefault: true,
                          defaultMode: _deviceMode,
                          onChanged: (m) => setState(() => _alertMode = m),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  // ------------------------------------ هتبدأ الدوا من إمتى؟
                  // مكان «تفاصيل أكتر» (الجرعة والمدة والتعليمات بقوا على
                  // شاشة التعديل بس — الإضافة سؤال واحد أقل).
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FieldLabel(_pattern == DosePattern.once ? 'هتاخده يوم إيه؟' : 'هتبدأ الدوا من إمتى؟', help: 'help_start_date'),
                        Row(
                          children: [
                            Expanded(
                              child: _CompactChip(
                                key: const ValueKey('start-today'),
                                label: 'النهارده',
                                selected: !_startsLater,
                                onTap: () => setState(() => _startDate = _today),
                              ),
                            ),
                            const SizedBox(width: F.s8),
                            Expanded(
                              child: _CompactChip(
                                key: const ValueKey('start-later'),
                                label: 'يوم تاني',
                                selected: _startsLater,
                                onTap: _pickStartDate,
                              ),
                            ),
                          ],
                        ),
                        if (_startsLater) ...[
                          const SizedBox(height: F.s10),
                          // «بكرة» = اليوم اللي بعده **بالتقويم** — بالليل بعد نص الليل
                          // ده مش الليلة الجاية، والتاريخ مكتوب عشان ده يبان
                          Text(
                            _startDate == DateTime(_today.year, _today.month, _today.day + 1)
                                ? 'هيبدأ بكرة — ${arabicDate(_startDate)} — مفيش تذكير قبلها.'
                                : 'هيبدأ يوم ${arabicDate(_startDate)} — مفيش تذكير قبلها.',
                            key: const ValueKey('start-date-line'),
                            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
                          ),
                        ],
                        // المخزون — **اختياري**، سطر مقفول لحد ما يدوس عليه، والعجلة
                        // ما بتكتبش حاجة لحد ما تتحرّك. للحفظ بس (مش لمراجعة الروشتة).
                        if (!widget.draft) ...[
                          const SizedBox(height: F.gap),
                          if (!_askStock)
                            _CompactChip(
                              key: const ValueKey('add-stock-open'),
                              label: 'عندك كام ${stockUnitOf(_amount.text)} دلوقتي؟ (لو حابب)',
                              selected: false,
                              onTap: () => setState(() => _askStock = true),
                            )
                          else ...[
                            _FieldLabel('عندك كام ${stockUnitOf(_amount.text)} دلوقتي؟'),
                            FNumberWheel(
                              key: const ValueKey('add-stock-wheel'),
                              value: _stock,
                              rest: 30,
                              min: 0,
                              max: 500,
                              unit: stockUnitOf(_amount.text),
                              semanticsLabel: 'المخزون',
                              onChanged: (v) => setState(() => _stock = v),
                            ),
                          ],
                          const SizedBox(height: F.gap),
                          MedPhotoSlot(
                            previewBytes: _photo,
                            boxImage: widget.packageImage,
                            onPicked: (bytes) => setState(() => _photo = bytes),
                            onRemove: () => setState(() => _photo = null),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(F.gap),
              child: FPrimaryButton(
                key: const ValueKey('save-medication'),
                label: 'احفظ',
                onPressed: _ready ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// صف جرعة في الفورم: الرقم، والساعة اللي هترن فيها (أو السبب اللي مش
/// هترن عشانه)، وكلمة الفعل — الكارت كله هدف لمس.
/// عجلة الساعة الثابتة جوّه الفورم: الجملة اللي القاعدة ١ بتطلبها، والساعة
/// لما تتختار، والعجلة. بترتاح على ٨:٠٠ ص زي المحرّر، ومش بتكتب حاجة لحد
/// ما تتلفّ.
class _InlineFixedClock extends StatelessWidget {
  const _InlineFixedClock({required this.label, required this.chosen, required this.onChanged, super.key});

  static const rest = MinuteOfDay(8 * 60);

  final String label;
  final MinuteOfDay? chosen;
  final ValueChanged<MinuteOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = chosen ?? rest;
    final time = arabicTime(DateTime(2026, 1, 1, shown.hour, shown.minute));
    return Container(
      padding: const EdgeInsets.all(F.s12),
      decoration: BoxDecoration(
        color: F.railGround,
        borderRadius: BorderRadius.circular(F.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ساعة ثابتة — مش هتتحرك مع روتين يومك',
            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
          ),
          const SizedBox(height: F.s8),
          Text(
            chosen == null ? '$label — حرّك البكرة للساعة اللي عايزها' : '$label — $time',
            key: const ValueKey('inline-fixed-label'),
            style: TextStyle(fontSize: F.minBodySize, color: chosen == null ? F.mutedDark : F.ink, height: 1.5),
          ),
          const SizedBox(height: F.s8),
          FTimeWheel(value: shown, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _DoseRowTile extends StatelessWidget {
  const _DoseRowTile({
    required this.title,
    required this.subtitle,
    required this.ready,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: F.railGround,
        borderRadius: BorderRadius.circular(F.radiusTile),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radiusTile),
          child: Container(
            constraints: const BoxConstraints(minHeight: F.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(F.radiusTile),
              // الذهبي للي لسه محتاج قرار — نفس معناه في التطبيق
              border: Border.all(color: ready ? F.line : F.gold, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                      ),
                      const SizedBox(height: F.s4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: F.s8),
                Text(
                  ready ? 'عدّل' : 'اختار',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.green),
                ),
              ],
            ),
          ),
        ),
      );
}

/// شريحة ضيّقة — أربعة في صف واحد على SE، بخط ١٧.
class _CompactChip extends StatelessWidget {
  const _CompactChip({required this.label, required this.selected, required this.onTap, super.key});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: Material(
          color: selected ? F.gold : F.railGround,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusChip),
            side: BorderSide(color: selected ? F.gold : F.line, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusChip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: F.s4),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                ),
              ),
            ),
          ),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.help});
  final String text;

  /// جملة «ساعدني» عن الخانة دي (الكتالوج) — null = من غير زرار.
  final String? help;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s8),
      child: help == null ? label : HelpRow(id: help!, child: label),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.mono = false,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool mono;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        textInputAction: TextInputAction.next,
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        maxLines: 1,
        style: TextStyle(
          fontSize: F.minBodySize,
          fontFamily: mono ? F.monoFamily : null,
          fontFamilyFallback: mono ? F.monoFallback : null,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: F.minTextSize, color: F.placeholder),
          filled: true,
          fillColor: F.fieldGround,
          contentPadding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            borderSide: BorderSide(color: F.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            borderSide: BorderSide(color: F.line),
          ),
        ),
      );
}

/// **اللي اتقرا من الصورة، معلّم إنه اتقرا** — عشان يراجعه قبل ما يحفظ.
class _FromPhoto extends StatelessWidget {
  const _FromPhoto({required this.reading});

  final PackageReading reading;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (reading.ingredientField case final v?) ('المادة الفعّالة', v),
      if (reading.formField case final v?) ('الشكل', v),
      if (reading.packSizeField case final v?) ('في العلبة', v),
    ];
    final unclear = reading.unclear;
    return FCard(
      key: const ValueKey('from-photo'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 20, color: F.green),
              const SizedBox(width: F.s8),
              Expanded(
                child: Text(
                  'ده اللي قريناه من العلبة — راجعه',
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: F.s4),
              child: Text(
                '$label: $value',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
            ),
          if (unclear.isNotEmpty)
            Text(
              '$unreadablePackage (${unclear.join('، ')})',
              key: const ValueKey('unclear-fields'),
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
            ),
          const SizedBox(height: F.s8),
          Text(
            'العلبة ما بتقولش الجرعة ولا المواعيد — دي من الدكتور، وإنت '
            'اللي بتكتبها تحت.',
            style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.6),
          ),
        ],
      ),
    );
  }
}
