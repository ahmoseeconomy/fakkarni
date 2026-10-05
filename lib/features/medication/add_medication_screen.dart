import '../../domain/medication/medicine_name.dart';
import 'dart:async';
import '../voice/help_button.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/repositories/stock_repository.dart';
import '../../data/repositories/stock_unit_store.dart';
import '../../domain/medication/stock.dart' show resolveStockUnit, stockLeftQuestion, stockUnitOf, unknownStockUnit;
import 'stock_left_card.dart';

import '../../ai/package_reading.dart';
import 'scan_package_screen.dart' show unreadablePackage;
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/escalation/alert_mode.dart';
import '../../domain/medication/duplicate_check.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/medication/medicine_form.dart';
import '../../domain/medication/meal_relation.dart';
import '../../domain/scheduling/minute_of_day.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../../domain/wording/rule_wording.dart';
import '../../core/widgets/f_wheels.dart';
import 'alert_mode_chips.dart';
import 'dose_editor.dart' show DoseEditor;
import 'med_photo.dart';
import '../../domain/scheduling/every_hours.dart';
import 'day_pattern_picker.dart';
import 'every_hours_picker.dart';
import '../../domain/scheduling/day_pattern.dart';
import 'medication_draft.dart';
import 'med_voice_input.dart';
import '../../domain/voice/nlu/nlu.dart' show NluIntent, understandUtteranceAs;
import '../../domain/voice/answer_parser.dart' show normalizeArabic, parseTime, parseNumber;
import '../../domain/voice/nlu/normalize.dart' show normalizeUtterance, spokenAnswer;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/diagnostics.dart';

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
/// «بياخده إزاي» ← «كام مرة» ← الساعة (شرايح سريعة وبكرة) ← «مع الأكل؟»
/// (كلمة تعليمات، اختيارية) ← مواعيد الجرعات ← نوع التنبيه ← «احفظ».
///
/// **الساعة بالساعة وبس** (قرار المالك، ٢٧ سبتمبر ٢٠٢٦ — الروتين والمراسي
/// اتشالوا). «كام مرة» → ساعات افتراضية (`defaultTimesFor`): مرة ٩ص، مرتين
/// ٩ص و٩م، ٣ مرات ٩ و٣ و٩، ٤ مرات ٨ و١ و٦ و١١. أول ساعة يختارها بتوزّع
/// الباقي على اليوم بالتساوي — **قدّامه، في الصفوف، ومش بيتحفظ غير بدوسة
/// «احفظ»**. «قبل/مع/بعد الأكل» بقت كلمة تتعرض جنب الجرعة، ما بتحرّكش ساعة.
///
/// **ولا حاجة بتتحفظ قبل «احفظ»**، وفي وضع المسوّدة ولا بعده.
class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({
    this.today,
    this.initialName,
    this.initialAmount,
    this.initialAmountUnknown = false,
    this.initialStartDate,
    this.initialTimings = const [],
    this.initialEmptyDoses,
    this.initialEveryHours,
    this.initialDurationDays,
    this.initialOnce = false,
    this.initialAlertMode,
    this.initialPurpose,
    this.initialForm,
    this.initialInstructions,
    this.initialMealRelation,
    this.packageReading,
    this.packageImage,
    this.draft = false,
    this.voiceInput = true,
    super.key,
  });

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
  final List<FixedTiming> initialTimings;

  /// سطر روشتة من غير ساعات مكتوبة: كام صف **فاضي** («اختار الساعة»)
  /// من غير ساعات افتراضية — الروشتة ما بتختارش ساعة عن حد. null = العُرف.
  final int? initialEmptyDoses;

  /// «كل ١٢ ساعة» من «كلّمني» — النمط «كل كام ساعة» بالفاصل ده. أول جرعة
  /// بيختارها هو على البكرة زي أي مرة.
  final int? initialEveryHours;
  final int? initialDurationDays;

  /// الدوا ده «مرة واحدة» (`DoseRepeat.once`).
  final bool initialOnce;
  final AlertMode? initialAlertMode;
  final MedicationPurpose? initialPurpose;

  /// نوع الدوا من المسوّدة (عدّل في المراجعة) — العلبة بتملاه لوحدها لو واضح.
  final MedicineForm? initialForm;
  final String? initialInstructions;

  /// «قبل الأكل» وأخواتها من الروشتة أو المسوّدة — كلمة تعليمات، مش توقيت.
  final MealRelation? initialMealRelation;

  /// اللي اتقرا من صورة علبة — **حقول وبس، ولا موعد فيهم**.
  final PackageReading? packageReading;

  /// صورة العلبة اللي اتقرت — بتتعرض «استخدم صورة العلبة» في خانة الصورة.
  final Uint8List? packageImage;

  /// الصوت على الفورم — «قولها بصوتك» ومايكات الحقول. **false على موبايل
  /// الممرض** (قرار المالك، ٥ أكتوبر ٢٠٢٦): الصوت للمريض وبس.
  final bool voiceInput;

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

