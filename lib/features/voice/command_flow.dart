import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/command_reader.dart';
import '../../app/app_scope.dart';
import '../../core/diagnostics.dart';
import '../../core/format/arabic_time.dart';
import '../../data/db/tables.dart' show GlucoseContext;
import '../../data/repositories/dose_event_repository.dart';
import '../../data/repositories/not_bought_repository.dart';
import '../../data/repositories/readings_repository.dart';
import '../../data/repositories/records_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../data/repositories/visit_questions_repository.dart';
import '../../data/repositories/vitals_repository.dart';
import '../../data/services/appointment_card.dart';
import '../../data/voice/listen_health.dart';
import '../../data/voice/speech_listener.dart';
import '../../data/voice/voice_service.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/health/vitals.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/medication/stock.dart';
import '../../domain/medication/meal_relation.dart';
import '../../domain/scheduling/minute_of_day.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/voice/answer_parser.dart';
import '../../domain/voice/mic_state.dart';
import '../../domain/voice/voice_catalog.dart';
import '../../domain/voice/voice_time.dart';
import '../today/dose_actions.dart';
import '../../ai/prescription_timing.dart' show daysWord, hoursWord, timesPerDayWord;
import '../../domain/medication/medicine_name.dart';
import '../../domain/voice/nlu/nlu.dart';
import '../../domain/voice/phrases.dart';
import '../../domain/places/specialty.dart';
import '../../domain/health/doctor_match.dart';
import '../../data/dose_state.dart';
import '../../data/repositories/lab_results_repository.dart';
import '../health/usual_words.dart' show GlucoseContextWords;
import 'cloud_tools.dart';
import 'command_parser.dart';
import 'voice_flags.dart';
import '../adherence/weekly_summary_sources.dart';
import 'fact_answers.dart';

/// مراحل «كلّمني».
enum CommandPhase {
  idle,
  listening,

  /// «بفكّر…» — بنفهم (محلي، أو السحابة).
  thinking,

  /// سؤال متابعة واحد («الميعاد الساعة كام؟») — بيتقال وبيتكتب، وبعده سماع مرة.
  asking,

  /// اللي اتفهم مكتوب كبير + «صح كده؟» — مستنيين «أيوه».
  confirming,

  /// كذا جرعة تنفع — «أنهي واحد؟» بأزرار كبيرة.
  choosing,

  /// جملة بتتقال وتتقري (رد، أو «للدكتور») — وخلاص.
  answering,

  /// **اللي فهمناه بكلامنا** + «إنت قلت: …» + «صح كده» / «عيد كلامك» — مكتوب
  /// بس، من غير صوت. «صح كده» بيفتح الفورم متعبّي، والحفظ بزراره هو. من غير
  /// فعل ([CommandFlow.canConfirmReview] = false) = «مش متأكد إنت عايز إيه».
  reviewing,

  /// تعادل بين نيتين — «قصدك …؟» بزرار لكل واحدة.
  clarifying,

  /// «احجز عند د. حسن»: الدكتور بيتدوّر عليه في دكاترة المريض — كذا واحد =
  /// «أنهي واحد؟»، ومحدش = «مش لاقي …» ودوسة على دكاترته أو «القريب مني».
  /// **عمرنا ما نعمل دكتور من اسم اتقال لوحده.**
  pickingDoctor,
  done,
}

/// جرعة ممكن يكون قصدها — من نافذة «أخدته» نفسها.
class DoseCandidate {
  const DoseCandidate(this.dose, this.routineDay);
  final DoseEventView dose;
  final DateTime routineDay;
  String get label => '${dose.medicationName} — الساعة ${voiceTime(dose.scheduledAt)}';
}

/// «ضيفلي دوا» → الفورم العادي **متعبّي** — ولا حاجة بتتحفظ غير من «احفظ».
class AddMedPrefill {
  const AddMedPrefill({
    this.name,
    this.purpose,
    this.timings = const [],
    this.once = false,
    this.durationDays,
    this.startDate,
    this.mealRelation,
    this.amount,
    this.everyHours,
    this.emptyDoses,
  });
  final String? name;

  /// «٥٠٠» / «قرص واحد» — زي ما اتقالت، في خانة الجرعة (مش في الاسم).
  final String? amount;

  /// «كل ١٢ ساعة» — الفورم بيفتح على «كل كام ساعة» بالفاصل ده.
  final int? everyHours;

  /// «مرتين» من غير ساعات — صفوف فاضية بالعدد، **مش ساعات مننا**.
  final int? emptyDoses;
  final MedicationPurpose? purpose;
  final List<FixedTiming> timings;

  /// «بعد الفطار» → «بعد الأكل» — كلمة تعليمات على الفورم، مش ساعة.
  final MealRelation? mealRelation;
  final bool once;
  final int? durationDays;
  final DateTime? startDate;
}

/// «احجزلي ميعاد» → ورقة «ميعاد جديد» **متعبّية** — والحفظ بزرارها هي.
class AppointmentPrefill {
  const AppointmentPrefill({required this.kind, this.name, this.day, this.time, this.doctor, this.specialty});
  final FollowKind kind;

  /// التخصص اللي اتقال («دكتور بطنه» = باطنة) — في خانة التخصص في الورقة،
  /// والورقة هي اللي بتركّب الاسم (`bookingTitle`).
  final Specialty? specialty;

  /// دكتور **حقيقي** من دكاترة المريض — بيتسجّل على الميعاد.
  final String? doctor;
  final String? name;
  final DateTime? day;

  /// الساعة اللي اتقالت — في خانة الساعة، **مش في الاسم**.
  final MinuteOfDay? time;
}

/// «كلّمني» — طلب مفتوح: اسمع ← افهم على الموبايل ← (السحابة لو ما فهمناش)
/// ← سؤال متابعة واحد لو خانة أساسية ناقصة ← نفّذ **بنفس سكّة الزرار**.
///
/// - **فورم متعبّي**: «ضيف دوا» و«احجز ميعاد» بيفتحوا الفورم العادي باللي
///   اتفهم — مفيش حفظ غير من زراره ([onOpenAdd] / [onOpenAppointment]).
/// - **كارت تأكيد + «صح كده؟» المسجّلة** للكتابات الصغيرة: أخدته، أجّل،
///   قياس، سؤال للدكتور، اشتريته، الروتين — و«أيوه» بالإيد أو بالصوت
///   (`classifyReply`: الرفض الأول، مش واضح = نسأل تاني، وعمره ما يبقى ذكاء).
/// - **قراية بس**: الدوا الجاي، أدوية النهارده، المواعيد الجاية، المخزون —
///   رد مكتوب وبصوت الموبايل.
/// - أي سؤال طبي: `gen_no_medical` — ولا كلمة تانية. مش مفهوم: نسأل يعيد
///   مرة، والتانية `gen_try_hands`.
///
/// الصوت مقفول = نفس الجمل مكتوبة على الشاشة ([shown]) من غير ما تتقال.
class CommandFlow extends ChangeNotifier {
  CommandFlow({
    required this.voice,
    required this.services,
    required this.routineDay,
    required this.onOpenAdd,
    this.onOpenAppointment,
    this.onOpenNearby,
    this.reader,
    this.cloudAllowed,
    this.onCloudUsed,
    DateTime Function()? clock,
    Future<List<DoseEventView>> Function(DateTime day)? dosesFor,
    Future<Map<String, MedicationPurpose?>> Function()? purposesFor,
    Future<void> Function(String reason)? onStartFailure,
    Future<List<String>> Function()? doctorsFor,
    MicBreaker? breaker,
  })  : breaker = breaker ?? MicBreaker(),
        _doctorsFor = doctorsFor ??
            (() async => distinctDoctors([for (final r in await RecordsRepository(services.db).all(services.patientId)) r.doctor])),
        _clock = clock ?? DateTime.now,
        _onStartFailure = onStartFailure ?? recordListenProblem,
        _dosesFor = dosesFor ?? ((day) => services.events.watchDay(day).first),
        _purposesFor = purposesFor ??
            (() async => {
                  for (final s in await services.medications.watchActiveSummaries(services.patientId).first)
                    s.medication.name: MedicationPurpose.fromStorage(s.medication.purpose),
                });

  final VoiceService voice;
  final AppServices services;
  final DateTime routineDay;
  final Future<void> Function(String reason) _onStartFailure;

