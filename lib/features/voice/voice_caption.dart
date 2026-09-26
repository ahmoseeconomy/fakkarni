import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';

/// **الترجمة المكتوبة**: أي حاجة الرفيق بيقولها بتظهر نص تحت الشاشة، فوق
/// كل حاجة (في جذر التطبيق). بتختفي أول ما الكلام يخلص أو يتقطع.
/// «اسكت» بيوقّف الكلام — كلمة، مش أيقونة لوحدها.
class VoiceCaptionOverlay extends StatelessWidget {
  const VoiceCaptionOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final voice = AppScope.maybeOf(context)?.voice;
    if (voice == null) return child;
    return Stack(
      children: [
        child,
        Positioned(
          left: F.gap,
          right: F.gap,
          bottom: F.gap + MediaQuery.paddingOf(context).bottom,
          child: ListenableBuilder(
            // ورقة بتكتب الجملة بنفسها = الكارت ده بيسكت، عشان الجملة تتكتب مرة
            listenable: Listenable.merge([voice.caption, voice.captionHolds]),
            builder: (context, _) {
              final text = voice.caption.value;
              if (text == null || voice.captionHolds.value > 0) return const SizedBox.shrink();
              return Material(
                key: const ValueKey('voice-caption'),
                color: F.dialogGround,
                elevation: 6,
                borderRadius: BorderRadius.circular(F.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(F.s14, F.s12, F.s14, F.s8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.record_voice_over_outlined, size: 22, color: F.green),
                          const SizedBox(width: F.s8),
                          Expanded(
                            child: Text(
                              text,
                              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          key: const ValueKey('voice-caption-stop'),
                          onPressed: voice.stop,
                          style: TextButton.styleFrom(
                            foregroundColor: F.ink,
                            minimumSize: const Size(F.minTapTarget, F.minTapTarget),
                            textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
                          ),
                          child: const Text('اسكت'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