/// بياخده إزاي: كل يوم (المراسي أو ساعات)، كل كام ساعة (بيتفرد لساعات
/// ثابتة)، أو مرة واحدة (`DoseRepeat.once`).
enum DosePattern { daily, everyHours, weekdays, everyNDays, cycle, once }

/// كلمة النمط — كانت على الشرايح، والبكرة والصوت بيقروا منها.
String patternLabel(DosePattern p) => switch (p) {
      DosePattern.daily => 'كل يوم',
      DosePattern.everyHours => 'كل كام ساعة',
      DosePattern.weekdays => 'أيام معينة',
      DosePattern.everyNDays => 'كل كام يوم',
      DosePattern.cycle => 'فترة وراحة',
      DosePattern.once => 'مرة واحدة',
    };

class _AddMedicationScreenState extends State<AddMedicationScreen> with WidgetsBindingObserver {
  /// صوت الفورم — null = مفيش صوت على الشاشة دي (ممرض، أو مفيش متعرّف).
  MedVoiceSession? _voice;
  bool _voiceWired = false;

  /// «أدخّل بصوتي» (المالك، ٥ أكتوبر ٢٠٢٦) — **مقفول افتراضياً**: مقفول =
  /// مفيش مايك حقول و«ساعدني» ظاهر؛ مفتوح = مايك على كل قسم بيتعبّى
  /// بالصوت و«ساعدني» بيستخبى. «قولها بصوتك» ظاهر في الحالتين. متخزّن
  /// على الموبايل ([micsKey]) عشان اللي بيدخّل بصوته ما يفتحهوش كل مرة.
  static const micsKey = 'voice.formMics';
  bool _micsOn = false;

  /// مايكات الحقول ظاهرة؟
  bool get _mics => _voice != null && _micsOn;

