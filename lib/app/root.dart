import 'bootstrap.dart' show handleNotificationAction;
import '../data/services/pending_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/care/follower_role.dart';

import '../core/theme/tokens.dart';
import '../data/auth/auth_service.dart';
import '../data/services/reminder_plan.dart';
import '../features/entry/entry_screen.dart';
import '../features/link/sign_in_screen.dart';
import '../features/onboarding/profile_onboarding_screen.dart';
import '../features/reminder/reminder_screen.dart';
import '../features/voice/voice_intro_screen.dart';
import 'app_scope.dart';
import 'shell.dart';
import '../data/services/reminder_scheduler.dart' show logReminderRepairs;

/// بيقرر يبدأ منين — **من البيانات، مش من عمود دور** (٣.٣، D4):
///
/// * فيه مريض محلي («نتعرّف عليك» اتحفظت) → «يومك».
/// * مفيش مريض وفيه جلسة محفوظة محلياً → تطبيق الابن. شاشة المتابعة بتسأل
///   السحابة بنفسها؛ لو قالت «مفيش مريض مربوط» بنرجع لشاشة البداية.
/// * مفيش الاتنين → «مين ماسك التليفون؟». سؤال، مش تسجيل دخول.
///
/// وبيسمع لدوسة الإشعار: أول ما فيه payload و«يومك» اتبنت، بيفتح شاشة
/// التذكير فوقها. لو الدوسة جت والتطبيق لسه بيحمّل، بتستنى.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  /// نفس القاعدة: البث بيتعمل مرة واحدة، مش في كل build.
  Stream<bool>? _hasPatient;
  StreamSubscription<FakkarniUser?>? _authSub;
  ValueNotifier<String?>? _tapPayload;
  bool _shellReady = false;

  /// «التليفون ده ليا» اتضغط — في الذاكرة بس، مش متخزّن ومش دور.
  ///
  /// بيفضّل مسار المريض على مسار الابن: لو دخل بحساب من شاشة الدخول وقفل
  /// التطبيق قبل ما يخلّص «نتعرّف عليك»، عنده جلسة ومفيش مريض — ومن غير
  /// السطر ده الجذر كان هيقراه «ابن» ويوديه للمتابعة.
  bool _patientPath = false;

  /// شاشة الدخول مفتوحة في مسار المريض ولسه ما اتقفلتش. **تحتها بتفضل شاشة
  /// البداية زي ما هي — مش أسئلة البداية**: الأسئلة كانت بتتبني تحت شاشة
  /// الدخول وبتقول «اسم حضرتك إيه؟» والمريض لسه قدّام التسجيل، وصفحة الاسم
  /// نفسها بعدها كانت ساكتة (آيفون، ٢٦ سبتمبر ٢٠٢٦). وفي نفس الوقت الفلاج ده
  /// بيمنع الجلسة اللي ممكن تتعمل من الشاشة دي إنها تتقري «ابن».
  bool _patientSignIn = false;

  /// السحابة قالت «الجلسة دي مالهاش مريض مربوط» — نرجع لشاشة البداية بدل ما
  /// نفضل على متابعة فاضية. بيتصفّر بعد ربط ناجح.
  bool _notLinked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // عند الفتح: تأكيدات الممرض وتغييراته (٠٠٢٣/٠٠٢٤) — مجاملة بعد ما
    // الجدولة خلصت في main، ومن غير ما الشاشة تستناها.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(AppScope.of(context).pullFromCircle());
    });
  }

  /// رجوع للمقدمة = محفّز مزامنة — الجهاز ممكن يكون كان أوفلاين ساعات —
  /// وصحوة لقرار المهلة: لو جرعة عدّى عليها ٤٥ دقيقة وهو بيفتح، «يومك»
  /// لازم تقول «اتنست» دلوقتي مش في الفتحة الجاية.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final services = AppScope.of(context);
      services.sync?.onAppForeground();
      unawaited(
        // الطابور الأول: دوسة على «أخدته» اتكتبت وإحنا في الخلفية بتتطبّق
        // قبل ما الجدولة تتعاد، فـ«يومك» بتفتح على الصف الصح.
        drainPendingActions(
          PendingActionStore(),
          (action, payload) => handleNotificationAction(
              db: services.db, services: services, actionId: action, payload: payload),
        )
            .then((_) => services.scheduler.rescheduleAll())
            .then((_) => logReminderRepairs(services.scheduler.lastRepair, 'الرجوع'))
            .catchError(
              (Object error) =>
                  debugPrint('إعادة الجدولة عند الرجوع فشلت: $error'),
            )
            // المواعيد **بعدها**، ومن غير ما تقدر توقّعها.
            .then((_) => services.refreshAppointments())
            .then((_) => services.refreshRefills())
            // وتأكيدات الممرض (٠٠٢٣) بعد الجدولة — بتلغي وتعيد بنفسها
            .then((_) => services.pullFromCircle())
            // الفحص الآلي **آخر حاجة** — بعد كل وعد، ومجاملة، ومن غير أي إشعار
            .then((_) => services.healthCheckIfDue()),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasPatient != null) return;
    final services = AppScope.of(context);
    _hasPatient = services.patients.watchHasPatient(services.patientId);
    // الجلسة بتتقرا بس (محفوظة محلياً) — مفيش نداء دخول هنا أبداً
    _authSub = services.auth?.authState.listen((_) {
      if (mounted) setState(() {});
    });
    _tapPayload = services.tapPayload?..addListener(_openFromTap);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tapPayload?.removeListener(_openFromTap);
    _authSub?.cancel();
    super.dispose();
  }

  void _openFromTap() {
    final raw = _tapPayload?.value;
    if (raw == null) return;
    if (!_shellReady) return; // هنرجع نبص عليه أول ما «يومك» تتبني

    // بنصفّر في الحالتين: payload مش بتاعنا ما يستاهلش يتفتح عليه تاني.
    _tapPayload!.value = null;
    final payload = decodePayload(raw);
    if (payload == null) return;

    // تنبيه الجرعة بيكسب — الكلام يسكت قبل ما شاشة التذكير تتفتح
    unawaited(AppScope.of(context).voice?.stop());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReminderScreen(
          routineDay: payload.routineDay,
          scheduleIds: payload.scheduleIds,
        ),
      ),
    );
  }

  /// «التليفون ده ليا»: شاشة الدخول الحقيقية الأول — **بتتخطى**. الحساب
  /// للربط بس؛ «كمّل من غير حساب» بتكمّل للأسئلة، والمريض بيوصل «يومك»
  /// من غير جلسة ولا نت زي ما هو. الشاشة بتتعرض بعد دوسة، مش عند الفتح —
  /// حارس `root_test` لسه واقف.
  Future<void> _startPatient() async {
    final services = AppScope.of(context);
    setState(() => _patientSignIn = true);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SignInScreen(
          auth: services.auth,
          caregiver: services.caregiver,
          push: services.push,
          skipLabel: 'كمّل من غير حساب',
        ),
      ),
    );
    // الأسئلة بتتبني **بعد** ما شاشة الدخول تتقفل — فجملة الاسم بتتقال على
    // صفحة الاسم، مش تحت شاشة التسجيل
    if (mounted) {
      setState(() {
        _patientSignIn = false;
        _patientPath = true;
      });
    }
  }

  /// «ابني أو والدي بعتلي كود»: الدخول (النداء الوحيد، من زرار الشاشة دي)
  /// ← الكود ← لو اتربط، المتابعة. فشل أو رجوع = شاشة البداية تاني.
  Future<void> _haveCode() => _linkThrough(FollowerRole.follower);

  /// «أنا ممرض / مرافق»: نفس الطريق بالظبط، بباب الممرض — كود متابع هنا
  /// بيقول «الكود ده لمتابع» ومش بيتحرق.
  Future<void> _nurseCode() => _linkThrough(FollowerRole.nurse);

  Future<void> _linkThrough(FollowerRole door) async {
    final services = AppScope.of(context);
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SignInScreen(
          auth: services.auth,
          caregiver: services.caregiver,
          push: services.push,
          door: door,
          // من غير الإذن تنبيه التصعيد ما بيظهرش على أندرويد ١٣+
          onCaregiverLinked: () => services.scheduler.ensurePermissions(),
        ),
      ),
    );
    if (linked == true && mounted) setState(() => _notLinked = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _hasPatient,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: F.green)),
          );
        }
        // **«نتعرّف عليك» State واحدة لحد ما تتحفظ.** الحفظ بيقلب
        // `hasPatient` لـtrue؛ لو الفرع اتغيّر هنا قبل `onDone`، الشاشة كانت
        // بتتبني من جديد في مكان تاني — State تانية بتعيد جملة الصفحة.
        if (_patientPath) {
          return ProfileOnboardingScreen(
            onBack: snapshot.data == true ? null : () => setState(() => _patientPath = false),
            onDone: () {
              if (mounted) setState(() => _patientPath = false);
            },
          );
        }
        if (snapshot.data == true) return _patientApp(context);
        if (_patientSignIn) {
          return EntryScreen(onSelf: _startPatient, onHaveCode: _haveCode, onNurse: _nurseCode);
        }
        final services = AppScope.of(context);
        if (services.auth?.currentUser != null && !_notLinked) {
          return CaregiverShell(onNotLinked: () {
            if (mounted) setState(() => _notLinked = true);
          });
        }
        // **المقدمة الصوتية أول شاشة في تنزيلة جديدة** — قبل «مين ماسك
        // التليفون ده؟»، عشان لو قال «أيوه، اتكلّم» تلاقي `onb_entry`
        // بتتقال من أول شاشة. مرة واحدة (`introDone`)، و«تخطّي» ظاهر.
        if (services.voice case final voice? when !voice.introDone) {
          return VoiceIntroScreen(voice: voice, onDone: () => setState(() {}));
        }
        return EntryScreen(onSelf: _startPatient, onHaveCode: _haveCode, onNurse: _nurseCode);
      },
    );
  }

  Widget _patientApp(BuildContext context) {
    if (!_shellReady) {
      _shellReady = true;
      // الدوسة اللي جت قبل ما «يومك» تتبني — نفتحها دلوقتي، بعد الفريم.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFromTap();
      });
    }
    return const AppShell();
  }
}