  /// المايك اتقفل على الشاشة دي (المتعرّف مش موجود، أو القاطع اشتغل) —
  /// «كلّمني» بيختفي.
  bool startFailed = false;

  /// ٥ وقعات في ١٠ ثواني ← المايك يتقفل على الشاشة دي (`webSpeechStt.js`).
  final MicBreaker breaker;

  /// سطر هادي تحت الدايرة وهي مرتاحة — مكتوب، ما بيتقالش.
  String? note;

  /// المايك مفتوح عشان «أيوه» / «لأ».
  bool _reply = false;

  /// اللي اتفهم — بيرجع مكانه بعد سماع الرد.
  String _understood = '';

  /// بيفتح الفورم متعبّي وبيرجّع «اتحفظ؟» — «تمام، عملتها» بعدها بس.
  final Future<bool> Function(AddMedPrefill prefill) onOpenAdd;

  /// بيفتح ورقة «ميعاد جديد» متعبّية وبيرجّع «اتحفظ؟».
  final Future<bool> Function(AppointmentPrefill prefill)? onOpenAppointment;

  /// «أقرب صيدلية» → «القريب مني» على النوع ده، على طول — و«أقرب دكتور
  /// عيون» على الدكاترة والتخصص ده.
  final Future<void> Function(NearbyPlace place, Specialty? specialty)? onOpenNearby;

  /// دكاترة المريض من ملفه — الحجز بيتطابق عليهم وبس.
  final Future<List<String>> Function() _doctorsFor;

  /// «أنهي دكتور؟» — دكاترة حقيقيين من ملفه.
  List<String> doctorOptions = const [];

  /// كل دكاترته — لـ«اختار من دكاترتك».
  List<String> savedDoctors = const [];

  /// الاسم اللي اتقال وملقيناهوش — الورقة بتقول «مش لاقي …».
  String? doctorMissing;
  NluResult? _bookingNlu;

  /// «مش لاقي دوا اسمه كده عندك» — أدويته كشرايح، والدوسة بتجاوب عن الدوا ده.
  List<String> medChoices = const [];
  Future<String> Function(List<String> names)? _medAnswer;

  /// اللي اتسمع زي ما هو — تحت اللي فهمناه، بهدوء («إنت قلت: …»).
  String heard = '';

  /// اللي فهمناه — للاختبار والتشخيص.
  NluResult? understood;

  /// «صح كده» بيعمل إيه — null = مفيش فعل (مش مفهوم).
  Future<void> Function()? _reviewAction;
  bool get canConfirmReview => _reviewAction != null;

  /// «قصدك …؟» — اختيار لكل نية.
  List<({String label, NluIntent intent})> clarifyOptions = const [];

  /// السحابة — null = مفيش (مفتاح ناقص).
  final VoiceCommandReader? reader;

  /// الحد اليومي (المرحلة ٤): false = `cmd_limit`.
  final bool Function()? cloudAllowed;
  final void Function()? onCloudUsed;

  final DateTime Function() _clock;
  final Future<List<DoseEventView>> Function(DateTime day) _dosesFor;
  final Future<Map<String, MedicationPurpose?>> Function() _purposesFor;

  CommandPhase phase = CommandPhase.idle;

  /// الجملة اللي على الشاشة دلوقتي — نفس اللي بيتقال.
  String shown = '';

  /// الكلام وهو بيتقال — بيتكتب في الورقة لحظة بلحظة.
  String partial = '';

  /// «تقدر تقولّي مثلاً…» — **مكتوبة** تحت «سامعك…» أول مرة خالص (ما بتتقالش:
  /// ولا جملة قبل المايك).
  String? hint;

  /// سماعات اتفتحت — دوسة واحدة = سماع واحد.
  int sessions = 0;
  VoiceCommand? command;
  List<DoseCandidate> candidates = const [];
  DoseCandidate? chosen;
  AddMedPrefill? prefill;
  AppointmentPrefill? appointmentPrefill;

  /// اللي هيتكتب لما يقول «أيوه» — الاختبار بيقرا إن مفيش كتابة قبلها.
  Future<void> Function()? _pendingWrite;

  /// أول تعثّر «مافهمتش»، والتاني ورا بعض «كمّل بإيدك».
  int failures = 0;
  bool _busy = false;
  bool _disposed = false;

  bool get available => voice.listener != null && !voice.micDenied && !startFailed;

  /// حالة الدايرة — نفس ماكينة `MicOrb` ([micStateLabel]).
  MicState get mic {
    if (startFailed || voice.micDenied) return MicState.off;
    return switch (phase) {
      CommandPhase.listening => MicState.listening,
      CommandPhase.thinking => MicState.thinking,
      _ when voice.speaking => MicState.speaking,
      CommandPhase.confirming => MicState.confirming,
      _ => MicState.idle,
    };
  }

  void _set(CommandPhase p, [String? text]) {
    if (_disposed) return;
    phase = p;
    if (text != null) shown = text;
    notifyListeners();
  }

  bool _interrupted(int gen) {
    if (gen == voice.interrupts) return false;
    if (phase != CommandPhase.idle) _set(CommandPhase.idle, '');
    return true;
  }

  /// جملة من الكتالوج: بتتكتب على الشاشة، وبتتقال لو الصوت شغّال.
  Future<void> _say(String id, {CommandPhase? phase}) async {
    _set(phase ?? this.phase, voiceLine(id));
    await voice.speakLine(id);
  }

  /// رد متغيّر: **مكتوب**، وبيتقال بس لو ليه جملة متركّبة من حتت ممدوح
  /// ([phrase]) — من غير أسامي. مفيش صوت موبايل (المالك، ٢٨ سبتمبر ٢٠٢٦).
  Future<void> _sayText(String text, {CommandPhase? phase, SpokenPhrase? phrase}) async {
    _set(phase ?? this.phase, text);
    if (phrase != null) await voice.speakPhrase(phrase);
  }

  /// دوسة «كلّمني».
  Future<void> start() async {
    final listener = voice.listener;
    if (listener == null || _busy || startFailed) return;
    _busy = true;
    try {
      _reply = false;
      note = null;
      final wasSpeaking = voice.speaking;
      await voice.stop();
      final gen = voice.interrupts;
      if (!await listener.hasPermission()) {
        await _say('lis_mic_permission', phase: CommandPhase.listening);
        if (_interrupted(gen)) return;
      }
      final failed = await listener.prepare();
      if (_interrupted(gen)) return;
      if (failed != null) {
        await _cantListen(failed);
        return;
      }
      // أول مرة خالص: «تقدر تقولّي مثلاً…» **مكتوبة** تحت «سامعك…» — مرة
      // واحدة في عمر التنزيلة، ومن غير ما تتقال قبل المايك
      hint = null;
      if (!voice.cmdHintDone) {
        await voice.markCmdHintDone();
        hint = voiceLine('cmd_hint');
      }
      await _round(gen, settle: wasSpeaking);
    } finally {
      _busy = false;
    }
  }

  Future<void> _round(int gen, {bool settle = false}) async {
    final listener = voice.listener!;
    command = null;
    candidates = const [];
    chosen = null;
    prefill = null;
    appointmentPrefill = null;
    _pendingWrite = null;
    _reviewAction = null;
    understood = null;
    clarifyOptions = const [];
    doctorOptions = const [];
    doctorMissing = null;
    medChoices = const [];
    _medAnswer = null;
    heard = '';
    partial = '';
    // **الدوسة ← المايك على طول**: مفيش جملة قبله؛ النغمة من المتعرّف نفسه
    await voice.yieldToMic(settle: settle);
    if (_interrupted(gen)) return;
    final text = await _hear(listener, gen);
    if (text == null) return;
    await _understand(text, gen);
  }

