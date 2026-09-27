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
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/voice/answer_parser.dart';
import '../../domain/voice/arabic_dates.dart';
import '../../domain/voice/mic_state.dart';
import '../../domain/voice/voice_catalog.dart';
import '../../domain/voice/voice_time.dart';
import '../today/dose_actions.dart';
import 'cloud_tools.dart';
import 'command_parser.dart';
import 'voice_flags.dart';

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

  /// جملة بتتقال وتتقري (رد، أو «مافهمتش»، أو «للدكتور») — وخلاص.
  answering,
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
  const AddMedPrefill({this.name, this.purpose, this.timings = const [], this.once = false, this.durationDays, this.startDate});
  final String? name;
  final MedicationPurpose? purpose;
  final List<DoseTiming> timings;
  final bool once;
  final int? durationDays;
  final DateTime? startDate;
}

/// «احجزلي ميعاد» → ورقة «ميعاد جديد» **متعبّية** — والحفظ بزرارها هي.
class AppointmentPrefill {
  const AppointmentPrefill({required this.kind, this.name, this.day});
  final FollowKind kind;
  final String? name;
  final DateTime? day;
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
    this.reader,
    this.cloudAllowed,
    this.onCloudUsed,
    DateTime Function()? clock,
    Future<List<DoseEventView>> Function(DateTime day)? dosesFor,
    Future<Map<String, MedicationPurpose?>> Function()? purposesFor,
    Future<void> Function(String reason)? onStartFailure,
    MicBreaker? breaker,
  })  : breaker = breaker ?? MicBreaker(),
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

  /// رد متغيّر: مكتوب، وبصوت الموبايل (أحسن صوت عربي متسطّب، أبطأ شوية).
  Future<void> _sayText(String text, {CommandPhase? phase}) async {
    _set(phase ?? this.phase, text);
    await voice.speakText(text);
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
    var cmd = parseCommand(text, now: now);
    var source = 'local';
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

  Future<void> _fail(int gen) async {
    failures++;
    await _say(failures >= 2 ? 'gen_try_hands' : 'lis_not_understood', phase: CommandPhase.answering);
  }

  Future<void> _handle(VoiceCommand cmd, int gen) async {
    if (cmd.intent != CommandIntent.unknown) failures = 0;
    switch (cmd.intent) {
      case CommandIntent.unknown:
        return _fail(gen);
      case CommandIntent.medicalQuestion:
        return _say('gen_no_medical', phase: CommandPhase.answering);
      case CommandIntent.nextDose:
        return _sayText(await _nextDoseText(), phase: CommandPhase.answering);
      case CommandIntent.todayList:
        return _sayText(await _todayListText(), phase: CommandPhase.answering);
      case CommandIntent.upcomingAppointments:
        return _sayText(await _upcomingText(), phase: CommandPhase.answering);
      case CommandIntent.stockStatus:
        return _sayText(await _stockText(), phase: CommandPhase.answering);
      case CommandIntent.markTaken:
        return _markTaken(cmd, gen);
      case CommandIntent.snooze:
        return _snooze(cmd, gen);
      case CommandIntent.addMed:
        return _addMed(cmd, gen);
      case CommandIntent.addAppointment:
        return _addAppointment(cmd, gen);
      case CommandIntent.addVital:
        return _addVital(cmd, gen);
      case CommandIntent.addDoctorQuestion:
        return _addQuestion(cmd, gen);
      case CommandIntent.markBought:
        return _markBought(cmd, gen);
      case CommandIntent.setRoutine:
        return _setRoutine(cmd, gen);
    }
  }

  // ---------------------------------------------------------------- سؤال متابعة

  /// **سؤال واحد** لخانة ناقصة: بيتقال وبيتكتب، وبعده سماع مرة — الجواب،
  /// أو null (سكوت / دوسة / وقعة). مفيش سؤال تاني.
  Future<String?> _followUp(String question, int gen) async {
    final listener = voice.listener;
    if (listener == null) return null;
    _set(CommandPhase.asking, question);
    await voice.speakText(question);
    if (_interrupted(gen)) return null;
    partial = '';
    await voice.yieldToMic(settle: true);
    if (_interrupted(gen)) return null;
    _busy = true;
    final text = await _hear(listener, gen);
    return text;
  }

  /// «الساعة ٩» + جواب «الصبح»/«بالليل» → ساعة كاملة. السؤال عرض اختيارين
  /// بس، فـ«بالليل» = بعد الضهر (٥ بالليل = ٥ مساءً)، و«الصبح» = قبله.
  SpokenTime? _resolveHour(int hour, String? answer) {
    if (answer == null) return null;
    final a = normalizeArabic(answer);
    final h12 = hour % 12;
    if (RegExp(r'ليل|مسا|عصر|مغرب|ضهر|ظهر|\bم\b').hasMatch(a)) return SpokenTime(h12 + 12, 0);
    if (RegExp(r'صبح|صباح|فجر|\bص\b').hasMatch(a)) return SpokenTime(h12, 0);
    return parseTime('$hour $answer');
  }

  // ---------------------------------------------------------------- الردود

  Future<List<DoseEventView>> _today() => _dosesFor(routineDay);

  /// أول جرعة لسه ما اتأكدتش — لو فات معادها بنقول كده (هي اللي «جاية»
  /// فعلاً بالنسبة له)، وإلا الجاية النهارده، وإلا أول واحدة بكرة.
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
    final today = await _today();
    if (today.isEmpty) return 'مفيش أدوية متسجّلة النهارده.';
    final groups = groupByMinute(today);
    final items = <String>[];
    for (final g in groups) {
      final names = [for (final d in g) d.medicationName].join(' و');
      final taken = g.every((d) => d.isDone);
      items.add('$names الساعة ${voiceTime(g.first.scheduledAt)}${taken ? ' — أخدته' : ''}');
    }
    final shownItems = items.take(5).toList();
    final more = items.length > 5 ? '، وحاجات تانية على الشاشة' : '';
    return 'النهارده عندك ${arabicNumber(groups.length)} ${groups.length == 1 ? 'جرعة' : groups.length == 2 ? 'جرعتين' : 'جرعات'}: ${shownItems.join('، ')}$more.';
  }

  /// «مواعيدك الجاية» — من نفس الدالة اللي كارت «يومك» بيقراها.
  Future<String> _upcomingText() async {
    final rows = await RecordsRepository(services.db).all(services.patientId);
    final soon = upcomingAppointments(rows, now: _clock());
    if (soon.isEmpty) return 'مفيش مواعيد جاية متسجّلة.';
    final items = [for (final a in soon.take(3)) '${a.headline} ${a.displayTitle} يوم ${arabicDate(a.at)}'];
    return 'مواعيدك الجاية: ${items.join('، ')}${soon.length > 3 ? '، وحاجات تانية على الشاشة' : ''}.';
  }

  /// «فاضل كام؟» — من نفس حساب «قرب يخلص».
  Future<String> _stockText() async {
    final all = await StockRepository(services.db).all(services.patientId);
    if (all.isEmpty) return 'مفيش مخزون متسجّل — تقدر تكتب اللي عندك من صفحة الدوا.';
    final low = [for (final v in all) if (v.isLow) stockLowLine(v.name, stock: v.quantity, daysLeft: v.daysLeft ?? 0)];
    if (low.isEmpty) return 'كل أدويتك لسه فيها كمية كويسة.';
    return 'قرب يخلص: ${low.join('، ')}.';
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

  Future<void> _setRoutine(VoiceCommand cmd, int gen) async {
    final r = cmd.routine!;
    final anchor = _anchorOf(r.anchorWord);
    if (anchor == null) return _fail(gen);
    final at = DateTime(routineDay.year, routineDay.month, routineDay.day, r.time.hour, r.time.minute);
    _pendingWrite = () async {
      await services.routines.setAnchor(services.patientId, anchor, MinuteOfDay(r.time.minutes));
      await services.scheduler.rescheduleAll(now: _clock());
    };
    await _askYes('أخلّي ${anchor.label} الساعة ${voiceTime(at)}');
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
      case CommandPhase.asking || CommandPhase.idle || CommandPhase.choosing || CommandPhase.answering:
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

  // ---------------------------------------------------------------- ضيفلي / احجزلي

  /// «ضيف دوا» → الفورم العادي **متعبّي** على طول (مفيش كارت تأكيد — الحفظ
  /// بزرار الفورم). ساعة ناقصة الصبح/بالليل، أو مفيش ميعاد خالص = سؤال واحد.
  Future<void> _addMed(VoiceCommand cmd, int gen) async {
    var c = cmd;
    final ambiguous = c.timings.indexWhere((t) => t.hourNeedsPeriod != null);
    if (ambiguous >= 0) {
      final h = c.timings[ambiguous].hourNeedsPeriod!;
      final answer = await _followUp('الساعة ${arabicNumber(h)} الصبح ولا بالليل؟', gen);
      if (answer == null) return;
      final t = _resolveHour(h, answer);
      final timings = [...c.timings];
      timings[ambiguous] = t == null ? const SpokenTiming() : SpokenTiming(fixed: t);
      c = c.copyWith(timings: [for (final x in timings) if (x.fixed != null || x.anchorWord != null) x]);
    } else if (c.timings.isEmpty && c.timesPerDay == null && c.everyHours == null) {
      final answer = await _followUp('تاخده إمتى؟', gen);
      if (answer != null) {
        final more = parseCommand('ضيف دوا ${c.medWords ?? ''} $answer', now: _clock());
        if (more.intent == CommandIntent.addMed && (more.timings.isNotEmpty || more.timesPerDay != null || more.everyHours != null)) {
          c = VoiceCommand(
            CommandIntent.addMed,
            medWords: c.medWords,
            timings: more.timings.where((t) => t.hourNeedsPeriod == null).toList(),
            timesPerDay: more.timesPerDay,
            everyHours: more.everyHours,
            once: c.once || more.once,
            durationDays: c.durationDays ?? more.durationDays,
            startDate: c.startDate ?? more.startDate,
            weekdays: c.weekdays.isNotEmpty ? c.weekdays : more.weekdays,
          );
        }
      } else if (_interrupted(gen) || phase == CommandPhase.idle) {
        return;
      }
    }
    if (_interrupted(gen)) return;
    final purpose = _purposeFromWords(c.medWords);
    prefill = AddMedPrefill(
      name: purpose == null ? c.medWords : null,
      purpose: purpose,
      timings: _timingsFor(c),
      once: c.once,
      durationDays: c.durationDays,
      startDate: c.startDate,
    );
    _set(CommandPhase.done, '');
    unawaited(voice.stop());
    final saved = await onOpenAdd(prefill!);
    if (saved) await _say('cmd_done', phase: CommandPhase.done);
  }

  /// «احجزلي ميعاد» → ورقة «ميعاد جديد» متعبّية. اليوم ناقص = سؤال واحد؛
  /// لسه ناقص = الورقة بتتفتح بالباقي.
  Future<void> _addAppointment(VoiceCommand cmd, int gen) async {
    var a = cmd.appointment!;
    if (a.date == null) {
      final answer = await _followUp('الميعاد إمتى؟', gen);
      if (answer == null) return;
      final dates = extractDates(answer, now: _clock(), future: true);
      if (dates.isNotEmpty) a = a.copyWith(date: dates.first.date);
    } else if (a.hourNeedsPeriod != null) {
      final answer = await _followUp('الساعة ${arabicNumber(a.hourNeedsPeriod!)} الصبح ولا بالليل؟', gen);
      if (answer == null) return;
      final t = _resolveHour(a.hourNeedsPeriod!, answer);
      a = a.copyWith(time: t, clearHour: true);
    }
    if (_interrupted(gen)) return;
    final kind = a.kind == AppointmentKind.lab ? FollowKind.lab : FollowKind.visit;
    final what = switch (a.kind) {
      AppointmentKind.doctor => a.withWhom == null ? 'زيارة دكتور' : 'زيارة دكتور ${a.withWhom}',
      AppointmentKind.lab => a.withWhom == null ? 'تحليل' : 'تحليل ${a.withWhom}',
      AppointmentKind.scan => a.withWhom == null ? 'أشعة' : 'أشعة ${a.withWhom}',
      AppointmentKind.other => a.withWhom ?? 'ميعاد',
    };
    final withTime = a.time == null ? what : '$what — ${arabicTime(DateTime(2026, 1, 1, a.time!.hour, a.time!.minute))}';
    appointmentPrefill = AppointmentPrefill(kind: kind, name: withTime, day: a.date);
    _set(CommandPhase.done, '');
    unawaited(voice.stop());
    final open = onOpenAppointment;
    if (open == null) return;
    final saved = await open(appointmentPrefill!);
    if (saved) await _say('cmd_done', phase: CommandPhase.done);
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

  static DayAnchor? _anchorOf(String? word) => switch (word) {
        'الصحيان' => DayAnchor.wake,
        'الفطار' => DayAnchor.breakfast,
        'الغدا' => DayAnchor.lunch,
        'العشا' => DayAnchor.dinner,
        'النوم' => DayAnchor.sleep,
        _ => null,
      };

  static int _offset(DayAnchor anchor, MealRelation? r) => switch (r) {
        MealRelation.before || null => -defaultOffsetBefore(anchor),
        MealRelation.with_ => 0,
        MealRelation.after => 30,
      };

  /// كلمات المواعيد → مراسي الفورم (نفس عُرف «ضيف دوا»: ١× الفطار، ٢× +العشا،
  /// ٣× +الغدا). الفورم بيعرضها والمريض بيعدّلها — ومفيش حفظ هنا.
  static List<DoseTiming> _timingsFor(VoiceCommand cmd) {
    final out = <DoseTiming>[];
    MealRelation? relationOnly;
    for (final t in cmd.timings) {
      if (t.fixed != null) {
        out.add(FixedTiming(MinuteOfDay(t.fixed!.minutes)));
        continue;
      }
      final anchor = _anchorOf(t.anchorWord);
      if (anchor == null) {
        relationOnly ??= t.relation;
        continue;
      }
      out.add(AnchorTiming(anchor, _offset(anchor, t.relation)));
    }
    if (out.isEmpty && (cmd.timesPerDay != null || relationOnly != null)) {
      const order = [DayAnchor.breakfast, DayAnchor.dinner, DayAnchor.lunch, DayAnchor.sleep, DayAnchor.wake];
      final n = (cmd.timesPerDay ?? 1).clamp(1, order.length);
      for (final a in order.take(n)) {
        out.add(AnchorTiming(a, _offset(a, relationOnly)));
      }
    }
    return out;
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
