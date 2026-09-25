import 'bootstrap.dart' show handleNotificationAction;
import '../data/services/pending_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/care/follower_role.dart';

import '../core/theme/tokens.dart';
import '../data/auth/auth_service.dart';
import '../data/services/reminder_plan.dart';
import '../domain/scheduling/day_routine.dart';
import '../features/entry/entry_screen.dart';
import '../features/link/sign_in_screen.dart';
import '../features/onboarding/routine_onboarding_screen.dart';
import '../features/reminder/reminder_screen.dart';
import 'app_scope.dart';
import 'shell.dart';

/// بيقرر يبدأ منين — **من البيانات، مش من عمود دور** (٣.٣، D4):
///
/// * فيه مريض محلي (روتين محفوظ أو جنس اتسأل) → مسار المريض زي ما هو: لو
///   مفيش روتين الأسئلة الأول، وإلا «يومك».
/// * مفيش مريض وفيه جلسة محفوظة محلياً → تطبيق الابن. شاشة المتابعة بتسأل
///   السحابة بنفسها؛ لو قالت «مفيش مريض مربوط» بنرجع لشاشة البداية.
/// * مفيش الاتنين → «مين ماسك التليفون؟». سؤال، مش تسجيل دخول.
///
/// وبيسمع لدوسة الإشعار: أول ما فيه payload وروتين محمّل، بيفتح شاشة
/// التذكير فوق «يومك». لو الدوسة جت والتطبيق لسه بيحمّل، بتستنى الروتين.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  /// نفس القاعدة: البث بيتعمل مرة واحدة، مش في كل build.
  Stream<DayRoutine?>? _routine;
  Stream<bool>? _hasPatient;
  StreamSubscription<FakkarniUser?>? _authSub;
  ValueNotifier<String?>? _tapPayload;
  bool _routineReady = false;

  /// «التليفون ده ليا» اتضغط — في الذاكرة بس، مش متخزّن ومش دور.
  ///
  /// بيفضّل مسار المريض على مسار الابن: لو دخل بحساب من شاشة الدخول وقفل
  /// التطبيق قبل ما يخلّص «نتعرّف عليك»، عنده جلسة ومفيش مريض — ومن غير
  /// السطر ده الجذر كان هيقراه «ابن» ويوديه للمتابعة.
  bool _patientPath = false;

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
            .catchError(
              (Object error) =>
                  debugPrint('إعادة الجدولة عند الرجوع فشلت: $error'),
            )
            // المواعيد **بعدها**، ومن غير ما تقدر توقّعها.
            .then((_) => services.refreshAppointments())
            .then((_) => services.refreshRefills())
            // وتأكيدات الممرض (٠٠٢٣) بعد الجدولة — بتلغي وتعيد بنفسها
            .then((_) => services.pullFromCircle()),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routine != null) return;
    final services = AppScope.of(context);
    _routine = services.routines.watchRoutine(services.patientId);
    _hasPatient = services.routines.watchHasPatient(services.patientId);
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
    if (!_routineReady) return; // هنرجع نبص عليه أول ما الروتين يوصل

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
    setState(() => _patientPath = true);
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
        if (snapshot.data == true) return _patientApp(context);

        if (_patientPath) {
          return RoutineOnboardingScreen(
            onBack: () => setState(() => _patientPath = false),
          );
        }
        final services = AppScope.of(context);
        if (services.auth?.currentUser != null && !_notLinked) {
          return CaregiverShell(onNotLinked: () {
            if (mounted) setState(() => _notLinked = true);
          });
        }
        return EntryScreen(onSelf: _startPatient, onHaveCode: _haveCode, onNurse: _nurseCode);
      },
    );
  }

  Widget _patientApp(BuildContext context) {
    return StreamBuilder<DayRoutine?>(
      stream: _routine,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: F.green)),
          );
        }
        if (snapshot.data == null) {
          return const RoutineOnboardingScreen();
        }
        if (!_routineReady) {
          _routineReady = true;
          // الدوسة اللي جت قبل ما الروتين يوصل — نفتحها دلوقتي، بعد الفريم.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openFromTap();
          });
        }
        return AppShell(routine: snapshot.data!);
      },
    );
  }
}