  Future<void> _setMics(bool on) async {
    setState(() => _micsOn = on);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(micsKey, on);
    } catch (_) {
      // تفضيل — مش أهم من الشاشة
    }
  }

  // «لا» اللي اتسمعت مع «ضيف دوا» مش اسم — الحقل يبدأ فاضي
  late final _name = TextEditingController(text: medicineNameOrNull(widget.initialName) ?? '');
  late final _amount = TextEditingController(text: widget.initialAmount ?? '');
  late final _instructions = TextEditingController(text: widget.initialInstructions ?? '');
  int _timesPerDay = 1;

  /// «قبل الأكل» وأخواتها — كلمة تعليمات، اختيارية. null = مفيش.
  MealRelation? _meal;

  /// «كل يوم» افتراضياً — نفس الفورم اللي كان.
  DosePattern _pattern = DosePattern.daily;

  /// «كل كام ساعة»: الفاصل وأول جرعة (العجلة بتقف على ٨ الصبح).
  int _everyHours = 8;
  /// أول جرعة في «كل كام ساعة» — **null لحد ما يختارها** (يحرّك البكرة أو
  /// يأكّد مكانها). مكان البكرة لوحده مش ساعة اتختارت، و«احفظ» مقفول.
  MinuteOfDay? _firstDose;

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

  /// نوع الدوا — اختياري. من العلبة لو الكلمة واضحة، وإلا فاضي.
  MedicineForm? _form;

  /// جرعات اليوم — صف لكل واحدة، **في الذاكرة، ولسه ما اتحفظتش**.
  /// null = ساعة لسه ما اتختارتش.
  List<FixedTiming?> _doses = const [];

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

  /// «ده إيه؟» لما الجرعة ما بتقولش — بيتحفظ على الموبايل ده بعد الحفظ.
  String? _stockUnit;

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
    _form = widget.initialForm ?? MedicineForm.fromPackageText(widget.packageReading?.formField);
    _meal = widget.initialMealRelation;
    if (widget.initialStartDate case final d?) _startDate = DateTime(d.year, d.month, d.day);
    // «اليوم فقط» من الورقة = «مرة واحدة» (نفس السلوك بالظبط، بكلمته)
    if (widget.initialOnce || widget.initialDurationDays == 1) {
      _pattern = DosePattern.once;
      _openEnded = true;
    }
    final fixedTimes = [for (final t in widget.initialTimings) t.minuteOfDay];
    final hours = _pattern == DosePattern.daily ? everyHoursOf(fixedTimes) : null;
    if (hours != null) {
      _pattern = DosePattern.everyHours;
      _everyHours = hours;
      _firstDose = (fixedTimes..sort((a, b) => a.minutes.compareTo(b.minutes))).first;
    }
    if (widget.initialTimings.isNotEmpty) {
      _timesPerDay = widget.initialTimings.length;
      _customCount = _timesPerDay > _countChips.last;
      _doses = [...widget.initialTimings];
    } else if (widget.initialEmptyDoses case final n? when n > 0) {
      _timesPerDay = n;
      _customCount = n > _countChips.last;
      _doses = List<FixedTiming?>.filled(n, null);
    } else if (widget.packageReading != null) {
      // العلبة ما بتقولش ميعاد — صف فاضي «اختار الساعة»، مش ٩ مننا
      _doses = [null];
    } else {
      _doses = _fromConvention();
    }
    if (widget.initialEveryHours case final h? when widget.initialTimings.isEmpty && everyHoursChoices.contains(h)) {
      _pattern = DosePattern.everyHours;
      _everyHours = h;
      _expandEveryHours(); // أول جرعة لسه ما اتختارتش — الصفوف فاضية
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

  // ------------------------------------------------- الصوت (٥ أكتوبر ٢٠٢٦)

  /// (ب) الاسم باللي اتسمع — زي حقل الاسم في البداية: بيتكتب قدّامه،
  /// والفورم بيقول «ده مش اسم دوا» لو الكلام مش اسم.
  void _hearName(String text) {
    final heard = medicineNameOrNull(text) ?? text.trim();
    setState(() => _name.text = heard);
    if (_duplicateChecked) _checkDuplicate();
  }

  /// (ب) «للضغط» / «آه للضغط.» / «مضاد حيوي» — بيملا بكرة «لإيه؟» وبس.
  /// مطابقة متسامحة (contains على القايمة المقفولة) — المتعرّف الحقيقي
  /// بيرجّع جُمل بحشو وترقيم والتوكنة الصارمة كانت بتقع (المرحلة ٢).
  void _hearPurpose(String text) {
    final found = MedicationPurpose.fromSpokenText(spokenAnswer(text));
    if (found == null) {
      setState(() => _voice?.note = 'مافهمتش — قول زي «للضغط» أو «للسكر»، أو حرّك البكرة بإيدك.');
      return;
    }
    setState(() => _purpose = found);
  }

  /// (ب) «قرص» / «شراب يعني.» / «حباية» — بيملا بكرة «نوعه؟» وبس.
  /// نفس التسامح: contains على القايمة المقفولة (المرحلة ٢).
  void _hearForm(String text) {
    final found = MedicineForm.fromSpokenText(spokenAnswer(text));
    if (found == null) {
      setState(() => _voice?.note = 'مافهمتش — قول زي «قرص» أو «شراب»، أو حرّك البكرة بإيدك.');
      return;
    }
    setState(() => _form = found);
  }

  /// (ب) «بياخده إزاي؟» — «كل ١٢ ساعة» بينتقل للفاصل بساعاته، وأسماء
  /// الأنماط بكلمتها («أيام معينة» بتفتح اختيار الأيام والإنسان بيكمّل).
  void _hearPattern(String text) {
    final norm = spokenAnswer(text);
    final r = understandUtteranceAs(NluIntent.addMedication, 'ضيف دوا X $norm', now: DateTime.now());
    if (r.everyHours case final h? when everyHoursChoices.contains(h)) {
      _pickPattern(DosePattern.everyHours);
      setState(() {
        _everyHours = h;
        _expandEveryHours();
      });
      return;
    }
    final byLabel = {
      for (final p in DosePattern.values) normalizeUtterance(patternLabel(p)): p,
    };
    DosePattern? found;
    if (norm.contains('كل يوم')) found = DosePattern.daily;
    for (final e in byLabel.entries) {
      if (found != null) break;
      if (norm.contains(e.key)) found = e.value;
    }
    if (found == null) {
      setState(() => _voice?.note = 'مافهمتش — قول زي «كل يوم» أو «كل ١٢ ساعة»، أو حرّك البكرة بإيدك.');
      return;
    }
    if (widget.draft && const {DosePattern.weekdays, DosePattern.everyNDays, DosePattern.cycle}.contains(found)) {
      setState(() => _voice?.note = 'أنماط الأيام مش في مراجعة الروشتة — كمّل من «ضيف دوا».');
      return;
    }
    _pickPattern(found);
  }

  /// (ب) «كام مرة في اليوم؟» — «مرتين» / «٣ مرات» / رقم لوحده (١–١٢).
  void _hearCount(String text) {
    final clean = spokenAnswer(text);
    final r = understandUtteranceAs(NluIntent.addMedication, 'ضيف دوا X $clean', now: DateTime.now());
    final n = r.perDay ?? parseNumber(clean);
    if (n == null || n < 1 || n > _maxCount) {
      setState(() => _voice?.note = 'مافهمتش — قول زي «مرتين» أو «٣ مرات»، أو حرّك البكرة بإيدك.');
      return;
    }
    if (n <= _countChips.last) {
      _pickCount(n);
    } else {
      setState(() => _customCount = true);
      _pickCustomCount(n);
    }
  }

  /// (ب) «المواعيد» — ساعة أو أكتر بالواو: «تسعة الصبح وتسعة بالليل».
  /// كل ساعة لازم جزء يومها (مفيش تخمين)، والصفوف بتتكتب باللي اتقال.
  void _hearTimes(String text) {
    final parts = spokenAnswer(text).split(RegExp(r'\s+و(?=\S)|\sو\s'));
    final minutes = <int>{};
    for (final part in parts) {
      final t = parseTime(spokenAnswer(part));
      if (t == null) {
        setState(() => _voice?.note = 'مافهمتش «${part.trim()}» — قول الساعة بجزء يومها، زي «٩ الصبح».');
        return;
      }
      minutes.add(t.minutes);
    }
    if (minutes.isEmpty) {
      setState(() => _voice?.note = 'مافهمتش — قول زي «٩ الصبح و٩ بالليل».');
      return;
    }
    final sorted = minutes.toList()..sort();
    setState(() {
      _timesPerDay = sorted.length;
      _customCount = sorted.length > _countChips.last;
      _doses = [for (final m in sorted) FixedTiming(MinuteOfDay(m))];
      _spreadLive = false; // الساعات دي اتقالت — العجلة ما تلمسهاش
    });
  }

  /// (ب) «الساعة كام؟» — ساعة واحدة بجزء يومها («٩ الصبح»)، بتكتب أول
  /// جرعة والباقي بيتوزّع وراها زي البكرة بالظبط ([_pickFirstFixed]).
  void _hearFirstTime(String text) {
    final t = parseTime(spokenAnswer(text));
    if (t == null) {
      setState(() => _voice?.note = 'مافهمتش — قول الساعة بجزء يومها، زي «٩ الصبح».');
      return;
    }
    _pickFirstFixed(MinuteOfDay(t.minutes));
  }

  /// (ب) «مع الأكل؟» — كلمة الأكل من نفس قارئ «كلّمني»، و«من غير» بتمسح.
  void _hearMeal(String text) {
    final norm = spokenAnswer(text);
    if (norm.contains('من غير') || norm.contains('عادي') || norm.contains('ولا حاجه')) {
      setState(() => _meal = null);
      return;
    }
    var food = understandUtteranceAs(NluIntent.addMedication, 'ضيف دوا X $norm', now: DateTime.now()).food;
    // والكلمة بلفظها كمان — contains على الأربع كلمات المقفولة (المرحلة ٢)
    for (final m in MealRelation.values) {
      if (food != null) break;
      if (norm.contains(normalizeArabic(m.label))) food = m;
    }
    if (food == null) {
      setState(() => _voice?.note = 'مافهمتش — قول زي «بعد الأكل» أو «على معدة فاضية»، أو حرّك البكرة.');
      return;
    }
    setState(() => _meal = food);
  }

  // «البداية» و«نوع التنبيه» **مالهمش مايك** (قاعدة المالك، ٥ أكتوبر ٢٠٢٦
  // مساءً): سؤال إجابته ٤ زراير أو أقل الدوسة فيه أسرع وأدق من الكلام —
  // المايك للبكر وحقول النص وبس. `_hearStart` و`_hearAlert` اتشالوا معاها.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عمرنا ما نسمع في الخلفية — كانت في «قولها بصوتك» ونقلت للشاشة لما اتشال
    if (state != AppLifecycleState.resumed) unawaited(_voice?.cancel());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_voiceWired) return;
    _voiceWired = true;
    WidgetsBinding.instance.addObserver(this);
    // الصوت للمريض وبس (قرار المالك): شاشات الممرض بتبعت voiceInput: false
    final voice = AppScope.maybeOf(context)?.voice;
    if (widget.voiceInput && voice != null && voice.listener != null) {
      _voice = MedVoiceSession(voice);
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted) return;
        final on = prefs.getBool(micsKey) ?? false;
        if (on != _micsOn) setState(() => _micsOn = on);
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _amount.dispose();
    _instructions.dispose();
    super.dispose();
  }

  static const _countChips = [1, 2, 3, 4];
  static const _maxCount = 12;

  /// ساعات «كام مرة» الافتراضية — عُرف تشغيلي مش ورقة، وكل صف بيتعدّل.
  // صفوف فاضية «اختار الساعة» — الفورم ما بيختارش ساعة عن حد (٢٧ سبتمبر ٢٠٢٦)
  List<FixedTiming?> _fromConvention() => List<FixedTiming?>.filled(_timesPerDay, null);

  void _reseed(VoidCallback change) => setState(() {
        change();
        _doses = _fromConvention();
        // ساعات العُرف مش ساعات حد كتبها — أول ساعة بتوزّعهم لحد ما صف يتعدّل بإيده
        _spreadLive = _doses.length > 1;
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

  /// دوسة تانية على نفس الشريحة بتشيلها — اختيارية فعلاً، ومش بتلمس الساعات.
  void _pickPattern(DosePattern p) {
    if (_pattern == p) return;
    // بين «كل يوم» وأنماط الأيام: الأيام بس بتتغيّر، والمواعيد زي ما هي
    final keepTimes = _dailyLike;
    setState(() {
      _pattern = p;
      switch (p) {
        case DosePattern.everyHours:
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
          _timesPerDay = 1;
          _doses = _fromConvention();
      }
    });
  }

  /// «كل كام ساعة» → ٢٤÷ن جرعة بساعة ثابتة — **في الصفوف قدّامه**، وكل
  /// صف لسه بيتعدّل لوحده.
  void _expandEveryHours() {
    final first = _firstDose;
    if (first == null) {
      _timesPerDay = 24 ~/ _everyHours;
      _doses = List<FixedTiming?>.filled(_timesPerDay, null);
      return;
    }
    final times = everyHoursTimes(first, _everyHours);
    _timesPerDay = times.length;
    _doses = [for (final t in times) FixedTiming(t)];
  }

  /// الدوسة على صف: محرّر **الجرعة دي بس**، وبيرجع.
  Future<void> _editDose(int i) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    FixedTiming? picked;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => DoseEditor(
          name: _name.text.trim().isEmpty ? 'الدوا' : _name.text.trim(),
          today: widget.today,
          initialTiming: _doses[i],
          kicker: _doses.length == 1
              ? null
              : 'الجرعة ${arabicNumber(i + 1)} من ${arabicNumber(_doses.length)}',
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
      _spreadFrom(i, picked!.minuteOfDay);
    });
  }

  /// **أول ساعة بتوزّع الباقي على اليوم بالتساوي** — قدّامه في الصفوف، وكل
  /// صف بيتعدّل. نافذة اليوم ٧ ص لـ١١ م كعُرف تشغيلي (مفيش روتين).
  void _spreadFrom(int index, MinuteOfDay first, {bool force = false}) {
    if (_doses.length < 2) return;
    for (final (i, d) in _doses.indexed) {
      if (!force && i != index && d != null) return; // فيه صفوف اتحددت قبل كده — ما نلمسهاش
    }
    const wake = 7 * 60;
    const sleep = 23 * 60;
    const waking = sleep - wake;
    final step = waking ~/ _doses.length;
    for (var k = 0; k < _doses.length; k++) {
      if (k == index) continue;
      _doses[k] = FixedTiming(MinuteOfDay((first.minutes + (k - index) * step + 1440 * 2) % 1440));
    }
  }

  /// عجلة الساعة تحت «كام مرة» على طول: بتكتب **أول جرعة**، والباقي
  /// بيتوزّع وراها طول ما محدش عدّله بإيده.
  void _pickFirstFixed(MinuteOfDay m) => setState(() {
        final othersEmpty = _doses.skip(1).every((d) => d == null);
        final live = _spreadLive || othersEmpty;
        _doses[0] = FixedTiming(m);
        if (live) {
          _spreadFrom(0, m, force: true);
          _spreadLive = _doses.length > 1;
        }
      });

  bool _rowReady(FixedTiming? t) => t != null;

  bool get _ready =>
      !_busy &&
      !isNotAMedicineName(_name.text) &&
      _doses.isNotEmpty &&
      _doses.every(_rowReady) &&
      // «أيام معينة» من غير ولا يوم = مفيش جرعة ترن
      (_pattern != DosePattern.weekdays || _weekdays.isNotEmpty);

  /// الوحدة اتسألت (مش من النوع ولا من كلام الجرعة) — ساعتها بس اختيار
  /// الشخص بيتحفظ على الموبايل.
  bool get _unitIsAsked => _form?.stockUnit == null && stockUnitOf(_amount.text) == unknownStockUnit;

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
        mealRelation: _meal,
        form: _form,
      );

      if (widget.draft) {
        if (mounted) navigator.pop(result);
        return;
      }

      // الدوا والجدولة في خطوة واحدة — **قبل** المخزون والصورة: دول إضافات،
      // واستثناء في واحد منهم كان بيسيب الدوا محفوظ من غير ولا تذكير.
      final medicationId = await services.medicationSaves.add(
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
        mealRelation: result.mealRelation,
        form: result.form,
      );
      try {
        if (_stock case final stock?) {
          await StockRepository(services.db).setQuantity(medicationId, stock.toDouble());
          if (_stockUnit case final u? when _unitIsAsked) {
            await StockUnitStore.write(medicationId, u);
          }
        }
        if (_photo case final photo?) {
          // صورة ما اتفكّتش = الدوا بيتحفظ من غيرها، من غير كلام تقني
          await services.medPhotos.setFromBytes(medicationId, photo);
          // للدائرة (٠٠٢٩): في الخلفية، من غير ما حد يستنى
          services.syncMedPhotosSoon();
        }
      } catch (error) {
        diag('ضيف دوا: المخزون أو الصورة ما اتحفظوش — $error');
      }
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

  String _rowText(FixedTiming? t) {
    const engine = ScheduleEngine();
    final day = widget.today ?? DateTime.now();
    return switch (t) {
      null => 'اختار الساعة',
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
                  // «قولها بصوتك» اتشال من الفورم (المالك، ٥ أكتوبر مساءً) —
                  // الدوا كله بالصوت مكانه «كلّمني» على «يومك». اللي فاضل:
                  // المفتاح ومايكات الحقول.
                  if (_voice != null) ...[
                    // «أدخّل بصوتي» — مفتاح مايكات الحقول (مقفول افتراضياً):
                    // «ساعدني» و«قولها» كانوا بيزاحموا بعض، فواحد منهم بس
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'أدخّل بصوتي',
                            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                          ),
                        ),
                        Switch(
                          key: const ValueKey('voice-input-switch'),
                          value: _micsOn,
                          onChanged: _setMics,
                        ),
                      ],
                    ),
                    // سطر حالة الصوت اتنقل **جنب البكرة بتاعته** ([MicNote]
                    // تحت كل حقل) — المالك 1A، المرحلة ٢: السطر البعيد هنا
                    // كان بيتقري على الجهاز «ولا حاجة حصلت».
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
                        _SectionHead(
                          'اسم الدوا والتركيز',
                          mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'اسم الدوا', onHeard: _hearName) : null,
                        ),
                        _Field(
                          controller: _name,
                          hint: 'زي Concor 5mg',
                          mono: true,
                          // الكيبورد مفتوح على طول — اسم فاضي = أول حاجة بيكتبها
                          autofocus: _name.text.isEmpty,
                          onChanged: (_) {
                            setState(() {});
                            if (_duplicateChecked) _checkDuplicate();
                          },
                        ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'اسم الدوا'),
                        if (_name.text.trim().isNotEmpty && isNotAMedicineName(_name.text)) ...[
                          const SizedBox(height: F.s8),
                          Text(
                            'ده مش اسم دوا — اكتب اسمه زي ما هو على العلبة.',
                            key: const ValueKey('not-a-name'),
                            style: TextStyle(fontSize: F.minTextSize, color: F.ink),
                          ),
                        ],
                        const SizedBox(height: F.gap),
                        // --------------------------------------- لإيه؟
                        // بكرة مش ١٠ شرايح (طلب المدير، ٥ أكتوبر ٢٠٢٦) —
                        // أول صف «من غير تحديد» وبيكتب null
                        // «ساعدني» بيستخبى لما المايكات شغّالة — واحد منهم بس
                        _SectionHead(
                          'الدوا ده لإيه؟ (لو حابب)',
                          help: _mics ? null : 'help_purpose',
                          mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'الدوا ده لإيه', onHeard: _hearPurpose) : null,
                        ),
                        FChoiceWheel<MedicationPurpose>(
                          wheelKey: const ValueKey('purpose-wheel'),
                          choices: MedicationPurpose.values,
                          labelOf: (p) => p.label,
                          value: _purpose,
                          semanticsLabel: 'الدوا ده لإيه',
                          onChanged: (p) => setState(() => _purpose = p),
                        ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'الدوا ده لإيه'),
                        const SizedBox(height: F.gap),
                        // --------------------------------------- نوعه
                        // (طلب المدير، ٤ أكتوبر ٢٠٢٦) — هو اللي بيحدد وحدة المخزون
                        _SectionHead(
                          'نوعه؟ (لو حابب)',
                          mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'نوعه', onHeard: _hearForm) : null,
                        ),
                        FChoiceWheel<MedicineForm>(
                          wheelKey: const ValueKey('form-wheel'),
                          choices: MedicineForm.values,
                          labelOf: (f) => f.label,
                          value: _form,
                          semanticsLabel: 'نوع الدوا',
                          onChanged: (f) => setState(() => _form = f),
                        ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'نوعه'),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  // --------------------------------------- كام مرة + الأكل
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHead(
                          'بياخده إزاي؟',
                          help: _mics ? null : 'help_pattern',
                          mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'بياخده إزاي', onHeard: _hearPattern) : null,
                        ),
                        // بكرة مش ٦ شرايح (المالك، ٥ أكتوبر) — **من غير «من غير
                        // تحديد»**: القسم ده ليه افتراضي («كل يوم») والبكرة
                        // واقفة عليه. أطول شوية عشان الست اختيارات يبانوا.
                        FChoiceWheel<DosePattern>(
                          wheelKey: const ValueKey('pattern-wheel'),
                          noneLabel: null,
                          choices: [
                            for (final p in DosePattern.values)
                              // المراجعة (مسوّدة الروشتة) من غير أنماط الأيام
                              if (!widget.draft ||
                                  !const {DosePattern.weekdays, DosePattern.everyNDays, DosePattern.cycle}.contains(p))
                                p,
                          ],
                          labelOf: patternLabel,
                          value: _pattern,
                          height: wheelItemExtent * 4,
                          semanticsLabel: 'بياخده إزاي',
                          onChanged: (p) {
                            if (p != null) _pickPattern(p);
                          },
                        ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'بياخده إزاي'),
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
                        _SectionHead(
                          'كام مرة في اليوم؟',
                          mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'كام مرة', onHeard: _hearCount) : null,
                        ),
                        // بكرة — صف «أكتر» (صفر) بيفتح بكرة العدد ٥–١٢ زي
                        // الشريحة القديمة بالظبط. افتراضي «مرة» — مفيش
                        // «من غير تحديد»: القسم مالوش حالة فاضية.
                        FChoiceWheel<int>(
                          wheelKey: const ValueKey('count-wheel'),
                          noneLabel: null,
                          choices: const [1, 2, 3, 4, 0],
                          labelOf: (n) => switch (n) {
                            0 => 'أكتر',
                            1 => 'مرة',
                            2 => 'مرتين',
                            _ => '${arabicNumber(n)} مرات',
                          },
                          value: _customCount ? 0 : (_timesPerDay <= _countChips.last ? _timesPerDay : 0),
                          semanticsLabel: 'كام مرة في اليوم',
                          onChanged: (n) {
                            if (n == null) return;
                            if (n == 0) {
                              if (_customCount) return;
                              setState(() => _customCount = true);
                              _pickCustomCount(_countChips.last + 1);
                            } else {
                              _pickCount(n);
                            }
                          },
                        ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'كام مرة'),
                        if (_customCount) ...[
                          const SizedBox(height: F.s8),
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
                        // الساعة تحت «كام مرة» على طول: بتكتب أول جرعة، والباقي
                        // بيتوزّع وراها. البكرة وبس — الشرايح السريعة اتشالت
                        // (المالك، ٥ أكتوبر ٢٠٢٦ مساءً)، والمايك بيكتب عليها.
                        if (_doses.isNotEmpty) ...[
                          _SectionHead(
                            'الساعة كام؟',
                            mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'الساعة', onHeard: _hearFirstTime) : null,
                          ),
                          _InlineFixedClock(
                            key: const ValueKey('inline-fixed-clock'),
                            label: _doses.length == 1 ? 'الساعة' : 'ساعة الجرعة الأولى',
                            chosen: switch (_doses.first) {
                              FixedTiming(:final minuteOfDay) => minuteOfDay,
                              _ => null,
                            },
                            onChanged: _pickFirstFixed,
                          ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'الساعة'),
                          const SizedBox(height: F.gap),
                        ],
                        ],
                        // «قبل الأكل» وأخواتها — **كلمة تعليمات**، اختيارية، ما
                        // بتحرّكش الساعة. بكرة بأول صف «من غير تحديد» (المالك،
                        // ٥ أكتوبر) — اختياري فعلاً زي ما الدوسة التانية كانت.
                        _SectionHead(
                          'مع الأكل؟ (لو حابب)',
                          help: _mics ? null : 'help_timing',
                          mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'مع الأكل', onHeard: _hearMeal) : null,
                        ),
                        FChoiceWheel<MealRelation>(
                          wheelKey: const ValueKey('meal-wheel'),
                          choices: MealRelation.values,
                          labelOf: (m) => m.label,
                          value: _meal,
                          semanticsLabel: 'مع الأكل',
                          onChanged: (m) => setState(() => _meal = m),
                        ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'مع الأكل'),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  // -------------------------------------- مواعيد الجرعات
                  // جرعة واحدة في اليوم = الكارت مستخبي (المالك، ٥ أكتوبر
                  // ٢٠٢٦ مساءً): ساعتها بتتظبط من «الساعة كام؟» فوق، وصف
                  // واحد تحتها بيكرّر نفس الرقم من غير ما يضيف حاجة.
                  if (_doses.length >= 2) ...[
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHead(
                          'مواعيد الجرعات',
                          mic: _mics ? FieldMicButton(session: _voice!, forWhat: 'المواعيد', onHeard: _hearTimes) : null,
                        ),
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
                        const SizedBox(height: F.s8),
                        Text(
                          fromPaper
                              ? 'دي اللي فهمناها من الورقة — دوس على أي جرعة لو مش مظبوطة.'
                              : 'البكرة فوق بتختار أول ساعة، والباقي بيتوزّع على يومك — دوس على أي جرعة لو عايز تغيّرها.',
                          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                        ),
                        if (_mics) MicNote(session: _voice!, forWhat: 'المواعيد'),
                      ],
                    ),
                  ),
                  const SizedBox(height: F.s12),
                  ],
                  // ----------------------------------------- نوع التنبيه
                  FCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ٤ شرايح = مفيش مايك (قاعدة «٤ زراير أو أقل») —
                        // و«ساعدني» راجع دايماً مكانه.
                        const _SectionHead('نوع التنبيه', help: 'help_alert_mode'),
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
                        // زرارين = مفيش مايك (نفس قاعدة «نوع التنبيه»).
                        _SectionHead(
                          _pattern == DosePattern.once ? 'هتاخده يوم إيه؟' : 'هتبدأ الدوا من إمتى؟',
                          help: 'help_start_date',
                        ),
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
                          const SizedBox(height: F.s8),
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
                          // المرهم والبخاخة مالهمش مخزون (قرار المالك، ٤ أكتوبر ٢٠٢٦)
                          if (_form?.tracksStock ?? true) ...[
                          const SizedBox(height: F.gap),
                          // «باقي كام قرص؟» — كارت لوحده (طلب المالك، ٢٩ سبتمبر ٢٠٢٦)
                          if (!_askStock)
                            _CompactChip(
                              key: const ValueKey('add-stock-open'),
                              label: '${switch (resolveStockUnit(_amount.text, chosen: _stockUnit, form: _form)) {
                                final u? => stockLeftQuestion(u),
                                null => 'باقي كام؟',
                              }} (لو حابب)',
                              selected: false,
                              onTap: () => setState(() => _askStock = true),
                            )
                          else
                            StockLeftCard(
                              wheelKey: const ValueKey('add-stock-wheel'),
                              unit: resolveStockUnit(_amount.text, chosen: _stockUnit, form: _form),
                              unitChosen: _unitIsAsked,
                              value: _stock,
                              onUnit: (u) => setState(() => _stockUnit = u),
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
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: selected ? F.onGold : F.ink),
                ),
              ),
            ),
          ),
        ),
      );
}

