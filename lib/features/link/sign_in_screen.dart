import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/auth/auth_service.dart';
import '../../data/auth/supabase_init.dart';

/// شاشة الدخول — بتتفتح من «اربط ابني» وبس، عمرها ما بتقف في وش حد.
///
/// «مش دلوقتي» بترجّع المستخدم لتطبيق كامل شغّال — الحساب للربط، مش شرط
/// لأي حاجة تانية.
class SignInScreen extends StatefulWidget {
  const SignInScreen({required this.auth, super.key});

  /// null = إعداد Supabase مش موجود، والشاشة بتقول ده بوضوح.
  final AuthService? auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  StreamSubscription<FakkarniUser?>? _sub;
  FakkarniUser? _user;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = widget.auth?.currentUser;
    _sub = widget.auth?.authState.listen((user) {
      if (mounted) setState(() => _user = user);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _signIn() async {
    final auth = widget.auth;
    if (auth == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // النداء الوحيد في التطبيق كله — من الزرار ده وبس.
      await auth.signInToLink();
    } on SignInException catch (e) {
      // الإلغاء بإيده مش خطأ — ولا رسالة.
      if (mounted && e.message != null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'مقدرناش نكمّل التسجيل. جرّب تاني.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.auth?.signOut();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الربط',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(F.gap),
          children: [
            const Text(
              'ليه محتاجين حساب؟',
              style: TextStyle(
                fontSize: F.questionSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'عشان لو جرعة مهمة فاتت، نعرف نكلّم ابنك على موبايله هو. '
              'الربط ده محتاج حساب يعرّفنا مين أنت — والتطبيق من غيره '
              'شغّال بكل حاجة تانية عادي.',
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.7),
            ),
            const SizedBox(height: F.gap),
            if (widget.auth == null)
              const _Panel(text: SupabaseAuthConfig.missingConfigMessage)
            else if (_user != null) ...[
              _Panel(
                text: _user!.email == null
                    ? 'اتربط الجهاز ده. باقي الربط بييجي من موبايل ابنك.'
                    : 'الحساب متوصّل: ${_user!.email}',
              ),
              const SizedBox(height: F.gap),
              SizedBox(
                height: F.minTapTarget,
                child: OutlinedButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text(
                    'تسجيل الخروج',
                    style: TextStyle(fontSize: F.minTextSize + 1, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else ...[
              if (_error != null) ...[
                _Panel(text: _error!),
                const SizedBox(height: F.gap),
              ],
              SizedBox(
                height: F.primaryButtonHeight,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: Text(_busy ? 'ثواني…' : 'اربط ابني'),
                ),
              ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              height: F.minTapTarget,
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text(
                  'مش دلوقتي',
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w600,
                    color: F.green,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
      );
}
