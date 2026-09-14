import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../domain/patient/sex.dart';

/// الصوت اللي التطبيق بيكلّم بيه المريض — [Say] بجنسه.
///
/// الشاشات بتقرا `PatientVoice.of(context)` بدل ما كل واحدة تسأل قاعدة
/// البيانات. من غير ما حد يحطّه فوق الشجرة (اختبارات شاشة لوحدها مثلاً)
/// بيرجع `Say(null)` — المذكّر اللي كان عليه النص قبل نسخة ٨.
class PatientVoice extends InheritedWidget {
  const PatientVoice({required this.say, required super.child, super.key});

  final Say say;

  static Say of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PatientVoice>()?.say ?? const Say(null);

  @override
  bool updateShouldNotify(PatientVoice old) => old.say.sex != say.sex;
}

/// بيسمع لصف المريض وبيحدّث [PatientVoice] — بيتحط مرة واحدة فوق الـNavigator
/// عشان كل شاشة (حتى اللي بتتفتح بـpush) تشوفه.
class PatientVoiceScope extends StatefulWidget {
  const PatientVoiceScope({required this.child, super.key});

  final Widget child;

  @override
  State<PatientVoiceScope> createState() => _PatientVoiceScopeState();
}

class _PatientVoiceScopeState extends State<PatientVoiceScope> {
  StreamSubscription<Object?>? _sub;
  Sex? _sex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final services = AppScope.of(context);
    _sub = services.routines.watchPatient(services.patientId).listen((row) {
      if (mounted && row?.sex != _sex) setState(() => _sex = row?.sex);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PatientVoice(say: Say(_sex), child: widget.child);
}
