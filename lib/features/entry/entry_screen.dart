import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/fa_mark.dart';

/// «مين ماسك التليفون؟» (D4، بأسلوب كروت المخطط ٢) — أول شاشة في تنزيلة
/// جديدة.
///
/// **سؤال مش تسجيل دخول**: مفيش جلسة ولا نداء دخول هنا (حارس `root_test`).
/// كل كارت هو الفعل نفسه — مفيش «اختار وبعدين يلا نبدأ» زي المخطط، خطوة
/// واحدة أسهل على إيد عندها ٧٢ سنة. الشاشة **بتوجّه وبس**: الاختيار مش
/// متخزّن (مفيش عمود دور — ٣.٣). بتختفي للأبد أول ما يبقى فيه مريض محلي أو
/// علاقة رعاية، والجذر هو اللي بيقرر ده من البيانات.
class EntryScreen extends StatelessWidget {
  const EntryScreen({
    required this.onSelf,
    required this.onForSomeoneElse,
    required this.onHaveCode,
    super.key,
  });

  /// «التليفون ده ليا» → نتعرّف عليك → ظبّط يومك → يومك.
  final VoidCallback onSelf;

  /// «بظبّط لحد تاني» → نفس الشاشات بالغايب.
  final VoidCallback onForSomeoneElse;

  /// «ابني أو والدي بعتلي كود» → الدخول → الكود → المتابعة.
  final VoidCallback onHaveCode;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s30, F.gap, F.gap),
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: F.greenDeep, borderRadius: BorderRadius.circular(F.radiusTile)),
                  alignment: Alignment.center,
                  child: const FaMark(size: 46),
                ),
              ),
              const SizedBox(height: F.gap),
              const Text(
                'أهلاً في فكّرني',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
              const SizedBox(height: F.s6),
              const Text(
                'مين ماسك التليفون ده؟',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
              ),
              const SizedBox(height: F.s22),
              _EntryCard(
                key: const ValueKey('entry-self'),
                icon: Icons.person_outline,
                title: 'التليفون ده ليا',
                hint: 'أنا اللي باخد الدوا',
                onTap: onSelf,
              ),
              const SizedBox(height: F.s12),
              _EntryCard(
                key: const ValueKey('entry-other'),
                icon: Icons.people_outline,
                title: 'بظبّط لحد تاني',
                hint: 'والدي أو والدتي — وهو اللي هيمسك التليفون',
                onTap: onForSomeoneElse,
              ),
              const SizedBox(height: F.s12),
              _EntryCard(
                key: const ValueKey('entry-code'),
                icon: Icons.link,
                title: 'ابني أو والدي بعتلي كود',
                hint: 'عايز أتابع أدويته من تليفوني',
                onTap: onHaveCode,
              ),
              const SizedBox(height: F.s22),
              const Text(
                'أول اختيارين من غير حساب، وكل حاجة بتفضل على الموبايل ده.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
              ),
            ],
          ),
        ),
      );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.icon, required this.title, required this.hint, required this.onTap, super.key});

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

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
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: F.ivoryWarm, borderRadius: BorderRadius.circular(F.radiusTile)),
                  child: Icon(icon, size: 28, color: F.ink),
                ),
                const SizedBox(width: F.s14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontSize: F.questionSize, fontWeight: FontWeight.w700, color: F.ink, height: 1.3)),
                      const SizedBox(height: F.s4),
                      Text(hint, style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left, size: 28, color: F.muted),
              ],
            ),
          ),
        ),
      );
}