  /// افهم: محلي الأول، والسحابة لو ما فهمناش — وبعدين نفّذ.
  Future<void> _understand(String text, int gen) async {
    final started = _clock();
    final now = _clock();
    _set(CommandPhase.thinking, 'بفكّر…');
    heard = text.trim();
    var cmd = parseCommand(text, now: now);
    var source = 'local';
    // الأربع نيات اللي كانت بتقع (أقرب مكان، ضيف دوا، احجز ميعاد، احجز
    // تحليل) بتتفهم بالـNLU الجديد؛ الباقي (أخدته، أجّل، قياس، طبي…) زي ما هو
    if (!_legacyOnly.contains(cmd.intent)) {
      final nlu = understandUtterance(text, now: now);
      if (nlu.isAmbiguous) {
        diag('Cmd: intent=ambiguous(${nlu.alternatives.map((i) => i.name).join('|')}) source=nlu');
        return _clarify(nlu.alternatives);
      }
      if (nlu.intent != NluIntent.none) {
        diag('Cmd: intent=${nlu.intent.name} source=nlu latency=${_clock().difference(started).inMilliseconds}ms');
        return _handleNlu(nlu, gen);
      }
    }
    // «الكونكور الجاي إمتى؟» من غير كلمة «دوا» — بس لو الاسم دوا عنده فعلاً
    if (cmd.intent == CommandIntent.unknown) {
      final own = await _ownMedicineQuestion(text);
      if (own != null) {
        diag('Cmd: intent=nextDose source=local-own-med');
        command = own;
        return _handle(own, gen);
      }
    }
    if (cmd.intent == CommandIntent.unknown && reader != null && voiceCommandsCloud) {
      if (cloudAllowed?.call() == false) {
        diag('Cmd: intent=unknown source=local — الحد اليومي خلص، مفيش سحابة');
        await _say('cmd_limit', phase: CommandPhase.answering);
        return;
      }
      source = 'cloud';
      await _say('cmd_thinking', phase: CommandPhase.thinking);
      if (_interrupted(gen)) return;
      onCloudUsed?.call();
      final result = await reader!.read(text, now: now);
      if (_interrupted(gen)) return;
      if (result.failed) {
        diag('Cmd: intent=unknown source=cloud latency=${result.latency.inMilliseconds}ms error=${result.error}');
        await _say('gen_try_hands', phase: CommandPhase.answering);
        return;
      }
      cmd = result.tool == null ? VoiceCommand.unknown : (commandFromCloudTool(result.tool!, now: now) ?? VoiceCommand.unknown);
      diag('Cmd: intent=${cmd.intent.name} source=cloud tool=${result.tool?.tool} latency=${result.latency.inMilliseconds}ms');
    } else {
      diag('Cmd: intent=${cmd.intent.name} source=$source latency=${_clock().difference(started).inMilliseconds}ms');
    }
    command = cmd;
    await _handle(cmd, gen);
  }

  /// سماع واحد: الكلام، أو null (راحة بسطر، وقعة، أو دوسة كسبت).
  /// «كلّمني» بيسمع لحد ٣٠ ثانية، وبيقفل بعد ٢٫٥ ثانية سكوت بعد آخر كلمة.
  Future<String?> _hear(SpeechListener listener, int gen) async {
    sessions++;
    _set(CommandPhase.listening, 'سامعك…');
    final result = await listener.listen(
      silence: ListenTimings.commandSilence,
      maxLength: ListenTimings.commandMaxLength,
      onPartial: (t) {
        if (phase != CommandPhase.listening || _disposed) return;
        partial = t;
        notifyListeners();
      },
    );
    // المايك اتقفل: من هنا الدوسة الجاية مسموحة — **حتى والموبايل لسه بيقول
    // الرد أو «صح كده؟»**. من غير ده الدوسة وقت الكلام كانت بتتبلع، والمقاطعة
    // ما بتحصلش.
    _busy = false;
    if (_interrupted(gen) || phase != CommandPhase.listening) return null; // دوسة كسبت
    switch (result) {
      case ListenFailed(permission: true):
        await _cantListen(result);
        return null;
      case ListenFailed():
        await _stumble(result);
        return null;
      case ListenSilence() when partial.trim().isEmpty:
        // **مفيش كلام مش عطل**: راحة والمايك فاضل — ولا جملة بتتقال
        note = 'ما سمعتش حاجة — دوس واتكلم.';
        _rest();
        return null;
      case ListenSilence():
        unawaited(clearListenProblem());
        return partial; // دوسة «خلصت» وهو بيتكلم
      case ListenHeard(:final text):
        unawaited(clearListenProblem());
        if (text.trim().isEmpty) {
          note = 'ما سمعتش حاجة — دوس واتكلم.';
          _rest();
          return null;
        }
        return text;
    }
  }

  /// راحة: مستنيين «أيوه»/«لأ» لو ده كان سماع رد، وإلا idle.
  void _rest() => _reply ? _set(CommandPhase.confirming, _understood) : _set(CommandPhase.idle, '');

  /// المايك وقع — مش «مافهمتش»، ولا بيتقفل من أول مرة: ٥ في ١٠ ثواني بس.
  Future<void> _stumble(ListenFailed failed) async {
    diag('Cmd: السماع وقع (${failed.started ? 'في النص' : 'في البداية'})');
    if (!failed.started) unawaited(_onStartFailure(failed.reason));
    if (breaker.fail()) return _cantListen(failed);
    note = 'معلش — دوس واتكلم تاني.';
    _rest();
  }

  /// المايك اتقفل على الشاشة دي. الإذن = «كمّل بإيدك» ومش هنسأل تاني؛
  /// المتعرّف مش موجود أو القاطع اشتغل = `gen_try_hands` مرة، و«كلّمني» يختفي،
  /// والسبب للسجل والأدمن بس.
  Future<void> _cantListen(ListenFailed failed) async {
    if (failed.permission) {
      voice.markMicDenied();
      await _say('lis_mic_denied', phase: CommandPhase.answering);
      return;
    }
    startFailed = true;
    diag('Cmd: intent=none source=none — المايك ما اشتغلش');
    await _onStartFailure(failed.reason);
    await _say('gen_try_hands', phase: CommandPhase.answering);
  }

  /// النيات اللي الـNLU الجديد ما بيلمسهاش.
  static const _legacyOnly = {
    CommandIntent.markTaken,
    CommandIntent.nextDose,
    CommandIntent.todayList,
    CommandIntent.snooze,
    CommandIntent.addVital,
    CommandIntent.addDoctorQuestion,
    CommandIntent.markBought,
    CommandIntent.upcomingAppointments,
    CommandIntent.stockStatus,
    CommandIntent.medicalQuestion,
    CommandIntent.doseStatus,
    CommandIntent.latestReading,
    CommandIntent.medInfo,
    CommandIntent.myDoctors,
    CommandIntent.weeklySummary,
  };

  /// مش مفهوم — **عمره ما يبقى طريق مسدود**: الجملة مكتوبة، واللي اتسمع
  /// تحتها، و«عيد كلامك».
  Future<void> _fail(int gen) async {
    failures++;
    _reviewAction = null;
    _set(CommandPhase.reviewing, unclearLine);
    await voice.speakLine(failures >= 2 ? 'gen_try_hands' : 'lis_not_understood');
  }

  static const unclearLine = 'مش متأكد إنت عايز إيه — عيد كلامك';

  Future<void> _handle(VoiceCommand cmd, int gen) async {
    if (cmd.intent != CommandIntent.unknown) failures = 0;
    switch (cmd.intent) {
      case CommandIntent.unknown:
        return _fail(gen);
      case CommandIntent.medicalQuestion:
        return _say('gen_no_medical', phase: CommandPhase.answering);
      case CommandIntent.nextDose:
        if (cmd.medWords case final words?) return _answerForMedicine(words, _nextDoseOfText);
        final (text, phrase) = await _nextDoseAnswer();
        return _sayText(text, phase: CommandPhase.answering, phrase: phrase);
      case CommandIntent.doseStatus:
        if (cmd.medWords case final words?) return _answerForMedicine(words, (names) => _statusText(names: names, part: cmd.dayPart));
        return _sayText(await _statusText(part: cmd.dayPart), phase: CommandPhase.answering);
      case CommandIntent.latestReading:
        return _sayText(await _latestReadingText(cmd), phase: CommandPhase.answering);
      case CommandIntent.todayList:
        final moments = groupByMinute([for (final d in await _today()) if (d.state != DoseState.superseded) d]).length;
        return _sayText(await _todayListText(), phase: CommandPhase.answering, phrase: todayCountPhrase(moments));
      case CommandIntent.upcomingAppointments:
        if (cmd.apptKind != null || cmd.withWhom != null) {
          return _sayText(await _filteredUpcoming(cmd), phase: CommandPhase.answering);
        }
        return _sayText(await _upcomingText(), phase: CommandPhase.answering);
      case CommandIntent.medInfo:
        return _answerForMedicine(cmd.medWords!, (names) => _medInfo(names, cmd.infoAspect!));
      case CommandIntent.myDoctors:
        return _sayText(doctorsText(await _doctorsFor()), phase: CommandPhase.answering);
      case CommandIntent.weeklySummary:
        return _sayText(await _weeklySummaryText(), phase: CommandPhase.answering);
      case CommandIntent.stockStatus:
        return _sayText(await _stockText(), phase: CommandPhase.answering);
      case CommandIntent.markTaken:
        return _markTaken(cmd, gen);
      case CommandIntent.snooze:
        return _snooze(cmd, gen);
      case CommandIntent.addMed:
      case CommandIntent.addAppointment:
        final nlu = nluFromLegacy(cmd);
        return nlu.intent == NluIntent.none ? _fail(gen) : _handleNlu(nlu, gen);
      case CommandIntent.addVital:
        return _addVital(cmd, gen);
      case CommandIntent.addDoctorQuestion:
        return _addQuestion(cmd, gen);
      case CommandIntent.markBought:
        return _markBought(cmd, gen);
    }
  }

