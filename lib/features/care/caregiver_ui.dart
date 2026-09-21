import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'caregiver_status.dart';

/// **الوِحدات المشتركة لتدرّج الابن — كثافة أعلى، نفس الهوية.**
///
/// نفس اللوحة ونفس الخطوط ونفس الـRTL بتوع الأب؛ اللي بيتغيّر المقاسات
/// والحشو بس، وكلها من `F.care…` (شوف `tokens.dart`). **ولا واحدة من
/// الودجتات دي بتتستعمل في شاشة مريض** — اختبار بيقرا `lib/` ويقفل على ده.

/// شريط علوي بمقاس الابن.
AppBar careAppBar(String title, {List<Widget> actions = const []}) => AppBar(
      titleSpacing: F.carePad,
      toolbarHeight: 52,
      title: Text(
        title,
        style: TextStyle(
          fontFamily: F.displayFamily,
          fontSize: F.careTitleSize,
          fontWeight: FontWeight.w700,
          color: F.ink,
        ),
      ),
      actions: actions,
    );

/// عنوان قسم — أصغر وأهدى من `FSectionHead` بتاع الأب، وبعدّاد اختياري.
class CareHead extends StatelessWidget {
  const CareHead(this.text, {this.count, this.accent, super.key});

  final String text;
  final int? count;

  /// لون القسم — **علامة صغيرة قبل الكلمة، مش لون الكلمة**. النص بياخد
  /// لون نص دايماً؛ اللون على العلامة عشان يفضل مقروء في الوضعين.
  final Color? accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: F.careRowGap, bottom: F.s6),
        child: Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: F.s6),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: F.careHeadSize,
                fontWeight: FontWeight.w700,
                color: F.mutedDark,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: F.s6),
              Text(
                '(${_ar(count!)})',
                style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark),
              ),
            ],
          ],
        ),
      );
}

String _ar(int v) {
  const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return v.toString().split('').map((c) => digits[int.parse(c)]).join();
}

/// كارت الابن — حشو أقل ونصف قطر أصغر من `FCard`.
class CareCard extends StatelessWidget {
  const CareCard({
    required this.child,
    this.edge,
    this.padding,
    this.border,
    super.key,
  });

  final Widget child;

  /// حد الكارت — لون قسمه، أو `F.line` لو مفيش قسم.
  final Color? border;

  /// حد جانبي ملوّن — للتنبيه. اللون **مش** الحامل الوحيد للمعنى؛ جنبه
  /// دايماً أيقونة وكلمة.
  final Color? edge;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding ?? const EdgeInsets.all(F.carePad),
      child: child,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: F.careRowGap),
      decoration: BoxDecoration(
        color: F.cardGround,
        borderRadius: BorderRadius.circular(F.careRadius),
        // **الحد بلون القسم، والأرضية زي ما هي.** تلوين الأرضية كان
        // هيحط نص على سطح جديد في كل قسم، ويحتاج فحص تباين لكل واحد؛
        // الحد بيدّي نفس الفصل البصري من غير ما يلمس قراية الكلام.
        border: Border.all(color: border ?? F.line, width: border == null ? 1 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: edge == null
          ? body
          // الحد شريط حقيقي على أول الكارت (نفس فكرة `GoldNote`) — مش
          // `BorderDirectional` جوّه `BoxDecoration` بنصف قطر، لأن فلاتر
          // بيرفض نصف قطر على حد مش متساوي الأضلاع.
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: edge),
                  Expanded(child: body),
                ],
              ),
            ),
    );
  }
}

/// لوحة هادية — رسالة، أو حالة فاضية.
class CarePanel extends StatelessWidget {
  const CarePanel({required this.text, this.action, this.onAction, super.key});

  final String text;

  /// فعل عملي جنب الرسالة (زي «حاول تاني») — مش قدرة جديدة، إعادة سؤال بس.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: F.careRowGap),
        padding: const EdgeInsets.all(F.carePad),
        decoration: BoxDecoration(
          color: F.railGround,
          borderRadius: BorderRadius.circular(F.careRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.5),
              ),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(width: F.s8),
              CareTextAction(label: action!, onPressed: onAction!),
            ],
          ],
        ),
      );
}

/// فعل نصي بهدف لمس بمقاس الابن — **الكلمة موجودة دايماً**، مش أيقونة لوحدها.
class CareTextAction extends StatelessWidget {
  const CareTextAction({required this.label, required this.onPressed, this.icon, super.key});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(F.careRadius),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: F.careTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: F.s10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: F.green),
                const SizedBox(width: F.s6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: F.careTextSize,
                  fontWeight: FontWeight.w700,
                  color: F.green,
                ),
              ),
            ],
          ),
        ),
      );
}

/// **الحالة بأيقونة وكلمة — واللون على العلامة، مش على النص.**
///
/// قاعدتين مع بعض:
///  * **مش لون لوحده.** صف بيتفرق بلونه بس بيضيع على حد مش بيفرّق
///    الألوان. الأيقونة والكلمة بيكفّوا، واللون تأكيد تالت.
///  * **والنص بياخد لون نص.** الذهبي على كارت نهاري **٢٫٠٦:١** — يعني
///    «اتنست — لسه ما اتأكدتش» كان أصعب سطر يتقرا على الشاشة، وهو أهم
///    سطر فيها. دلوقتي الكلمة بلون المتن، والذهبي على الأيقونة وعلى حد
///    الكارت — الاتنين علامة مش نص، والتباين بتاعهم مش شرط قراية.
class CareStateMark extends StatelessWidget {
  const CareStateMark({required this.look, required this.label, super.key});

  final DoseLook look;
  final String label;

  static IconData iconFor(DoseLook look) => switch (look) {
        DoseLook.taken => Icons.check_circle_outline,
        DoseLook.skipped => Icons.remove_circle_outline,
        DoseLook.unconfirmed => Icons.error_outline,
        DoseLook.upcoming => Icons.schedule,
      };

  static Color colourFor(DoseLook look) => switch (look) {
        DoseLook.taken => F.green,
        DoseLook.unconfirmed => F.gold,
        DoseLook.skipped || DoseLook.upcoming => F.mutedDark,
      };

  @override
  Widget build(BuildContext context) {
    final colour = colourFor(look);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconFor(look), size: 16, color: colour),
        const SizedBox(width: F.s4),
        Text(
          label,
          style: TextStyle(
            fontSize: F.careTextSize,
            fontWeight: FontWeight.w700,
            color: F.ink,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
