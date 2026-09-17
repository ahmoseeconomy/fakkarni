import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/auth/auth_service.dart';
import '../link/sign_in_screen.dart';
import 'scan_stage.dart';

/// باب قراية الصور (C2): الكاميرا بتبان بس لما فيه حد يقراها.
///
/// من بعد C2 القراية بتعدّي من دالتنا في السحابة بجلسة المستخدم — التطبيق
/// مالوش مفتاح. فمن غير جلسة الشاشة **ما بتفشلش في صمت** ولا بتسيبه يصوّر
/// وبعدين تقوله لأ: سطر واحد صريح وزرار لباب الدخول الموجود.
///
/// **الإدخال بالإيد دايماً موجود** — عمره ما احتاج حساب ولسه مش محتاج.
///
/// الدخول بيحصل جوّه [SignInScreen] وبس (النداء الوحيد لـ`signInToLink`)،
/// والشاشة دي بتتفتح بدوسة — حارس `root_test` لسه بيثبت إن مفيش دخول عند الفتح.
class AiReadGate extends StatelessWidget {
  const AiReadGate({
    required this.hasReader,
    required this.auth,
    required this.needsSignIn,
    required this.signInLine,
    required this.byHandLabel,
    required this.onByHand,
    required this.onSignInClosed,
    required this.child,
    super.key,
  });

  /// false = السحابة مش متظبطة في النسخة دي (من غير SUPABASE_URL).
  final bool hasReader;

  /// null في اختبارات الشاشة — ساعتها الباب ما بيحكمش، والقارئ نفسه هو اللي
  /// بيقول «مفيش جلسة» ([needsSignIn]).
  final AuthService? auth;

  /// السحابة ردّت ٤٠١ أو القارئ ما لقاش جلسة.
  final bool needsSignIn;

  final String signInLine;
  final String byHandLabel;
  final VoidCallback onByHand;

  /// رجع من شاشة الدخول — الشاشة بتصفّر حالة الفشل.
  final VoidCallback onSignInClosed;

  /// الكاميرا وباقي الشاشة.
  final Widget child;

  static const notConfiguredLine = 'قراية الصور مش متظبطة في النسخة دي — اكتبها بإيدك.';

  Future<void> _openSignIn(BuildContext context) async {
    final services = AppScope.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignInScreen(
          auth: services.auth,
          caregiver: services.caregiver,
          push: services.push,
        ),
      ),
    );
    onSignInClosed();
  }

  @override
  Widget build(BuildContext context) {
    if (!hasReader) {
      return _Closed(line: notConfiguredLine, byHandLabel: byHandLabel, onByHand: onByHand);
    }
    final auth = this.auth;
    if (auth == null) {
      return needsSignIn
          ? _Closed(line: signInLine, byHandLabel: byHandLabel, onByHand: onByHand, onSignIn: () => _openSignIn(context))
          : child;
    }
    return StreamBuilder<FakkarniUser?>(
      stream: auth.authState,
      initialData: auth.currentUser,
      builder: (context, _) {
        // `currentUser` هو الحقيقة — البث بس اللي بيصحّي الشاشة لما تتغيّر.
        final signedOut = auth.currentUser == null;
        if (!signedOut && !needsSignIn) return child;
        return _Closed(
          line: signInLine,
          byHandLabel: byHandLabel,
          onByHand: onByHand,
          onSignIn: () => _openSignIn(context),
        );
      },
    );
  }
}

class _Closed extends StatelessWidget {
  const _Closed({required this.line, required this.byHandLabel, required this.onByHand, this.onSignIn});

  final String line;
  final String byHandLabel;
  final VoidCallback onByHand;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelOnDark(text: line),
        const SizedBox(height: F.gap),
        if (onSignIn != null) ...[
          SizedBox(
            height: F.primaryButtonHeight,
            child: FilledButton(
              key: const ValueKey('ai-sign-in'),
              onPressed: onSignIn,
              style: FilledButton.styleFrom(
                backgroundColor: F.green,
                foregroundColor: F.onDark,
                textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
              ),
              child: const Text('سجّل دخول'),
            ),
          ),
          const SizedBox(height: F.s10),
        ],
        SizedBox(
          height: F.minTapTarget,
          child: SecondaryOnDark(label: byHandLabel, onPressed: onByHand),
        ),
      ],
    );
  }
}
