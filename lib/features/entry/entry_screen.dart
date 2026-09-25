import '../../core/widgets/legal_links_row.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../onboarding/onboarding_voice.dart';
import '../voice/help_button.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/fa_mark.dart';
import '../../core/widgets/primitives.dart';

/// «مين ماسك التليفون؟» (D4، بأسلوب كروت المخطط ٢) — أول شاشة في تنزيلة
/// جديدة: تلات أبواب — المريض، المتابع، والممرض (٢٤ سبتمبر ٢٠٢٦).
///
/// كان فيه كارت تالت «بظبّط لحد تاني»، وكل اللي كان بيعمله إنه يقلب كلام
/// الإعداد للغايب — اختيار ما بيتخزّنش ومفيش حاجة بتترتب عليه. اتشال:
/// اللي بيظبّط لحد تاني بيكتب بيانات المريض في نفس الشاشة، والتطبيق بيكلّم
/// المريض نفسه لأنه هو اللي هيمسك التليفون.
///
/// **سؤال مش تسجيل دخول**: مفيش جلسة ولا نداء دخول هنا (حارس `root_test`).
/// كل كارت هو الفعل نفسه — مفيش «اختار وبعدين يلا نبدأ» زي المخطط، خطوة
/// واحدة أسهل على إيد عندها ٧٢ سنة. الشاشة **بتوجّه وبس**: الاختيار مش
/// متخزّن (مفيش عمود دور — ٣.٣). بتختفي للأبد أول ما يبقى فيه مريض محلي أو
/// علاقة رعاية، والجذر هو اللي بيقرر ده من البيانات.
class EntryScreen extends StatefulWidget {
  const EntryScreen({required this.onSelf, required this.onHaveCode, this.onNurse, super.key});

  /// «التليفون ده ليا» → شاشة الدخول (تتخطى) → نتعرّف عليك → ظبّط يومك.
  final VoidCallback onSelf;

  /// «معايا كود متابعة» → الدخول → الكود → المتابعة.
  final VoidCallback onHaveCode;

  /// «أنا ممرض / مرافق» (٢٤ سبتمبر ٢٠٢٦، قرار المالك) → الدخول → كود
  /// **ممرض** بس → تطبيق المرآة. null = الباب مش معروض (شاشة من غير سحابة).
  final VoidCallback? onNurse;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

enum _Choice { self, code, nurse }

class _EntryScreenState extends State<EntryScreen> {
  _Choice? _choice;

  /// «مين اللي ماسك التليفون ده؟…» بتتقال لوحدها لو الصوت شغّال — يعني
  /// رجع هنا من البداية بعد ما قال «أيوه، اتكلّم». أول فتحة خالص المقدمة
  /// لسه ما جتش، فالشاشة ساكتة.
  OnboardingVoice _voice = OnboardingVoice(null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_voice.voice != null) return;
    _voice = OnboardingVoice(AppScope.maybeOf(context)?.voice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_voice.auto(const ['onb_entry']));
    });
  }

  @override
  void dispose() {
    _voice.hush();
    super.dispose();
  }

  void _pick(_Choice c) {
    _voice.hush();
    setState(() => _choice = c);
  }

  void _start() {
    _voice.hush();
    switch (_choice) {
      case _Choice.self:
        widget.onSelf();
      case _Choice.code:
        widget.onHaveCode();
      case _Choice.nurse:
        widget.onNurse?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        // أرضية بيضا زي المخطط — الكروت هي اللي بتبان عليها
        backgroundColor: F.pageGround,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(F.gap, F.s30, F.gap, F.gap),
                  children: [
                    const Center(child: FaMark(size: 76, letterColor: F.greenDeep)),
                    const SizedBox(height: F.gap),
                    Text(
                      'أهلاً بيك في فكّرني',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: F.displayFamily,
                        fontSize: F.screenTitleSize,
                        fontWeight: FontWeight.w700,
                        color: F.ink,
                      ),
                    ),
                    const SizedBox(height: F.s6),
                    Text(
                      'مين ماسك التليفون ده؟ تقدر تغيّر أو تضيف حد تاني في أي وقت.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                    ),
                    // بيظهر بس والصوت شغّال — وبيعيد نفس الجملة
                    const Center(child: HelpButton('onb_entry')),
                    const SizedBox(height: F.s22),
                    _EntryCard(
                      itemKey: const ValueKey('entry-self'),
                      icon: Icons.person_outline,
                      title: 'التليفون ده ليا',
                      hint: 'أنا اللي باخد الدوا',
                      selected: _choice == _Choice.self,
                      onTap: () => _pick(_Choice.self),
                    ),
                    const SizedBox(height: F.s12),
                    _EntryCard(
                      itemKey: const ValueKey('entry-code'),
                      icon: Icons.link,
                      title: 'معايا كود متابعة',
                      hint: 'ابن، بنت أو قريب',
                      selected: _choice == _Choice.code,
                      onTap: () => _pick(_Choice.code),
                    ),
                    if (widget.onNurse != null) ...[
                      const SizedBox(height: F.s12),
                      _EntryCard(
                        itemKey: const ValueKey('entry-nurse'),
                        icon: Icons.medical_services_outlined,
                        title: 'أنا ممرض / مرافق',
                        hint: 'هتابع مريض وأساعده في أدويته',
                        selected: _choice == _Choice.nurse,
                        onTap: () => _pick(_Choice.nurse),
                      ),
                    ],
                    // قبل أي حساب: الصفحتين قدّامه من أول شاشة
                    const SizedBox(height: F.s12),
                    const LegalLinksRow(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s12),
                child: Column(
                  children: [
                    // الشريط ده في المخطط بيقول إن البيانات «متشفّرة». ما بنقولش
                    // ده: التشفير مش مبني، والجملة اللي تحت هي اللي بيحصل فعلاً.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s10),
                      decoration: BoxDecoration(
                        color: F.railGround,
                        borderRadius: BorderRadius.circular(F.radiusCard),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, size: 20, color: F.mutedDark),
                          SizedBox(width: F.s8),
                          Expanded(
                            child: Text(
                              'بياناتك بتفضل على الموبايل ده — ما بتروحش لحد غير لما تربطه بنفسك.',
                              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: F.s12),
                    FPrimaryButton(
                      key: const ValueKey('entry-start'),
                      label: 'يلا نبدأ',
                      onPressed: _choice == null ? null : _start,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.itemKey,
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        key: itemKey,
        // المختار بيتعلّم بحد أخضر وعلامة — الأخضر معناه «ده اللي اخترته»
        color: selected ? F.greenTint : F.cardGround,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(F.radiusCard),
          side: BorderSide(color: selected ? F.green : F.line, width: selected ? 2 : 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radiusCard),
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s14),
            child: Row(
              children: [
                Icon(icon, size: 30, color: selected ? F.green : F.mutedDark),
                const SizedBox(width: F.s14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: F.subtitleSize, fontWeight: FontWeight.w700, color: F.ink, height: 1.3)),
                      const SizedBox(height: F.s4),
                      Text(hint, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 28, color: F.green)
                else
                  const SizedBox(width: 28),
              ],
            ),
          ),
        ),
      );
}