  // ---------------------------------------------------------------- سؤال متابعة

  /// **سؤال واحد** لخانة ناقصة: بيتقال وبيتكتب، وبعده سماع مرة — الجواب،
  /// أو null (سكوت / دوسة / وقعة). مفيش سؤال تاني.
  Future<String?> _followUp(String question, int gen) async {
    final listener = voice.listener;
    if (listener == null) return null;
    // السؤال مكتوب — مفيش حتت ليه، ومفيش صوت موبايل
    _set(CommandPhase.asking, question);
    if (_interrupted(gen)) return null;
    partial = '';
    await voice.yieldToMic(settle: true);
    if (_interrupted(gen)) return null;
    _busy = true;
    final text = await _hear(listener, gen);
    return text;
  }

  // ---------------------------------------------------------------- الردود

  Future<List<DoseEventView>> _today() => _dosesFor(routineDay);

  /// أول جرعة لسه ما اتأكدتش — لو فات معادها بنقول كده (هي اللي «جاية»
  /// فعلاً بالنسبة له)، وإلا الجاية النهارده، وإلا أول واحدة بكرة.
  /// الرد مكتوب بالأسامي، والمسموع من غيرها («الدوا الجاي الساعة ٨ بالليل») —
  /// بس لو الجرعة لسه جاية (اللي فات معادها مالهاش حتت).
  Future<(String, SpokenPhrase?)> _nextDoseAnswer() async {
    final text = await _nextDoseText();
    final open = [for (final d in await _today()) if (!d.isDone && d.state != DoseState.superseded) d]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final next = open.firstOrNull;
    return (text, next == null || next.scheduledAt.isBefore(_clock()) ? null : nextDosePhrase(next.scheduledAt));
  }

  Future<String> _nextDoseText() async {
    final now = _clock();
    final today = await _today();
    var open = [for (final d in today) if (!d.isDone) d];
    var tomorrow = false;
    if (open.isEmpty) {
      final next = await _dosesFor(DateTime(routineDay.year, routineDay.month, routineDay.day + 1));
      open = [for (final d in next) if (!d.isDone) d];
      tomorrow = true;
    }
    if (open.isEmpty) return 'مفيش جرعات جاية متسجّلة النهارده ولا بكرة.';
    open.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final at = open.first.scheduledAt;
    final names = [for (final d in open) if (d.scheduledAt == at) d.medicationName].join(' و');
    if (!tomorrow && at.isBefore(now)) return 'معاد $names كان الساعة ${voiceTime(at)} — ولسه ما اتأكدش.';
    return 'دواك الجاي $names ${tomorrow ? 'بكرة ' : ''}الساعة ${voiceTime(at)}.';
  }

  Future<String> _todayListText() async {
    final today = [for (final d in await _today()) if (d.state != DoseState.superseded) d];
    if (today.isEmpty) return 'مفيش أدوية متسجّلة النهارده.';
    final groups = groupByMinute(today);
    final items = <String>[];
    for (final g in groups) {
      // حالة كل دوا لوحده — «اتنين في نفس الساعة» مش معناها إن الاتنين اتاخدوا
      final names = [for (final d in g) '${d.medicationName}${_stateWord(d)}'].join(' و');
      items.add('$names الساعة ${voiceTime(g.first.scheduledAt)}');
    }
    final shownItems = items.take(5).toList();
    final more = items.length > 5 ? '، وحاجات تانية على الشاشة' : '';
    final count = switch (groups.length) {
      1 => 'جرعة واحدة',
      2 => 'جرعتين',
      final n => '${arabicNumber(n)} جرعات',
    };
    return 'النهارده عندك $count: ${shownItems.join('، ')}$more.';
  }

  String _stateWord(DoseEventView d) => switch (d.state) {
        DoseState.taken => ' (أخدته)',
        DoseState.skipped => ' (مش هتاخده)',
        _ when d.scheduledAt.isAfter(_clock()) => '',
        _ => ' (لسه ما اتأكدش)',
      };

  /// «مواعيدك الجاية» — من نفس الدالة اللي كارت «يومك» بيقراها.
  Future<String> _upcomingText() async {
    final rows = await RecordsRepository(services.db).all(services.patientId);
    final soon = upcomingAppointments(rows, now: _clock());
    if (soon.isEmpty) return 'مفيش مواعيد جاية متسجّلة.';
    final items = [for (final a in soon.take(3)) '${a.headline} ${a.displayTitle} يوم ${arabicDate(a.at)}'];
    return 'مواعيدك الجاية: ${items.join('، ')}${soon.length > 3 ? '، وحاجات تانية على الشاشة' : ''}.';
  }

  // ---------------------------------------------------------------- E1: من بياناته

  /// أدويته الشغّالة زي ما هي متسجّلة — الاسم والجرعة والغرض والمواعيد
  /// وكلمة الأكل. اللي اتطابق بس ([names]) بيتقال عنه.
  Future<String> _medInfo(List<String> names, MedInfoAspect aspect) async {
    final summaries = await services.medications.watchActiveSummaries(services.patientId).first;
    final lines = <String>[];
    for (final s in summaries) {
      if (!names.contains(s.medication.name)) continue;
      final active = [for (final d in s.schedules) d];
      lines.add(medInfoText(
        MedFact(
          name: s.medication.name,
          amountLabel: s.medication.amountLabel,
          purposeLabel: MedicationPurpose.fromStorage(s.medication.purpose)?.label,
          minutes: [for (final d in active) d.timing.minuteOfDay.minutes],
          mealLabel: active.map((d) => d.mealRelation).whereType<MealRelation>().firstOrNull?.label,
        ),
        aspect,
      ));
    }
    return lines.isEmpty ? unknownMedicineLine : lines.join('\n');
  }

  /// «التحليل إمتى؟» / «ميعاد د. حسام إمتى؟» — من نفس دالة الكارت، بفلتر.
  Future<String> _filteredUpcoming(VoiceCommand cmd) async {
    final rows = await RecordsRepository(services.db).all(services.patientId);
    final byId = {for (final r in rows) r.id: r};
    return filteredUpcomingText(
      upcomingAppointments(rows, now: _clock()),
      kind: cmd.apptKind,
      withWhom: cmd.withWhom,
      doctorOf: (a) => byId[a.recordId]?.doctor,
    );
  }

  /// «ملخص الأسبوع» — نفس حساب كارت «ملفّي» (Phase D) بالحرف.
  Future<String> _weeklySummaryText() async {
    final day = routineDay;
    final week = await services.events
        .watchRoutineDays(DateTime(day.year, day.month, day.day - 7), DateTime(day.year, day.month, day.day - 1))
        .first;
    return weeklySummaryText(summaryFromLocal(
      week: week,
      stock: await StockRepository(services.db).all(services.patientId),
      records: await RecordsRepository(services.db).all(services.patientId),
      today: day,
      now: _clock(),
    ));
  }

  /// «فاضل كام؟» — من نفس حساب «قرب يخلص».
  Future<String> _stockText() async {
    final all = await StockRepository(services.db).all(services.patientId);
    if (all.isEmpty) return 'مفيش مخزون متسجّل — تقدر تكتب اللي عندك من صفحة الدوا.';
    final low = [for (final v in all) if (v.isLow) stockLowLine(v.name, stock: v.quantity, daysLeft: v.daysLeft ?? 0)];
    if (low.isEmpty) return 'كل أدويتك لسه فيها كمية كويسة.';
    return 'قرب يخلص: ${low.join('، ')}.';
  }

