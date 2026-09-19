import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// الحالة الفاضية: بهدوء، وبتقول إزاي تضيف.
class RecordsEmpty extends StatelessWidget {
  const RecordsEmpty({required this.how, this.title = 'لسه مفيش حاجة هنا', super.key});

  final String title;
  final String how;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
            const SizedBox(height: F.s4),
            Text(how, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
          ],
        ),
      );
}
