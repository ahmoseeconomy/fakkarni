import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// شيت سفلي: نصف قطر ٢٦ فوق، حجاب `rgba(11,42,51,.55)`، بيطلع في ٢٨٠ ms،
/// والدوسة برّه بتقفله. كل خيار جوّاه زرار ٥٦+ بكلمة.
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
    return Container(
      decoration: const BoxDecoration(
        color: F.ivory,
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
                style: const TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.subtitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
              const SizedBox(height: F.s14),
              for (final child in children) ...[
                child,
                const SizedBox(height: F.s10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