  // ---------------------------------------------------------------- أسئلة عن بياناته

  /// أدوية المريض اللي الكلام بيطابقها — بالاسم أو بالغرض («الضغط»)، بنفس
  /// التطبيع والمطابقة بالصوت بتوع «أخدته».
  Future<List<String>> _matchOwn(String spoken) async {
    final purposes = await _purposesFor();
    return matchMedication(spoken, purposes.keys.toList(), purposes: {
      for (final e in purposes.entries)
        if (e.value != null) e.key: e.value!.label,
    }).names;
  }

  Future<VoiceCommand?> _ownMedicineQuestion(String text) async {
    final candidate = medicineQuestionCandidate(text);
    if (candidate == null) return null;
    return (await _matchOwn(candidate.medWords!)).isEmpty ? null : candidate;
  }

  /// سؤال عن دوا بعينه: لقيناه = الرد، ملقيناهوش = «مش لاقي …» وأدويته
  /// شرايح — **عمرنا ما نجاوب عن دوا مش عنده**.
  Future<void> _answerForMedicine(String spoken, Future<String> Function(List<String> names) answer) async {
    final names = await _matchOwn(spoken);
    if (names.isNotEmpty) {
      medChoices = const [];
      return _sayText(await answer(names), phase: CommandPhase.answering);
    }
    final all = (await _purposesFor()).keys.toList()..sort();
    medChoices = all;
    _medAnswer = answer;
    await _sayText(all.isEmpty ? '$unknownMedicineLine — ومفيش أدوية متسجّلة لسه.' : unknownMedicineLine, phase: CommandPhase.answering);
  }

  static const unknownMedicineLine = 'مش لاقي دوا اسمه كده عندك';

  /// دوسة على شريحة دوا بعد «مش لاقي …».
  Future<void> pickMedicine(String name) async {
    final answer = _medAnswer;
    if (answer == null) return;
    medChoices = const [];
    _medAnswer = null;
    await _sayText(await answer([name]), phase: CommandPhase.answering);
  }

  Future<String> _nextDoseOfText(List<String> names) async {
    final today = [for (final d in await _today()) if (names.contains(d.medicationName)) d];
    final tomorrow = [
      for (final d in await _dosesFor(DateTime(routineDay.year, routineDay.month, routineDay.day + 1)))
        if (names.contains(d.medicationName)) d,
    ];
    return nextDoseOfText(today: today, tomorrow: tomorrow, now: _clock(), subject: names.join(' و'));
  }

  Future<String> _statusText({List<String>? names, DayPart? part}) async {
    final today = [
      for (final d in await _today())
        if ((names == null || names.contains(d.medicationName)) && (part == null || dayPartOf(d.scheduledAt) == part)) d,
    ];
    return doseStatusText(today, now: _clock(), subject: names?.join(' و'), part: part);
  }

  /// «آخر تحليل سكر كام؟» — آخر رقم متسجّل وتاريخه، ولا كلمة غيرهم.
  Future<String> _latestReadingText(VoiceCommand cmd) async {
    final saidLab = normalizeArabic(heard).contains('تحليل');
    final labs = LabResultsRepository(services.db);
    switch (cmd.readingType) {
      case VitalType.sugar:
        if (saidLab) {
          final lab = await _latestLab(labs, const ['سكر', 'glucose', 'sugar', 'fbs', 'rbs', 'hba1c']);
          if (lab != null) return lab;
        }
        final rows = await ReadingsRepository(services.db).watchRecent(services.patientId, limit: 1).first;
        if (rows.isEmpty) return (await _latestLab(labs, const ['سكر', 'glucose', 'sugar', 'fbs', 'rbs', 'hba1c'])) ?? 'مفيش قياس سكر متسجّل عندك.';
        final r = rows.first;
        return 'آخر قياس سكر ${arabicNumber(r.valueMgDl)} — ${r.context.label} — ${arabicDate(r.measuredAt)} الساعة ${voiceTime(r.measuredAt)}.';
      case final VitalType type?:
        final kind = switch (type) {
          VitalType.bp => VitalKind.bloodPressure,
          VitalType.pulse => VitalKind.pulse,
          VitalType.weight => VitalKind.weight,
          VitalType.temp => VitalKind.temperature,
          VitalType.o2 => VitalKind.spo2,
          VitalType.sugar => VitalKind.pulse, // مش بيوصل هنا
        };
        final all = [for (final v in await VitalsRepository(services.db).all(services.patientId)) if (v.kind == kind) v]
          ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
        if (all.isEmpty) return 'مفيش قياس ${kind.label.replaceFirst('ال', '')} متسجّل عندك.';
        final v = all.first;
        return 'آخر قياس ${kind.label.replaceFirst('ال', '')} ${vitalValueText(v)} — ${arabicDate(v.measuredAt)} الساعة ${voiceTime(v.measuredAt)}.';
      case null:
        final words = cmd.labWords;
        if (words == null) return 'قولّي اسم التحليل — «آخر تحليل صورة دم».';
        return (await _latestLab(labs, normalizeArabic(words.toLowerCase()).split(' '), all: true)) ??
            'مش لاقي تحليل اسمه كده في ملفك.';
    }
  }

  /// أحدث نتيجة تحليل اسمها فيه أي كلمة من [words] (أو كلهم لو [all]).
  Future<String?> _latestLab(LabResultsRepository labs, List<String> words, {bool all = false}) async {
    for (final r in await labs.allNewestFirst(services.patientId)) {
      final name = normalizeArabic((r.testName ?? '').toLowerCase());
      final hit = all ? words.every(name.contains) : words.any(name.contains);
      if (!hit) continue;
      final value = r.value == r.value.roundToDouble() ? '${r.value.toInt()}' : '${r.value}';
      return 'آخر تحليل ${r.testName}: ${arabicDigits(value)}${r.unit == null ? '' : ' ${r.unit}'} — ${arabicDate(r.at)}.';
    }
    return null;
  }

  // ---------------------------------------------------------------- الدكتور

  /// «احجز عند د. حسن» — في دكاترته هو وبس.
  Future<void> _resolveDoctor(NluResult nlu) async {
    _bookingNlu = nlu;
    savedDoctors = await _doctorsFor();
    final matches = matchDoctors(nlu.doctorName!, savedDoctors);
    if (matches.length == 1) return _reviewBooking(matches.single);
    doctorMissing = matches.isEmpty ? nlu.doctorName : null;
    doctorOptions = matches;
    _set(
      CommandPhase.pickingDoctor,
      matches.isEmpty ? noDoctorLine(nlu.doctorName!) : 'عندك أكتر من دكتور بالاسم ده — أنهي واحد؟',
    );
  }

  static String noDoctorLine(String name) => 'مش لاقي $name عندك — اختار من دكاترتك أو دوّر في القريب مني';

  Future<void> _reviewBooking(String doctor) {
    final n = _bookingNlu!;
    appointmentPrefill = AppointmentPrefill(
      kind: FollowKind.visit,
      name: doctor,
      doctor: doctor,
      specialty: n.specialtyKind,
      day: n.date,
      time: n.time == null ? null : MinuteOfDay(n.time!.minutes),
    );
    final p = appointmentPrefill!;
    final wording = bookingWording(
      NluResult(NluIntent.bookAppointment, doctorName: doctor, specialtyKind: n.specialtyKind, date: n.date, time: n.time),
      now: _clock(),
    );
    return _review(wording, () async {
      final open = onOpenAppointment;
      if (open == null) return;
      final saved = await open(p);
      if (saved) await _say('cmd_done', phase: CommandPhase.done);
    });
  }

  /// دوسة على دكتور من «أنهي واحد؟» / «دكاترتك».
  Future<void> pickDoctor(String doctor) async {
    if (phase != CommandPhase.pickingDoctor || _bookingNlu == null) return;
    doctorOptions = const [];
    doctorMissing = null;
    await _reviewBooking(doctor);
  }

  /// «اختار من دكاترتك».
  void showSavedDoctors() {
    if (phase != CommandPhase.pickingDoctor) return;
    doctorMissing = null;
    doctorOptions = savedDoctors;
    _set(CommandPhase.pickingDoctor, 'اختار الدكتور');
  }

  /// «دوّر في القريب مني» — على الدكاترة (وتخصصه لو اتقال).
  Future<void> searchNearbyDoctor() async {
    final n = _bookingNlu;
    _set(CommandPhase.done, '');
    unawaited(voice.stop());
    await onOpenNearby?.call(NearbyPlace.doctor, n?.specialtyKind);
  }

