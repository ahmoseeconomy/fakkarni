import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';

/// «🔊 ساعدني» — زرار بكلمته، بيقول جملة الكتالوج [id] عن الكارت أو الشاشة
/// اللي هو عليها. **بيظهر بس لما الصوت شغّال**: زرار بيتداس وما يعملش
/// حاجة أسوأ من زرار مش موجود، والصوت المقفول له صفه في الإعدادات.
///
/// من غير `AppScope` (اختبار بيبني ويدجت لوحده) أو من غير خدمة صوت (مفيش
/// ملفات) = مفيش زرار.
class HelpButton extends StatelessWidget {
  const HelpButton(this.id, {this.elder = false, this.onDark = false, super.key});

  final String id;

  /// نمط كبار السن — أكبر: هدف ٦٤ وخط ٢٢.
  final bool elder;

  /// على أرضية غامقة (شاشة التصوير، بطاقة الطوارئ).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final voice = AppScope.maybeOf(context)?.voice;
    if (voice == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        if (!voice.enabled) return const SizedBox.shrink();
        final size = elder ? F.elderTextSize : F.minTextSize;
        final height = elder ? F.primaryButtonHeight : F.minTapTarget;
        final ink = onDark ? F.onDark : F.ink;
        return Semantics(
          button: true,
          label: 'ساعدني',
          child: Material(
            key: ValueKey('help-$id'),
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(F.radiusCard),
              side: BorderSide(color: onDark ? F.onDarkMuted : F.line, width: 1.5),
            ),
            child: InkWell(
              onTap: () => voice.speakLine(id),
              borderRadius: BorderRadius.circular(F.radiusCard),
              child: Container(
                constraints: BoxConstraints(minHeight: height, minWidth: height),
                padding: EdgeInsets.symmetric(horizontal: elder ? F.s14 : F.s10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up_outlined, size: elder ? 28 : 22, color: ink),
                    const SizedBox(width: F.s6),
                    Text('ساعدني', style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: ink)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// عنوان قسم وجنبه «ساعدني» — نفس شكل `FSectionHead`، للأماكن اللي العنوان
/// فيها هو الكارت.
class HelpRow extends StatelessWidget {
  const HelpRow({required this.child, required this.id, this.elder = false, super.key});

  final Widget child;
  final String id;
  final bool elder;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: child),
          const SizedBox(width: F.s8),
          HelpButton(id, elder: elder),
        ],
      );
}
