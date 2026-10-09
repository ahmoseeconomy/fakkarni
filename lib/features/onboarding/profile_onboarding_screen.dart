import 'dart:async';

import '../voice/help_button.dart';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/voice/voice_catalog.dart';
import 'onboarding_voice.dart';
import 'profile_page.dart';

/// «نتعرّف عليك» — الاسم، وبعدها السن (اختياري). وبعدها «يومك» على طول.
///
/// كان فيه بعدها خمس أسئلة عن الصحيان والأكل والنوم وسؤال «راجل ولا ست؟»؛
/// كلهم اتشالوا بقرار المالك (٢٧ سبتمبر ٢٠٢٦): الناس في مصر ما عندهاش
/// مواعيد أكل ونوم ثابتة، والأدوية بتتجدول بالساعة. سؤال واحد في المرة
/// عن قصد: المستخدم عنده ٧٢ سنة وبيقرا بنضارة.
class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({this.onDone, this.onBack, super.key});

  /// بيتندَه بعد ما البيانات تتحفظ وتتعاد جدولة التذكيرات.
  final VoidCallback? onDone;

  /// الرجوع لشاشة البداية — موجود بس قبل ما يبقى فيه مريض (اختيار غلط
  /// ما يحبسش حد في مسار مش بتاعه).
  final VoidCallback? onBack;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  final _profile = GlobalKey<ProfilePageState>();
  bool _saving = false;

  /// null = لسه بنقرا صف المريض.
  String? _name;
  bool _ready = false;

  /// صفحة «نتعرّف عليك» الحالية: ٠ الاسم، ١ السن.
  int _step = 0;

  /// جمل البداية اللي بتتقال لوحدها — لو قال «أيوه، اتكلّم» بس.
  OnboardingVoice _voice = OnboardingVoice(null);

  static const _lines = ['onb_name', 'onb_age'];

  String get _pageLine => _lines[_step];

  /// جملة الصفحة — لوحدها، مرة واحدة لكل صفحة.
  void _announce() {
    if (!_ready) return;
    unawaited(_voice.auto([_pageLine], key: _pageLine));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_voice.voice == null) {
      _voice = OnboardingVoice(AppScope.of(context).voice);
    }
    if (_ready) return;
    final services = AppScope.of(context);
    services.patients.getPatient(services.patientId).then((row) {
      if (!mounted) return;
      setState(() {
        _name = row?.name;
        _ready = true;
      });
      _announce();
    });
  }

  Future<void> _save({required String name, int? age}) async {
    if (_saving) return;
    setState(() => _saving = true);
    _voice.hush();
    final services = AppScope.of(context);
    await services.patients.saveProfile(
      services.patientId,
      name: name,
      age: age,
    );

    // الأذونات بتتطلب هنا مش عند أول فتح — دلوقتي بقى واضح ليه التطبيق
    // محتاجها.
    await services.scheduler.ensurePermissions();
    await services.scheduler.rescheduleAll();

    if (!mounted) return;
    widget.onDone?.call();
  }

  @override
  void dispose() {
    // سابت الصفحة = الكلام يسكت
    _voice.hush();
    super.dispose();
  }

  void _profileTo(int step) {
    _voice.hush();
    setState(() => _step = step);
    _announce();
  }

  /// «رجوع» فوق: صفحة لورا، وإلا لشاشة البداية.
  VoidCallback? get _back {
    if (_step > 0) return () => _profileTo(_step - 1);
    final out = widget.onBack;
    if (out == null) return null;
    return () {
      _voice.hush();
      out();
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: !_ready
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      F.gap,
                      F.gap,
                      F.gap,
                      F.s4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_back != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(
                              height: F.minTapTarget,
                              child: TextButton.icon(
                                key: const ValueKey('onboarding-back'),
                                onPressed: _back,
                                icon: const Icon(Icons.arrow_back, size: 22),
                                label: const Text('رجوع'),
                                style: TextButton.styleFrom(
                                  foregroundColor: F.green,
                                  minimumSize: const Size(0, F.minTapTarget),
                                  textStyle: const TextStyle(
                                    fontSize: F.minBodySize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const Kicker('أول خطوة'),
                        const SizedBox(height: F.s4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'نتعرّف عليك',
                                style: TextStyle(
                                  fontFamily: F.displayFamily,
                                  fontSize: F.screenTitleSize,
                                  fontWeight: FontWeight.w700,
                                  color: F.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: F.s8),
                            // جملة الصفحة نفسها — نفس اللي اتقالت لوحدها
                            HelpButton(_pageLine),
                          ],
                        ),
                        const SizedBox(height: F.s6),
                        Text(
                          voiceLine(_pageLine),
                          key: const ValueKey('onboarding-voice-caption'),
                          style: TextStyle(
                            fontSize: F.minTextSize,
                            color: F.mutedDark,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ProfilePage(
                      key: _profile,
                      initialName: _name,
                      onDone: _save,
                      step: _step,
                      onStep: _profileTo,
                      onInteract: _voice.hush,
                      busy: _saving,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