  // ---------------------------------------------------------------- أخدته / أجّل

  /// نفس نافذة زرار «أخدته»: اللي فات معاده من غير تأكيد، وأقرب جاية.
  Future<List<DoseEventView>> _window(VoiceCommand cmd) async {
    final now = _clock();
    final today = await _today();
    final window = [for (final g in nowGroups(groupByMinute(today), now)) for (final d in g) if (!d.isDone) d];
    if (cmd.medWords == null) return window;
    final purposes = await _purposesFor();
    final names = {for (final d in window) d.medicationName}.toList();
    final match = matchMedication(cmd.medWords, names, purposes: {
      for (final e in purposes.entries)
        if (e.value != null) e.key: e.value!.label,
    });
    return [for (final d in window) if (match.names.contains(d.medicationName)) d];
  }

  Future<void> _markTaken(VoiceCommand cmd, int gen) async {
    final picks = await _window(cmd);
    if (_interrupted(gen)) return;
    if (picks.isEmpty) {
      // «أخدت الكونكور» وهو متأكّد خلاص (أو لسه ما جاش) — بنقول حالته النهارده
      if (cmd.medWords case final words?) {
        final names = await _matchOwn(words);
        if (names.isNotEmpty) return _sayText(await _statusText(names: names), phase: CommandPhase.answering);
      }
      return _sayText(cmd.medWords == null ? 'مفيش جرعة مستنية دلوقتي.' : 'مفيش جرعة ${cmd.medWords} مستنية دلوقتي — بص على الشاشة.', phase: CommandPhase.answering);
    }
    candidates = [for (final d in picks.take(3)) DoseCandidate(d, d.routineDay ?? routineDay)];
    if (candidates.length > 1) return _sayText('أنهي واحد؟', phase: CommandPhase.choosing);
    await _confirm(candidates.single, gen);
  }

  /// اختيار واحدة من الأزرار الكبيرة.
  Future<void> choose(DoseCandidate c) async {
    if (phase != CommandPhase.choosing) return;
    chosen = c;
    await _confirm(c, voice.interrupts);
  }

  Future<void> _confirm(DoseCandidate c, int gen) async {
    chosen = c;
    if (command?.intent == CommandIntent.snooze) {
      _pendingWrite = () => snoozeGroup(services, c.routineDay, [c.dose], now: _clock());
      // التأجيل في التطبيق ربع ساعة ثابتة — بنقولها زي ما هي
      return _askYes('أأجّل ${c.dose.medicationName} ربع ساعة');
    }
    _pendingWrite = () => confirmGroup(services, c.routineDay, [c.dose]);
    await _askYes('أخدت ${c.dose.medicationName} بتاع الساعة ${voiceTime(c.dose.scheduledAt)}');
  }

  Future<void> _snooze(VoiceCommand cmd, int gen) async {
    final picks = await _window(cmd);
    if (_interrupted(gen)) return;
    if (picks.isEmpty) return _sayText('مفيش جرعة مستنية دلوقتي عشان أأجّلها.', phase: CommandPhase.answering);
    candidates = [for (final d in picks.take(3)) DoseCandidate(d, d.routineDay ?? routineDay)];
    if (candidates.length > 1) return _sayText('أنهي واحد؟', phase: CommandPhase.choosing);
    await _confirm(candidates.single, gen);
  }

  /// التأكيد: اللي اتفهم **مكتوب كبير** و«صح كده؟» **المسجّلة** — مفيش «فهمت:
  /// …» بصوت الموبايل، ومفيش سماع لـ«أيوه»: الزرارين قدّامه، والدوسة بتكسب.
  Future<void> _askYes(String understood) async {
    _understood = understood;
    _set(CommandPhase.confirming, understood);
    await voice.speakLine('lis_confirm');
  }

  // ---------------------------------------------------------------- الكتابات الصغيرة

  Future<void> _addVital(VoiceCommand cmd, int gen) async {
    final v = cmd.vital!;
    final now = _clock();
    if (v.type == VitalType.sugar) {
      final mg = v.values.first.round();
      if (!ReadingsRepository.isReadable(mg)) return _sayText('الرقم ده غريب — راجعه.', phase: CommandPhase.answering);
      // السياق لازم يتقال — سؤال متابعة واحد
      final answer = await _followUp('صايم ولا بعد الأكل؟', gen);
      if (answer == null) return;
      final a = normalizeArabic(answer);
      final GlucoseContext? context = a.contains('صايم') || a.contains('صيام') || a.contains('فاطر')
          ? (a.contains('فاطر') ? GlucoseContext.afterMeal : GlucoseContext.fasting)
          : (a.contains('اكل') || a.contains('بعد') ? GlucoseContext.afterMeal : null);
      if (context == null) return _say('gen_try_hands', phase: CommandPhase.answering);
      _pendingWrite = () => ReadingsRepository(services.db).add(patientId: services.patientId, valueMgDl: mg, context: context, measuredAt: now);
      return _askYes('أسجّل السكر ${arabicNumber(mg)} ${context == GlucoseContext.fasting ? 'صايم' : 'بعد الأكل'}');
    }
    final kind = switch (v.type) {
      VitalType.bp => VitalKind.bloodPressure,
      VitalType.pulse => VitalKind.pulse,
      VitalType.weight => VitalKind.weight,
      VitalType.temp => VitalKind.temperature,
      VitalType.o2 => VitalKind.spo2,
      VitalType.sugar => VitalKind.pulse, // مش بيوصل هنا
    };
    var values = v.values;
    if (kind == VitalKind.bloodPressure && values.length < 2) {
      final answer = await _followUp('والرقم التاني كام؟', gen);
      if (answer == null) return;
      final n = firstNumberOf(answer);
      if (n == null) return _say('gen_try_hands', phase: CommandPhase.answering);
      values = [values.first, n];
    }
    final entry = VitalEntry(
      kind: kind,
      value: values.first,
      value2: kind == VitalKind.bloodPressure ? values[1] : null,
      pulse: kind == VitalKind.bloodPressure && values.length > 2 ? values[2].round() : null,
    );
    final problem = vitalEntryProblem(entry);
    if (problem != null) return _sayText('$problem.', phase: CommandPhase.answering);
    _pendingWrite = () => VitalsRepository(services.db).add(services.patientId, entry, measuredAt: now);
    await _askYes('أسجّل ${kind.label} ${vitalWording(entry)}');
  }

  Future<void> _addQuestion(VoiceCommand cmd, int gen) async {
    var text = cmd.questionText;
    if (text == null) {
      text = await _followUp('تسأله عن إيه؟', gen);
      if (text == null) return;
    }
    final body = text;
    _pendingWrite = () => VisitQuestionsRepository(services.db).add(services.patientId, body, now: _clock());
    await _askYes('أسجّل سؤال للدكتور: $body');
  }

  Future<void> _markBought(VoiceCommand cmd, int gen) async {
    final repo = NotBoughtRepository(services.db);
    final pending = await repo.all(services.patientId);
    if (_interrupted(gen)) return;
    if (pending.isEmpty) return _sayText('مفيش دوا متعلّم إنك لسه ما اشتريتوش.', phase: CommandPhase.answering);
    var picks = pending;
    if (cmd.medWords != null) {
      final match = matchMedication(cmd.medWords, [for (final m in pending) m.name]);
      picks = [for (final m in pending) if (match.names.contains(m.name)) m];
      if (picks.isEmpty) return _sayText('مش لاقي ${cmd.medWords} في اللي لسه ما اتشتراش — بص على الشاشة.', phase: CommandPhase.answering);
    }
    if (picks.length > 1) return _sayText('أنهي واحد؟ ${[for (final m in picks) m.name].join('، ')} — قولّي اسمه.', phase: CommandPhase.answering);
    final med = picks.single;
    _pendingWrite = () => repo.markBought(med.id);
    await _askYes('اشتريت ${med.name}');
  }

  // ---------------------------------------------------------------- أيوه / لأ

