import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'motion_widgets.dart';

/// تحت العرض ده الجدول بيتحوّل لكروت.
///
/// المدير ممكن يفتح اللوحة من موبايله، وجدول بعشرة أعمدة على ٣٩٠ بكسل
/// بيبقى تمرير أفقي مش بصة سريعة. السطح العريض زي ما هو.
const double phoneBreakpoint = 700;

/// الأرضية الغامقة بتاعة الشريط العلوي وشاشة الدخول: أخضر غامق بالنهار،
/// وفحمي مخضرّ بالليل. الدهبي هو هو في الحالتين.
Color get brandGround => F.isDark ? F.inkDeep : F.greenDeep;

/// كارت العلامة (الدخول) عاجي بالنهار — الاسم بتاعه في التوكنز — وكارت
/// عادي بالليل.
Color get loginCardGround => F.isDark ? F.cardGround : F.ivory;

/// كارت اللوحة. بيترفع شوية تحت الماوس لو فيه فعل عليه، وبياخد حد جانبي
/// ملوّن لو [edge] اتحدّد — «محتاج نظرة» بيتقال بالحد، مش بأرضية ملوّنة.
class AdminCard extends StatefulWidget {
  const AdminCard({
    required this.child,
    this.edge,
    this.padding,
    this.onTap,
    super.key,
  });

  final Widget child;
  final Color? edge;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  State<AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<AdminCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final lifted = interactive && _hover;
    final body = Padding(
      padding: widget.padding ?? const EdgeInsets.all(F.carePad),
      child: widget.child,
    );
    final edge = widget.edge;
    final card = AnimatedContainer(
      duration: motionDuration(context, Motion.quick),
      curve: Motion.curve,
      transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(
          color: edge ?? (lifted ? F.green.withValues(alpha: 0.5) : F.line),
          width: edge == null ? 1 : 1.5,
        ),
        borderRadius: BorderRadius.circular(F.careRadius),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: F.isDark ? 0.4 : 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      clipBehavior: Clip.antiAlias,
      child: edge == null
          ? body
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Container(width: 4, color: edge), Expanded(child: body)],
              ),
            ),
    );
    if (!interactive) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}

class AdminHead extends StatelessWidget {
  const AdminHead(this.text, {this.count, super.key});

  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: F.displayFamily,
      fontSize: F.careTitleSize,
      fontWeight: FontWeight.w700,
      color: F.ink,
    );
    return Text(text, style: style);
  }
}

/// زرار نص — **الكلمة موجودة دايماً**، مفيش أيقونة لوحدها. الأيقونة بتلفّ
/// وهو [busy]، عشان «حدّث» يقول إنه بيجيب من غير جملة زيادة.
class AdminTextAction extends StatelessWidget {
  const AdminTextAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.onDark = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// على الشريط الأخضر الغامق النص أبيض، مش أخضر.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final colour = onDark ? F.onDark : F.green;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, F.careTapTarget),
        foregroundColor: colour,
        padding: const EdgeInsets.symmetric(horizontal: F.s12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            SpinWhile(spinning: busy, child: Icon(icon, size: 18)),
            const SizedBox(width: F.s6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontFamily: F.bodyFamily,
              fontSize: F.careBodySize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// لوحة رسالة — خطأ، أو «مفيش حاجة هنا».
class AdminPanel extends StatelessWidget {
  const AdminPanel({required this.text, this.action, this.onAction, super.key});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = action;
    final tap = onAction;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(F.carePad),
      decoration: BoxDecoration(
        color: F.railGround,
        borderRadius: BorderRadius.circular(F.careRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: F.bodyFamily,
              fontSize: F.careBodySize,
              color: F.mutedDark,
            ),
          ),
          if (label != null && tap != null)
            AdminTextAction(label: label, onPressed: tap),
        ],
      ),
    );
  }
}
