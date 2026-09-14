import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fa_mark.dart';
import '../../core/widgets/primitives.dart';
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
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: F.greenDeep,
                  borderRadius: BorderRadius.circular(F.radiusTile),
                ),
                alignment: Alignment.center,
                child: const FaMark(size: 42),
              ),
            ),
            const SizedBox(height: F.s12),
            const Text(
              'سجّل الدخول للربط',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.screenTitleSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
              ),
            ),
            const SizedBox(height: F.s8),
            const Text(
              'عشان لو جرعة مهمة فاتت، نعرف نكلّم ابنك على موبايله هو. '
              'الربط ده محتاج حساب يعرّفنا مين أنت — والتطبيق من غيره '
              'شغّال بكل حاجة تانية عادي.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.7),
            ),
            const SizedBox(height: F.s12),
            // الحقيقة: الدخول دلوقتي مجهول (دين تقني ٢) — بنسمّيه باسمه. رمادي مش
            // ذهبي: ده وصف، مش حاجة محتاجة انتباهه دلوقتي.
            const Center(child: StatusChip(label: 'حساب تجريبي')),
            const SizedBox(height: F.gap),
            if (widget.auth == null)
              const _Panel(text: SupabaseAuthConfig.missingConfigMessage)
            else if (_user != null) ...[
              // الدورين من البيانات مش من الحساب: الأب بيطلع كوداً،
              // والابن بيكتب كوداً — نفس الحساب، نفس الشاشة (بشكل المخطط ٢).
              _PathCard(
                icon: Icons.person_outline,
                title: 'اعرض كود الربط',
                hint: 'أنا صاحب الأدوية — عايز ابني يتابعني',
                onTap: _busy ? null : _showCode,
              ),
              const SizedBox(height: F.s10),
              if (_followed != null) ...[
                _PathCard(
                  icon: Icons.visibility_outlined,
                  title: 'متابعة ${_followed!.name}',
                  hint: 'افتح جدوله وتنبيهاته',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CaregiverScreen(remote: widget.caregiver!),
                    ),
                  ),
                ),
                const SizedBox(height: F.s10),
              ],
              _PathCard(
                icon: Icons.link,
                title: 'عندي كود من والدي',
                hint: 'أنا بتابع حد — معايا كود الربط بتاعه',
                onTap: _busy
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
              ),
              const SizedBox(height: F.gap),
              FSecondaryButton(label: 'تسجيل الخروج', onPressed: _busy ? null : _signOut),
            ] else ...[
              if (_error != null) ...[
                _Panel(text: _error!),
                const SizedBox(height: F.gap),
              ],
              // معروضين عشان يبان إنهم جايين — **معطّلين**، وكل واحد بسببه هو
              const _UnavailableRow(
                title: 'المتابعة بحساب Google',
                reason: 'قريباً',
              ),
              const SizedBox(height: F.s8),
              const _UnavailableRow(
                title: 'المتابعة بحساب Apple',
                reason: 'محتاج حساب Apple Developer',
              ),
              const SizedBox(height: F.gap),
              // الزرار الشغّال الوحيد
              FPrimaryButton(
                label: _busy ? 'ثواني…' : 'كمّل بحساب تجريبي',
                onPressed: _busy ? null : _signIn,
              ),
            ],
            const SizedBox(height: F.s4),
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

/// طريقة دخول مش متاحة: معروضة بشكل واضح إنها **مش زرار** — مفيش InkWell،
/// تعبئة باهتة، قفل، والسبب الحقيقي بتاعها هي مكتوب جنبها.
class _UnavailableRow extends StatelessWidget {
  const _UnavailableRow({required this.title, required this.reason});

  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$title — مش متاح: $reason',
        enabled: false,
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: F.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
          decoration: BoxDecoration(
            color: F.ivoryPale,
            borderRadius: BorderRadius.circular(F.radiusCard),
            border: Border.all(color: F.lineSoft),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 22, color: F.mutedLight),
              const SizedBox(width: F.s10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                ),
              ),
              const SizedBox(width: F.s8),
              Flexible(
                child: Text(
                  reason,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                ),
              ),
            ],
          ),
        ),
      );
}

/// اختيار طريق بعد الدخول — كارت بأيقونة وعنوان وسطر، بشكل المخطط ٢.
class _PathCard extends StatelessWidget {
  const _PathCard({required this.icon, required this.title, required this.hint, required this.onTap});

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(F.radiusCard),
          side: const BorderSide(color: F.line, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radiusCard),
          child: Container(
            constraints: const BoxConstraints(minHeight: F.primaryButtonHeight),
            padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: F.ivoryWarm,
                    borderRadius: BorderRadius.circular(F.radiusTile),
                  ),
                  child: Icon(icon, size: 24, color: F.ink),
                ),
                const SizedBox(width: F.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                      Text(hint, style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.4)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left, size: 26, color: F.muted),
              ],
            ),
          ),
        ),
      );
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
