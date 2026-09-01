import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../data/services/reminder_plan.dart';
import '../domain/scheduling/day_routine.dart';
import '../features/onboarding/routine_onboarding_screen.dart';
import '../features/reminder/reminder_screen.dart';
import '../features/today/today_screen.dart';
import 'app_scope.dart';

/// بيقرر يبدأ منين: لو مفيش روتين محفوظ، الأسئلة الأول.
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
  ValueNotifier<String?>? _tapPayload;
  bool _routineReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// رجوع للمقدمة = محفّز مزامنة — الجهاز ممكن يكون كان أوفلاين ساعات.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppScope.of(context).sync?.onAppForeground();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routine != null) return;
    final services = AppScope.of(context);
    _routine = services.routines.watchRoutine(services.patientId);
    _tapPayload = services.tapPayload?..addListener(_openFromTap);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tapPayload?.removeListener(_openFromTap);
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DayRoutine?>(
      stream: _routine,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
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
        return TodayScreen(routine: snapshot.data!);
      },
    );
  }
}
