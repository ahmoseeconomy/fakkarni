import '../../../core/format/arabic_time.dart';
import '../../../domain/medication/meal_relation.dart';
import '../../../domain/medication/medication_purpose.dart';
import '../../../domain/medication/medicine_form.dart';
import '../../../domain/medication/medicine_name.dart';
import '../../../domain/scheduling/every_hours.dart';
import '../../../domain/scheduling/minute_of_day.dart';
import '../../../domain/voice/answer_parser.dart';
import '../../../domain/voice/nlu/nlu.dart';
import '../../../domain/voice/nlu/normalize.dart';

/// **«كلّمني» بيسأل عن الناقص** (E2، طلب المدير ٤ أكتوبر ٢٠٢٦) — دارت نقية.
///
/// كل فعل ليه خانات أساسية؛ الناقص بيتسأل عليه **واحد واحد**، والإجابة بتتقري
/// بنفس قراء «كلّمني». القواعد اللي ما بتتكسرش:
/// - **مفيش ساعة مننا**: «مرتين» من غير ساعات = سؤال لكل جرعة (مش ٩ و٩).
///   «كل ١٢ ساعة» محتاج أول جرعة بس — زي الفورم بالظبط.
/// - «الساعة ٩» من غير الصبح/بالليل = سؤال «الصبح ولا بالليل؟».
/// - إجابة مش مفهومة مرتين ورا بعض = الفورم بيتفتح متعبّي باللي معانا.
/// - مفيش كتابة هنا خالص — اللي بينده بيكتب بعد «أيوه» بس.

/// سؤال واحد على الشاشة. [id] رقم جملة ممدوح في `docs/voice/script_dialog_ar.md`
/// (لسه مش متسجّلة — السؤال مكتوب لحد E4).
class DialogQuestion {
  const DialogQuestion(this.id, this.text);
  final String id;
  final String text;
}

/// أقصى مرات نسأل نفس السؤال قبل ما نفتح الفورم.
const maxDialogTries = 2;

String _clock(int minutes) => arabicTime(DateTime(2026, 1, 1, 0, minutes));

/// ساعة من غير جزء يوم («٩») — الرقم، وإلا null.
int? bareHour(String text) {
  if (parseTime(text) != null) return null;
  final morning = parseTime('$text الصبح');
  return morning?.hour;
}

/// «الصبح ولا بالليل؟» لساعة [hour] — الإجابة بتتركّب مع الساعة.
SpokenTime? withPeriod(int hour, String answer) => parseTime('${arabicNumber(hour)} $answer');

// ================================================================== ضيف دوا

enum _MedAsk { name, count, firstTime, time, period, form, purpose }

class MedDialog {
  MedDialog._({
    this.name,
    this.amount,
    this.meal,
    this.durationDays,
    this.everyHours,
    this.count,
    List<int?>? times,
  }) : times = times ?? [];

  /// من الجملة الأولى («ضيف دوا كونكور مرتين بعد الأكل»).
  /// «عدّي» وأخواتها — السؤالين الاختياريين (النوع والغرض) بيتعدّوا بيها
  /// والخانة بتفضل فاضية (قرار المالك، ٥ أكتوبر ٢٠٢٦). السكوت بيعدّي برضه
  /// ([skipOptional] — الـflow بينده عليها).
  static const skipWords = {'عدي', 'عدى', 'مش عارف', 'معرفش', 'مش عارفه', 'سيبها', 'سيبه', 'مش فارقه', 'لا', 'ولا حاجه'};

  static bool _isSkip(String text) => skipWords.contains(normalizeArabic(text).trim());

