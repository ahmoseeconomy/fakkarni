import 'dart:async';

import 'package:flutter/material.dart';

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

  /// اختيار شاشة البداية لمسار المريض — في الذاكرة بس، مش متخزّن. null =
  /// لسه ما اختارش. true = «بظبّط لحد تاني».
  bool? _forSomeoneElse;

  /// السحابة قالت «الجلسة دي مالهاش مريض مربوط» — نرجع لشاشة البداية بدل ما
  /// نفضل على متابعة فاضية. بيتصفّر بعد ربط ناجح.
  bool _notLinked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        services.scheduler.rescheduleAll().catchError(
              (Object error) =>
                  debugPrint('إعادة الجدولة عند الرجوع فشلت: $error'),
            ),
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

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReminderScreen(
          routineDay: payload.routineDay,
          scheduleIds: payload.scheduleIds,
        ),
      ),
    );
  }

  /// «ابني أو والدي بعتلي كود»: الدخول (النداء الوحيد، من زرار الشاشة دي)
  /// ← الكود ← لو اتربط، المتابعة. فشل أو رجوع = شاشة البداية تاني.
  Future<void> _haveCode() async {
    final services = AppScope.of(context);
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SignInScreen(
          auth: services.auth,
          caregiver: services.caregiver,
          push: services.push,
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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: F.green)),
          );
        }
        if (snapshot.data == true) return _patientApp(context);

        if (_forSomeoneElse != null) {
          return RoutineOnboardingScreen(
            forSomeoneElse: _forSomeoneElse!,
            onBack: () => setState(() => _forSomeoneElse = null),
          );
        }
        final services = AppScope.of(context);
        if (services.auth?.currentUser != null && !_notLinked) {
          return CaregiverShell(onNotLinked: () {
            if (mounted) setState(() => _notLinked = true);
          });
        }
        return EntryScreen(
          onSelf: () => setState(() => _forSomeoneElse = false),
          onForSomeoneElse: () => setState(() => _forSomeoneElse = true),
          onHaveCode: _haveCode,
        );
      },
    );
  }

  Widget _patientApp(BuildContext context) {
    return StreamBuilder<DayRoutine?>(
      stream: _routine,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: F.green)),
          );
        }
        if (snapshot.data == null) {
          // الصوت بيفضل زي ما اختار في شاشة البداية لحد ما الأسئلة تخلص
          return RoutineOnboardingScreen(forSomeoneElse: _forSomeoneElse ?? false);
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