  /// **دوسة الدايرة** — نفس `onPress` بتاع `MicOrb`: والموبايل بيتكلم ← يسكت
  /// ويفتح المايك في نفس الدوسة؛ والمايك مفتوح ← «خلصت»؛ ومستنيين «أيوه» ←
  /// سماع واحد للرد؛ و«بفكّر…» ما بيعملش حاجة.
  Future<void> tapMic() async {
    if (startFailed || voice.micDenied) return;
    switch (phase) {
      case CommandPhase.thinking || CommandPhase.done:
        return;
      case CommandPhase.listening:
        await voice.listener?.stop();
      case CommandPhase.confirming:
        await _listenReply();
      case CommandPhase.asking || CommandPhase.idle || CommandPhase.choosing || CommandPhase.answering || CommandPhase.reviewing || CommandPhase.clarifying || CommandPhase.pickingDoctor:
        await start();
    }
  }

  /// «أيوه» / «لأ» بالصوت — [classifyReply] (بورت `affirm.js`): الرفض الأول،
  /// ومش واضح = «صح كده؟» تاني. **عمره ما ينفّذ من غير كلمة واضحة.**
  Future<void> _listenReply() async {
    final listener = voice.listener;
    if (listener == null || _busy) return;
    _busy = true;
    try {
      final wasSpeaking = voice.speaking;
      await voice.stop();
      final gen = voice.interrupts;
      _reply = true;
      note = null;
      partial = '';
      await voice.yieldToMic(settle: wasSpeaking);
      if (_interrupted(gen)) return;
      final text = await _hearReply(listener, gen);
      if (text == null) return;
      _set(CommandPhase.confirming, _understood);
      _reply = false;
      switch (classifyReply(text)) {
        case ReplyClass.affirm:
          await confirmYes();
        case ReplyClass.deny:
          await confirmNo();
        case ReplyClass.unclear:
          note = 'قول «أيوه» أو «لأ» — أو دوس.';
          notifyListeners();
          await voice.speakLine('lis_confirm');
      }
    } finally {
      _busy = false;
    }
  }

  /// رد قصير («أيوه»/«لأ»): نافذة الإجابات القصيرة، مش نافذة الطلب.
  Future<String?> _hearReply(SpeechListener listener, int gen) async {
    sessions++;
    _set(CommandPhase.listening, 'سامعك…');
    final result = await listener.listen(onPartial: (t) {
      if (phase != CommandPhase.listening || _disposed) return;
      partial = t;
      notifyListeners();
    });
    _busy = false;
    if (_interrupted(gen) || phase != CommandPhase.listening) return null;
    switch (result) {
      case ListenFailed(permission: true):
        await _cantListen(result);
        return null;
      case ListenFailed():
        await _stumble(result);
        return null;
      case ListenSilence() when partial.trim().isEmpty:
        note = 'ما سمعتش حاجة — دوس واتكلم.';
        _rest();
        return null;
      case ListenSilence():
        return partial;
      case ListenHeard(:final text):
        if (text.trim().isEmpty) {
          _rest();
          return null;
        }
        return text;
    }
  }

  /// «أيوه» — التنفيذ الوحيد. «أخدته» بيعدّي من [confirmGroup] نفسها، والباقي
  /// من نفس مخازن الشاشات.
  Future<void> confirmYes() async {
    if (phase != CommandPhase.confirming) return;
    final write = _pendingWrite;
    _pendingWrite = null;
    _set(CommandPhase.done);
    // الدوسة بتكسب: «صح كده؟» والمايك بيقفوا على طول
    unawaited(voice.stop());
    if (write != null) {
      await write();
      if (command?.intent != CommandIntent.markTaken && command?.intent != CommandIntent.snooze) {
        await _say('cmd_done', phase: CommandPhase.done);
      }
    }
  }

  /// «لأ» / «إلغي» — ولا حاجة بتتغيّر.
  Future<void> confirmNo() async {
    if (phase != CommandPhase.confirming && phase != CommandPhase.choosing) return;
    chosen = null;
    prefill = null;
    _pendingWrite = null;
    await voice.stop();
    await _say('cmd_cancelled', phase: CommandPhase.answering);
  }

  /// «قول تاني» بعد «مافهمتش».
  Future<void> again() => start();

  /// «اقفل» — المايك بيقف على طول.
  Future<void> cancel() async {
    _pendingWrite = null;
    _set(CommandPhase.idle, '');
    await voice.stop();
  }

  // ---------------------------------------------------------------- اللي فهمناه

  /// النية اتفهمت: «أقرب …» بيفتح على طول؛ الباقي **بيتقال بكلامنا** ومستني
  /// «صح كده» — مكتوب بس، من غير صوت. ولا حاجة بتتحفظ هنا.
  Future<void> _handleNlu(NluResult nlu, int gen) async {
    failures = 0;
    understood = nlu;
    if (_interrupted(gen)) return;
    switch (nlu.intent) {
      case NluIntent.findNearby:
        _set(CommandPhase.done, '');
        unawaited(voice.stop());
        await onOpenNearby?.call(nlu.place ?? NearbyPlace.pharmacy, nlu.specialtyKind);
        return;
      case NluIntent.addMedication:
        final purpose = _purposeFromWords(nlu.name);
        prefill = AddMedPrefill(
          name: purpose == null ? nlu.name : null,
          purpose: purpose,
          timings: [for (final t in nlu.times) FixedTiming(MinuteOfDay(t.minutes))],
          amount: nlu.doseText,
          everyHours: nlu.everyHours,
          emptyDoses: nlu.times.isEmpty && nlu.everyHours == null ? (nlu.perDay ?? 1) : null,
          durationDays: nlu.durationDays,
          mealRelation: nlu.food,
        );
        final p = prefill!;
        return _review(addMedicationWording(nlu), () async {
          final saved = await onOpenAdd(p);
          if (saved) await _say('cmd_done', phase: CommandPhase.done);
        });
      case NluIntent.bookAppointment when nlu.doctorName != null:
        return _resolveDoctor(nlu);
      case NluIntent.bookAppointment || NluIntent.bookLab:
        final lab = nlu.intent == NluIntent.bookLab;
        appointmentPrefill = AppointmentPrefill(
          kind: lab ? FollowKind.lab : FollowKind.visit,
          // الدكتور: الاسم فاضي والتخصص في خانته — الورقة بتقول «دكتور باطنة»
          name: lab ? appointmentTitle(nlu) : null,
          specialty: lab ? null : nlu.specialtyKind,
          day: nlu.date,
          time: nlu.time == null ? null : MinuteOfDay(nlu.time!.minutes),
        );
        final p = appointmentPrefill!;
        return _review(bookingWording(nlu, now: _clock()), () async {
          final open = onOpenAppointment;
          if (open == null) return;
          final saved = await open(p);
          if (saved) await _say('cmd_done', phase: CommandPhase.done);
        });
      case NluIntent.none:
        return _fail(gen);
    }
  }

  Future<void> _review(String text, Future<void> Function() action) async {
    _reviewAction = action;
    await voice.stop(); // مكتوب بس — من غير «صح كده؟» بصوت
    _set(CommandPhase.reviewing, text);
  }

  /// «صح كده» — بيفتح الفورم متعبّي. الحفظ بزرار الفورم هو.
  Future<void> confirmReview() async {
    final action = _reviewAction;
    if (phase != CommandPhase.reviewing || action == null) return;
    _reviewAction = null;
    _set(CommandPhase.done);
    unawaited(voice.stop());
    await action();
  }

  /// «عيد كلامك» — سماع من الأول.
  Future<void> retry() async {
    _reviewAction = null;
    clarifyOptions = const [];
    await start();
  }

  /// تعادل: «قصدك …؟» بزرار لكل نية — والدوسة بتكمّل بنفس الجملة.
  void _clarify(List<NluIntent> options) {
    clarifyOptions = [
      for (final i in options)
        (
          intent: i,
          label: switch (i) {
            NluIntent.findNearby => 'أدوّر على مكان قريب',
            NluIntent.addMedication => 'أضيف دوا',
            NluIntent.bookAppointment => 'أحجز ميعاد دكتور',
            NluIntent.bookLab => 'أحجز تحليل',
            NluIntent.none => 'حاجة تانية',
          },
        ),
    ];
    _set(CommandPhase.clarifying, 'قصدك إيه؟');
  }

  /// دوسة على اختيار من «قصدك إيه؟».
  Future<void> clarify(NluIntent intent) async {
    if (phase != CommandPhase.clarifying) return;
    clarifyOptions = const [];
    await _handleNlu(understandUtteranceAs(intent, heard, now: _clock()), voice.interrupts);
  }