  factory MedDialog.fromNlu(NluResult n) {
    final every = n.everyHours != null && 24 % n.everyHours! == 0 && n.everyHours! < 24 ? n.everyHours : null;
    final explicit = [for (final t in n.times) t.minutes];
    final count = every != null ? null : (n.perDay ?? (explicit.isNotEmpty || n.hourNeedsPeriod != null ? 1 : null));
    final d = MedDialog._(
      name: n.name,
      amount: n.doseText,
      meal: n.food,
      durationDays: n.durationDays,
      everyHours: every,
      count: count,
    )
      ..form = n.form
      ..purpose = n.purpose;
    if (count != null) {
      d.times.addAll(List<int?>.filled(count, null));
      for (var i = 0; i < explicit.length && i < count; i++) {
        d.times[i] = explicit[i];
      }
      if (explicit.isEmpty && n.hourNeedsPeriod != null) d._pendingHour = (index: 0, hour: n.hourNeedsPeriod!);
    } else if (every != null) {
      d.times.add(explicit.firstOrNull);
      if (explicit.isEmpty && n.hourNeedsPeriod != null) d._pendingHour = (index: 0, hour: n.hourNeedsPeriod!);
    }
    return d;
  }

  String? name;
  final String? amount;
  final MealRelation? meal;
  final int? durationDays;
  int? everyHours;
  int? count;

  /// «نوعه إيه؟» و«الدوا ده لإيه؟» — اختياريين: اتقالوا في الجملة = مفيش
  /// سؤال؛ «عدّي» أو سكوت = الخانة بتفضل فاضية. (٥ أكتوبر ٢٠٢٦.)
  MedicineForm? form;
  MedicationPurpose? purpose;
  bool _formAsked = false;
  bool _purposeAsked = false;
  int _formTries = 0;
  int _purposeTries = 0;

  /// ساعة كل جرعة (دقيقة اليوم) — null = لسه.
  final List<int?> times;
  ({int index, int hour})? _pendingHour;

  int tries = 0;

  _MedAsk? get _ask {
    if (name == null) return _MedAsk.name;
    if (_pendingHour != null) return _MedAsk.period;
    if (everyHours != null && times.first == null) return _MedAsk.firstTime;
    if (everyHours == null) {
      if (count == null) return _MedAsk.count;
      if (times.contains(null)) return _MedAsk.time;
    }
    // الاختياريين — بعد الاسم والساعات (قرار المالك)
    if (form == null && !_formAsked) return _MedAsk.form;
    if (purpose == null && !_purposeAsked) return _MedAsk.purpose;
    return null;
  }

  /// السؤال الحالي اختياري؟ — السكوت عليه بيعدّيه (الـflow بينده).
  bool skipOptional() {
    switch (_ask) {
      case _MedAsk.form:
        _formAsked = true;
        return true;
      case _MedAsk.purpose:
        _purposeAsked = true;
        return true;
      default:
        return false;
    }
  }

  bool get complete => _ask == null;

  DialogQuestion? get question => switch (_ask) {
        null => null,
        _MedAsk.name => const DialogQuestion('dlg_med_name', 'اسم الدوا إيه؟'),
        _MedAsk.count => const DialogQuestion('dlg_med_times', 'بتاخده كام مرة في اليوم، والساعة كام؟'),
        _MedAsk.firstTime => const DialogQuestion('dlg_med_hour', 'أول جرعة الساعة كام؟'),
        _MedAsk.time => DialogQuestion(
            'dlg_med_hour',
            count == 1 ? 'تاخده الساعة كام؟' : 'الجرعة رقم ${arabicNumber(times.indexOf(null) + 1)} الساعة كام؟',
          ),
        _MedAsk.period => DialogQuestion('dlg_part_of_day', 'الساعة ${arabicNumber(_pendingHour!.hour)} الصبح ولا بالليل؟'),
        _MedAsk.form => const DialogQuestion('dlg_med_form', 'نوعه إيه؟'),
        _MedAsk.purpose => const DialogQuestion('dlg_med_purpose', 'الدوا ده لإيه؟'),
      };

  /// الإجابة على السؤال الحالي — true = اتفهمت واتحطّت.
  bool answer(String text, {required DateTime now}) {
    final ok = _apply(text, now);
    tries = ok ? 0 : tries + 1;
    return ok;
  }

