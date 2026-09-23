import 'package:flutter/material.dart';

import '../../format/arabic_time.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'status_cues.dart';

/// بلاطة فرز: حالة واحدة، كلمتها وشرحها وعددها. الدوسة بتفتح الحسابات
/// مفلترة عليها. الحد بلون الحالة — والشكل والكلمة موجودين دايماً.
class TriageTile extends StatelessWidget {
  const TriageTile({required this.tone, required this.count, required this.onTap, super.key});

  final RowTone tone;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = toneColour(tone);
    return AdminCard(
      onTap: onTap,
      hoverTint: true,
      border: colour,
      padding: const EdgeInsets.symmetric(horizontal: F.s16, vertical: F.s14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colour.withValues(alpha: F.isDark ? 0.2 : 0.13),
            ),
            child: Icon(toneIcon(tone), size: 22, color: colour),
          ),
          const SizedBox(width: F.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  toneWord(tone),
                  style: TextStyle(
                    fontFamily: F.bodyFamily,
                    fontSize: F.careBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                Text(
                  toneDescription(tone),
                  style: TextStyle(
                    fontFamily: F.bodyFamily,
                    fontSize: F.careTextSize,
                    color: F.mutedDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: F.s14),
          Text(
            arabicNumber(count),
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.screenTitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          Icon(Icons.chevron_left_rounded, size: 20, color: F.muted),
        ],
      ),
    );
  }
}
