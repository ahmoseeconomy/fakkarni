import 'package:flutter/material.dart';

import '../data/admin_service.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'widgets/admin_ui.dart';
import 'widgets/brand_mark.dart';
import 'widgets/motion_widgets.dart';

/// دخول بإيميل وباسورد — مفيش تسجيل حساب، ومفيش دخول مجهول.
///
/// **بعد الدخول بيتنده `counts()` فوراً**: الحساب ممكن يكون حقيقي وبرضه
/// مش أدمن، والسيرفر هو اللي بيقول. لو قال «مش أدمن»، الشاشة بتقول الجملة
/// **وبتعمل خروج** — جلسة واقفة على حساب مش مسموح له حاجة ملهاش لازمة.
class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.service, required this.onSignedIn, super.key});

  final AdminService service;
  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.signIn(email: _email.text, password: _password.text);
      await widget.service.counts();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onSignedIn();
    } on AdminException catch (e) {
      if (e.failure == AdminFailure.notAdmin) {
        await widget.service.signOut();
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonGround = F.isDark ? F.green : F.greenDeep;
    final buttonInk = F.isDark ? F.inkDeep : F.onDark;
    return Scaffold(
      backgroundColor: brandGround,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(F.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMarkHero(size: 128),
              const SizedBox(height: F.s22),
              // الكارت بيلحق العلامة بشوية — الاتنين مع بعض كانوا هيتقاطعوا.
              FadeSlideIn(
                delay: motionDuration(context, Motion.quick),
                child: SizedBox(
                  width: 380,
                  child: Container(
                    padding: const EdgeInsets.all(F.s22),
                    decoration: BoxDecoration(
                      color: loginCardGround,
                      borderRadius: BorderRadius.circular(F.radiusSection),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'لوحة فكرني',
                          style: TextStyle(
                            fontFamily: F.displayFamily,
                            fontSize: F.screenTitleSize,
                            fontWeight: FontWeight.w700,
                            color: F.ink,
                          ),
                        ),
                        const SizedBox(height: F.s4),
                        Text(
                          'قراية بس — أرقام تشغيل، مفيش بيانات طبية.',
                          style: TextStyle(
                            fontFamily: F.bodyFamily,
                            fontSize: F.careTextSize,
                            color: F.mutedDark,
                          ),
                        ),
                        const SizedBox(height: F.s20),
                        _field(_email, 'الإيميل', TextInputAction.next),
                        const SizedBox(height: F.s10),
                        _field(_password, 'الباسورد', TextInputAction.done, obscure: true),
                        if (_error != null) ...[
                          const SizedBox(height: F.s10),
                          AdminPanel(text: _error!),
                        ],
                        const SizedBox(height: F.s20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            backgroundColor: buttonGround,
                            foregroundColor: buttonInk,
                            disabledBackgroundColor: buttonGround.withValues(alpha: 0.7),
                            disabledForegroundColor: buttonInk,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(F.radiusTile),
                            ),
                          ),
                          child: _busy
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: buttonInk,
                                      ),
                                    ),
                                    const SizedBox(width: F.s10),
                                    const Text('ثانية…'),
                                  ],
                                )
                              : const Text(
                                  'دخول',
                                  style: TextStyle(
                                    fontFamily: F.bodyFamily,
                                    fontSize: F.careBodySize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    TextInputAction action, {
    bool obscure = false,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        textInputAction: action,
        onSubmitted: action == TextInputAction.done ? (_) => _submit() : null,
        style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careBodySize, color: F.ink),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              fontFamily: F.bodyFamily, fontSize: F.careTextSize, color: F.mutedDark),
          filled: true,
          fillColor: F.fieldGround,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            borderSide: BorderSide(color: F.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            borderSide: BorderSide(color: F.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(F.radiusTile),
            borderSide: const BorderSide(color: F.gold, width: 1.5),
          ),
        ),
      );
}
