import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// شيت سفلي: نصف قطر ٢٦ فوق، حجاب `rgba(11,42,51,.55)`، بيطلع في ٢٨٠ ms،
/// والدوسة برّه بتقفله. كل خيار جوّاه زرار ٥٦+ بكلمة.
///
/// **والكيبورد بيزقّه لفوق، مش بيغطّيه.** أي شيت فيه حقل كتابة (تعديل
/// الدكتور أو العيادة في شاشة المراجعة مثلاً) كان بيتبني على ارتفاعه
/// الطبيعي والكيبورد بيطلع فوقه: الحقل و«احفظ» بيبقوا تحته، فالراجل
/// بيكتب وهو مش شايف، وما بيوصلش لزرار الحفظ أصلاً. الإصلاح في مكان
/// واحد هنا عشان يشمل كل شيت: حشوة بقد `viewInsets.bottom` تحت، والجسم
/// جوّه `SingleChildScrollView` بـ`Flexible` — فلو الشاشة قصيرة
/// والكيبورد طالع، المحتوى بيتزحلق بدل ما يتقص.
class FSheet extends StatelessWidget {
  const FSheet({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        barrierColor: F.scrim,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        sheetAnimationStyle: const AnimationStyle(
          duration: F.sheetDuration,
          reverseDuration: F.sheetDuration,
          curve: Curves.easeOut,
        ),
        builder: (_) => FSheet(title: title, children: children),
      );

  @override
  Widget build(BuildContext context) {
    // الكيبورد. `viewInsetsOf` بيرجّع الجديد مع كل إطار وهو بيطلع، فالشيت
    // بيتحرّك معاه بدل ما يقفز في الآخر.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        decoration: BoxDecoration(
          color: F.pageGround,
          borderRadius: BorderRadius.vertical(top: Radius.circular(F.radiusSheet)),
          boxShadow: F.shadowSheet,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s12, F.gap, F.gap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: F.line,
                      borderRadius: BorderRadius.circular(F.radiusChip),
                    ),
                  ),
                ),
                const SizedBox(height: F.s14),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.subtitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                const SizedBox(height: F.s14),
                // **الجسم هو اللي بيتزحلق، مش الترويسة.** المقبض والعنوان
                // بيفضلوا ثابتين عشان الشيت يفضل معروف إنه شيت.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final child in children) ...[
                          child,
                          const SizedBox(height: F.s10),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
