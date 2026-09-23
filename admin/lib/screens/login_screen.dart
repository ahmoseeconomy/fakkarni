import 'package:flutter/material.dart';

import '../data/admin_service.dart';
import '../theme/tokens.dart';
import 'widgets/admin_ui.dart';

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
    return Scaffold(
      backgroundColor: F.pageGround,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(F.s16),
          child: SizedBox(
            width: 360,
            child: AdminCard(
              padding: const EdgeInsets.all(F.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AdminHead('لوحة فكرني'),
                  const SizedBox(height: F.s4),
                  Text(
                    'قراية بس — أرقام تشغيل، مفيش بيانات طبية.',
                    style: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careTextSize,
                        color: F.mutedDark),
                  ),
                  const SizedBox(height: F.s16),
                  _field(_email, 'الإيميل', TextInputAction.next),
                  const SizedBox(height: F.careRowGap),
                  _field(_password, 'الباسورد', TextInputAction.done, obscure: true),
                  if (_error != null) ...[
                    const SizedBox(height: F.careRowGap),
                    AdminPanel(text: _error!),
                  ],
                  const SizedBox(height: F.s16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, F.careTapTarget),
                      backgroundColor: F.greenDeep,
                      foregroundColor: F.onDark,
                    ),
                    child: Text(
                      _busy ? 'ثانية…' : 'دخول',
                      style: const TextStyle(
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
        style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careBodySize),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careTextSize),
          filled: true,
          fillColor: F.fieldGround,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusChip)),
        ),
      );
}
