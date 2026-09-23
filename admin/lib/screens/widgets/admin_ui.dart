import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// عناصر اللوحة المشتركة — كارت وعنوان قسم وزرار نص، بكثافة شاشة الابن
/// (`F.care…`): اللي بيفتح اللوحة دي شغّال وبيبص بسرعة، مش راجل عنده ٧٢ سنة.

class AdminCard extends StatelessWidget {
  const AdminCard({required this.child, this.edge, this.padding, super.key});

  final Widget child;
  final Color? edge;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding ?? const EdgeInsets.all(F.carePad),
      child: child,
    );
    return Container(
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(color: edge ?? F.line, width: edge == null ? 1 : 1.5),
        borderRadius: BorderRadius.circular(F.careRadius),
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
  }
}

class AdminHead extends StatelessWidget {
  const AdminHead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: F.displayFamily,
          fontSize: F.careTitleSize,
          fontWeight: FontWeight.w700,
        ).copyWith(color: F.ink),
      );
}

/// زرار نص — **الكلمة موجودة دايماً**، مفيش أيقونة لوحدها.
class AdminTextAction extends StatelessWidget {
  const AdminTextAction({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, F.careTapTarget),
        foregroundColor: F.green,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: F.s6)],
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