  static MedicationPurpose? _purposeFromWords(String? words) {
    if (words == null) return null;
    final key = medKey(words);
    for (final p in MedicationPurpose.values) {
      if (p == MedicationPurpose.other) continue;
      if (medKey(p.label).split(' ').any((w) => key.split(' ').contains(w))) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(voice.listener?.stop());
    super.dispose();
  }
}

/// أول رقم في كلام — للأجوبة القصيرة («٨٠»).
double? firstNumberOf(String text) {
  final n = RegExp(r'\d+([.,]\d+)?').firstMatch(normalizeArabic(text));
  return n == null ? null : double.tryParse(n.group(0)!.replaceAll(',', '.'));
}

/// «١٢٠ على ٨٠ — نبض ٧٠» / «٨٠ كيلو» — بكلام القياسات نفسه.
String vitalWording(VitalEntry e) {
  final v = Vital(kind: e.kind, value: e.value, value2: e.value2, pulse: e.pulse, measuredAt: DateTime(2026));
  return vitalValueText(v);
}

// ---------------------------------------------------------------- الكلام

const _weekdayNames = ['الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// «النهارده» / «بكرة» / «يوم الأحد ٤ أكتوبر».
String spokenDay(DateTime d, {required DateTime now}) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (diff == 0) return 'النهارده';
  if (diff == 1) return 'بكرة';
  return 'يوم ${_weekdayNames[day.weekday - 1]} ${arabicNumber(day.day)} ${arabicMonths[day.month - 1]}';
}

String _clockWord(SpokenTime t) => arabicTime(DateTime(2026, 1, 1, t.hour, t.minute));

/// «فهمت إنك عايز تضيف دوا: كونكور — كل ١٢ ساعة — الساعات: لسه هتختارها».
String addMedicationWording(NluResult n) => [
      'فهمت إنك عايز تضيف دوا: ${n.name ?? 'الاسم لسه هتكتبه'}',
      if (n.doseText case final d?) 'الجرعة ${arabicDigits(d)}',
      if (n.everyHours case final h?) 'كل ${hoursWord(h)}',
      if (n.everyHours == null && n.perDay != null) timesPerDayWord(n.perDay!),
      if (n.food case final f?) f.label,
      if (n.durationDays case final d?) 'لمدة ${daysWord(d)}',
      n.times.isEmpty ? 'الساعات: لسه هتختارها' : 'الساعات: ${n.times.map(_clockWord).join(' و')}',
    ].join(' — ');

/// «فهمت إنك عايز تحجز عند د. حسن — يوم الأحد ٤ أكتوبر — الساعة: لسه هتختارها».
String bookingWording(NluResult n, {required DateTime now}) {
  final who = n.intent == NluIntent.bookLab
      ? 'فهمت إنك عايز تحجز ${n.testName == null ? 'تحليل' : 'تحليل ${n.testName}'}${n.labName == null ? '' : ' في معمل ${n.labName}'}'
      : n.doctorName != null
          ? 'فهمت إنك عايز تحجز عند ${n.doctorName}${n.specialty == null ? '' : ' (${n.specialty})'}'
          : n.specialty != null
              ? 'فهمت إنك عايز تحجز عند دكتور ${n.specialty}'
              : 'فهمت إنك عايز تحجز ميعاد دكتور';
  return [
    who,
    n.date == null ? 'اليوم: لسه هتختاره' : spokenDay(n.date!, now: now),
    n.time == null ? 'الساعة: لسه هتختارها' : 'الساعة ${_clockWord(n.time!)}',
  ].join(' — ');
}

/// اسم الميعاد في ورقة «ميعاد جديد» — الاسم بس؛ الساعة ليها خانتها.
String appointmentTitle(NluResult n) => n.intent == NluIntent.bookLab
    ? [if (n.testName != null) 'تحليل ${n.testName}' else 'تحليل', if (n.labName != null) 'معمل ${n.labName}'].join(' — ')
    : n.doctorName ?? (n.specialty == null ? 'زيارة دكتور' : 'دكتور ${n.specialty}');

/// السحابة (أو القارئ القديم) قالت «ضيف دوا» / «احجز» — نفس خانات الـNLU،
/// عشان كل حاجة تعدّي من نفس التأكيد.
NluResult nluFromLegacy(VoiceCommand c) {
  switch (c.intent) {
    case CommandIntent.addMed:
      final fixed = [for (final t in c.timings) if (t.fixed != null) t.fixed!];
      final ambiguous = [for (final t in c.timings) if (t.hourNeedsPeriod != null) t.hourNeedsPeriod!];
      return NluResult(
        NluIntent.addMedication,
        name: medicineNameOrNull(c.medWords),
        everyHours: c.everyHours,
        perDay: c.timesPerDay,
        times: fixed,
        hourNeedsPeriod: ambiguous.firstOrNull,
        food: [for (final t in c.timings) if (t.relation != null) t.relation!].firstOrNull,
        durationDays: c.durationDays,
      );
    case CommandIntent.addAppointment:
      final a = c.appointment!;
      final lab = a.kind == AppointmentKind.lab;
      return NluResult(
        lab ? NluIntent.bookLab : NluIntent.bookAppointment,
        doctorName: !lab && a.withWhom != null ? 'د. ${a.withWhom}' : null,
        testName: lab ? a.withWhom : null,
        date: a.date,
        time: a.time,
        hourNeedsPeriod: a.hourNeedsPeriod,
      );
    default:
      return const NluResult(NluIntent.none);
  }
}


// ---------------------------------------------------------------- ردود من بياناته

/// جزء اليوم من الساعة: الصبح ٤–١٢، الضهر ١٢–٥، بالليل ٥–٤.
DayPart dayPartOf(DateTime at) => at.hour >= 4 && at.hour < 12
    ? DayPart.morning
    : at.hour >= 12 && at.hour < 17
        ? DayPart.afternoon
        : DayPart.evening;

String _partWord(DayPart p) => switch (p) {
      DayPart.morning => 'الصبح',
      DayPart.afternoon => 'الضهر',
      DayPart.evening => 'بالليل',
    };

/// «أخدت الكونكور؟» — حالة كل جرعة النهارده، من الصفوف نفسها. **وصف بس**:
/// اتاخدت إمتى، لسه ما اتأكدتش، أو لسه ما جاش معادها.
String doseStatusText(List<DoseEventView> doses, {required DateTime now, String? subject, DayPart? part}) {
  final shown = [for (final d in doses) if (d.state != DoseState.superseded) d]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  if (shown.isEmpty) {
    if (subject != null) return 'مفيش جرعة $subject النهارده.';
    return part == null ? 'مفيش أدوية متسجّلة النهارده.' : 'مفيش أدوية ${_partWord(part)} النهارده.';
  }
  final lines = <String>[];
  for (final d in shown) {
    final name = d.medicationName;
    final at = voiceTime(d.scheduledAt);
    lines.add(switch (d.state) {
      DoseState.taken => 'أيوه، أخدت $name الساعة ${voiceTime(d.actedAt ?? d.scheduledAt)}.',
      DoseState.skipped => '$name بتاع الساعة $at اتسجّل إنك مش هتاخده.',
      _ when d.scheduledAt.isAfter(now) => '$name معاده الساعة $at — لسه ما جاش.',
      _ => 'لأ، $name بتاع الساعة $at لسه ما اتأكدش.',
    });
  }
  return lines.join(' ');
}

/// «دوا الضغط الجاي إمتى؟» — أول جرعة لسه ما اتأكدتش للدوا ده.
String nextDoseOfText({
  required List<DoseEventView> today,
  required List<DoseEventView> tomorrow,
  required DateTime now,
  required String subject,
}) {
  bool open(DoseEventView d) => !d.isDone && d.state != DoseState.superseded;
  final todayOpen = [for (final d in today) if (open(d)) d]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  if (todayOpen.isNotEmpty) {
    final d = todayOpen.first;
    if (d.scheduledAt.isBefore(now)) return 'معاد ${d.medicationName} كان الساعة ${voiceTime(d.scheduledAt)} — ولسه ما اتأكدش.';
    return '${d.medicationName} الجاي الساعة ${voiceTime(d.scheduledAt)}.';
  }
  final next = [for (final d in tomorrow) if (open(d)) d]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  if (next.isNotEmpty) return '${next.first.medicationName} الجاي بكرة الساعة ${voiceTime(next.first.scheduledAt)}.';
  return 'مفيش جرعة $subject جاية النهارده ولا بكرة.';
}