  bool _apply(String text, DateTime now) {
    switch (_ask) {
      case null:
        return false;
      case _MedAsk.name:
        final n = understandUtteranceAs(NluIntent.addMedication, 'ضيف دوا اسمه $text', now: now).name ??
            medicineNameOrNull(text.trim());
        if (n == null || n.trim().isEmpty) return false;
        name = n;
        return true;
      case _MedAsk.period:
        final p = _pendingHour!;
        final t = withPeriod(p.hour, text);
        if (t == null || !_free(t.minutes, except: p.index)) return false;
        times[p.index] = t.minutes;
        _pendingHour = null;
        return true;
      case _MedAsk.firstTime || _MedAsk.time:
        final i = _ask == _MedAsk.firstTime ? 0 : times.indexOf(null);
        final t = parseTime(text);
        if (t != null) {
          if (!_free(t.minutes, except: i)) return false;
          times[i] = t.minutes;
          return true;
        }
        final h = bareHour(text);
        if (h == null) return false;
        _pendingHour = (index: i, hour: h);
        return true;
      case _MedAsk.count:
        final n = understandUtteranceAs(NluIntent.addMedication, 'ضيف دوا $text', now: now);
        final every = n.everyHours != null && 24 % n.everyHours! == 0 && n.everyHours! < 24 ? n.everyHours : null;
        if (every != null) {
          everyHours = every;
          times
            ..clear()
            ..add(n.times.firstOrNull?.minutes);
          if (n.times.isEmpty && n.hourNeedsPeriod != null) _pendingHour = (index: 0, hour: n.hourNeedsPeriod!);
          return true;
        }
        final c = n.perDay ?? _bareCount(text);
        if (c == null || c < 1 || c > 6) return false;
        count = c;
        times
          ..clear()
          ..addAll(List<int?>.filled(c, null));
        if (n.times.isNotEmpty) times[0] = n.times.first.minutes;
        if (n.times.isEmpty && n.hourNeedsPeriod != null) _pendingHour = (index: 0, hour: n.hourNeedsPeriod!);
        return true;
      case _MedAsk.form:
        if (_isSkip(text)) {
          _formAsked = true;
          return true;
        }
        for (final t in utteranceTokens(normalizeUtterance(text))) {
          if (MedicineForm.fromSpoken(t) case final f?) {
            form = f;
            return true;
          }
        }
        // إجابة مش مفهومة مرتين على سؤال اختياري = عدّي بخانة فاضية —
        // مش الفورم: السؤال مش مستاهل يقطع الحوار
        if (_formTries++ >= 1) {
          _formAsked = true;
          return true;
        }
        return false;
      case _MedAsk.purpose:
        if (_isSkip(text)) {
          _purposeAsked = true;
          return true;
        }
        final tokens = utteranceTokens(normalizeUtterance(text));
        for (var i = 0; i < tokens.length; i++) {
          if (tokens[i] == 'مضاد' && i + 1 < tokens.length && tokens[i + 1].startsWith('حيوي')) {
            purpose = MedicationPurpose.antibiotic;
            return true;
          }
          if (MedicationPurpose.fromSpokenWord(tokens[i]) case final p?) {
            purpose = p;
            return true;
          }
        }
        if (_purposeTries++ >= 1) {
          _purposeAsked = true;
          return true;
        }
        return false;
    }
  }

  /// «تلاتة» / «٢» لوحدها — عدد المرات.
  static int? _bareCount(String text) {
    final t = normalizeArabic(text).trim();
    if (t.contains('مرتين')) return 2;
    if (t == 'مره' || t == 'مره واحده' || t == 'واحده') return 1;
    return parseNumber(text);
  }

  /// نفس الساعة مرتين لنفس الدوا = إجابة مش مقبولة.
  bool _free(int minute, {required int except}) {
    for (var i = 0; i < times.length; i++) {
      if (i != except && times[i] == minute) return false;
    }
    return true;
  }

  /// الساعات النهائية — بعد ما [complete].
  List<MinuteOfDay> get minutes {
    if (everyHours != null) return everyHoursTimes(MinuteOfDay(times.first!), everyHours!);
    return [for (final t in times) MinuteOfDay(t!)]..sort((a, b) => a.minutes.compareTo(b.minutes));
  }