/// ترويسة قسم — **نظام مسافات واحد** (المالك، ٥ أكتوبر مساءً: «قولها»
/// كان لازق في اللي تحته والمسافات مش متساوية): الكلمة (+«ساعدني» أو
/// مايك «قولها») في صف واحد، والمسافة من **تحت الصف كله** ([F.s8]) —
/// مش من جوّه الكلمة، فالمايك الـ٥٦ ما بيلزقش في عنصر القسم. وبين قسم
/// والتاني [F.gap] دايماً.
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.text, {this.help, this.mic});

  final String text;

  /// جملة «ساعدني» عن الخانة دي (الكتالوج) — null = من غير زرار.
  final String? help;

  /// مايك «قولها» بتاع القسم — null = مفيش (المفتاح مقفول أو قسم من
  /// غير صوت).
  final Widget? mic;

  @override
  Widget build(BuildContext context) {
    final label = _FieldLabel(text, help: help);
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s8),
      child: mic == null
          ? label
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Expanded(child: label), mic!],
            ),
    );
  }
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
    // المسافة بتاعة الترويسة بقت في [_SectionHead] — مش هنا
    return help == null ? label : HelpRow(id: help!, child: label);
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
          fontFamily: mono ? F.bodyFamily : null,
          fontFamilyFallback: mono ? F.fontFallback : null,
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
