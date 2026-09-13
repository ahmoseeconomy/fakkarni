import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/auth/auth_service.dart';
import '../../data/push/push_tokens.dart';
import '../../data/auth/supabase_init.dart';
import '../../data/care/caregiver_remote.dart';
import '../care/caregiver_screen.dart';
import 'link_code_screen.dart';
import 'redeem_code_screen.dart';

/// شاشة الدخول — بتتفتح من «اربط ابني» وبس، عمرها ما بتقف في وش حد.
///
/// «مش دلوقتي» بترجّع المستخدم لتطبيق كامل شغّال — الحساب للربط، مش شرط
/// لأي حاجة تانية.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.auth,
    this.caregiver,
    this.push,
    super.key,
  });

  /// null = إعداد Supabase مش موجود، والشاشة بتقول ده بوضوح.
  final AuthService? auth;

  /// توكن الدفع — بيتحقن زي [auth] مش بيتسحب من AppScope، عشان مسار
  /// الخروج ما يعتمدش على وجود الـscope فوق الشجرة. الخروج لازم يشتغل
  /// دايماً؛ ده مش مكان لـassert.
  final PushTokens? push;

  /// لو فيه علاقة accepted، بيظهر «متابعة {الاسم}».
  final CaregiverRemote? caregiver;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  StreamSubscription<FakkarniUser?>? _sub;
  FakkarniUser? _user;
  CaregiverPatient? _followed;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = widget.auth?.currentUser;
    _sub = widget.auth?.authState.listen((user) {
      if (mounted) setState(() => _user = user);
      if (user != null) _checkFollowed();
    });
    if (_user != null) _checkFollowed();
  }

  /// فيه حد بنتابعه؟ فشل الشبكة هنا صامت — الزرار بس هو اللي مش بيظهر.
  Future<void> _checkFollowed() async {
    try {
      final patient = await widget.caregiver?.linkedPatient();
      if (mounted) setState(() => _followed = patient);
    } catch (_) {}
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
      // التوكن يتسجّل دلوقتي حالاً. السماع في `start()` بيمسك ده برضه،
      // بس الابن ممكن يقفل التطبيق على طول بعد الربط — وأول جرعة
      // فايتة ممكن تكون بعدها بساعة.
      await widget.push?.registerNow();
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

  /// طريق الأب: صف المريض المحلي (uuid + اسم) → شاشة الكود.
  Future<void> _showCode() async {
    final services = AppScope.of(context);
    final care = services.care;
    if (care == null) return;
    final navigator = Navigator.of(context);

    final patient = await services.routines.getPatient(services.patientId);
    if (patient == null || !mounted) return;

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => LinkCodeScreen(
          care: care,
          patientUuid: patient.uuid,
          patientName: patient.name,
          sync: services.sync,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    // **قبل** الخروج، مش بعده: مسح صف التوكن محتاج الجلسة الحالية. لو
    // اتعكس الترتيب، الصف بيفضل في السحابة وموبايل خرج من حسابه يفضل
    // يستقبل تنبيهات عن مريض بقى غريب عنه.
    await widget.push?.clear();
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
              // الدورين من البيانات مش من الحساب: الأب بيطلع كوداً،
              // والابن بيكتب كوداً — نفس الحساب، نفس الشاشة.
              SizedBox(
                height: F.primaryButtonHeight,
                child: FilledButton(
                  onPressed: _busy ? null : _showCode,
                  child: const Text('اعرض كود الربط'),
                ),
              ),
              const SizedBox(height: 10),
              if (_followed != null) ...[
                SizedBox(
                  height: F.primaryButtonHeight,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CaregiverScreen(remote: widget.caregiver!),
                      ),
                    ),
                    child: Text(
                      'متابعة ${_followed!.name}',
                      style: const TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: F.primaryButtonHeight,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final care = AppScope.of(context).care;
                          if (care == null) return;
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RedeemCodeScreen(
                                    care: care,
                                    caregiver: widget.caregiver,
                                  ),
                                ),
                              )
                              .then((_) => _checkFollowed());
                        },
                  child: const Text(
                    'عندي كود من والدي',
                    style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600),
                  ),
                ),
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