  /// «Concor — الساعة ٩:٠٠ ص و٩:٠٠ م — بعد الأكل — الجرعة قرص — لمدة ٧ أيام».
  String summary({String? duplicateOf}) => [
        'هضيف ${name!}',
        if (form case final f?) f.label,
        if (purpose case final p?) p.label,
        'الساعة ${minutes.map((m) => _clock(m.minutes)).join(' و')}',
        if (meal case final m?) m.label,
        if (amount case final a?) 'الجرعة ${arabicDigits(a)}',
        if (durationDays case final d?) 'لمدة ${arabicNumber(d)} ${d <= 10 ? 'أيام' : 'يوم'}',
        if (duplicateOf != null) 'تنبيه: $duplicateOf عندك خلاص',
      ].join(' — ');
}

// ================================================================== احجز ميعاد

enum _ApptAsk { day, time, period }

class BookingDialog {
  BookingDialog({required this.lab, required this.title, this.doctor, this.day, this.time, int? hourNeedsPeriod})
      : _pendingHour = hourNeedsPeriod;

  final bool lab;

  /// «د. حسام» / «تحليل صورة دم» / «زيارة دكتور» — من الجملة، أو من دكاترته.
  final String title;

  /// الدكتور **من ملفه** (اتطابق قبل كده) — عمره ما بيتخترع.
  final String? doctor;
  DateTime? day;

  /// الساعة (دقيقة اليوم) — null = لسه أو «من غير ساعة».
  int? time;
  int? _pendingHour;

  /// «من غير ساعة» اتقالت — الساعة اختيارية.
  bool _noTime = false;
  int tries = 0;

  _ApptAsk? get _ask {
    if (day == null) return _ApptAsk.day;
    if (_pendingHour != null) return _ApptAsk.period;
    if (time == null && !_noTime) return _ApptAsk.time;
    return null;
  }

  bool get complete => _ask == null;

  DialogQuestion? get question => switch (_ask) {
        null => null,
        _ApptAsk.day => const DialogQuestion('dlg_appt_day', 'الميعاد يوم إيه؟'),
        _ApptAsk.time => const DialogQuestion('dlg_appt_time', 'الساعة كام؟ ولو مش عارف قول «من غير ساعة».'),
        _ApptAsk.period => DialogQuestion('dlg_part_of_day', 'الساعة ${arabicNumber(_pendingHour!)} الصبح ولا بالليل؟'),
      };

  bool answer(String text, {required DateTime now}) {
    final ok = _apply(text, now);
    tries = ok ? 0 : tries + 1;
    return ok;
  }

  bool _apply(String text, DateTime now) {
    switch (_ask) {
      case null:
        return false;
      case _ApptAsk.day:
        final n = understandUtteranceAs(NluIntent.bookAppointment, 'احجز ميعاد $text', now: now);
        final d = n.date;
        final today = DateTime(now.year, now.month, now.day);
        if (d == null || d.isBefore(today)) return false;
        day = d;
        if (n.time != null) time = n.time!.minutes;
        if (n.time == null && n.hourNeedsPeriod != null) _pendingHour = n.hourNeedsPeriod;
        return true;
      case _ApptAsk.time:
        final t = normalizeArabic(text).trim();
        if (t.contains('من غير') || t.contains('مش عارف') || t.contains('معرفش') || t == 'لا' || t == 'لأ') {
          _noTime = true;
          return true;
        }
        final parsed = parseTime(text);
        if (parsed != null) {
          time = parsed.minutes;
          return true;
        }
        final h = bareHour(text);
        if (h == null) return false;
        _pendingHour = h;
        return true;
      case _ApptAsk.period:
        final t = withPeriod(_pendingHour!, text);
        if (t == null) return false;
        time = t.minutes;
        _pendingHour = null;
        return true;
    }
  }

  /// «هحجز د. حسام — يوم الاتنين ١٢ أكتوبر — الساعة ٥:٠٠ م».
  String summary(String dayWords) => [
        'هحجز $title',
        dayWords,
        time == null ? 'من غير ساعة' : 'الساعة ${_clock(time!)}',
      ].join(' — ');
}
