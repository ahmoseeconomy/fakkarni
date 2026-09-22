import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// أيقونة نوع الكارت (المخطط ٤): جرعة، قياس سكر، تقرير تحليل، مرحلة فحص.
/// مربّع هادي على يمين الكارت — بيقول نوعه من غير ما ياخد انتباه من الذهبي.
class CardTypeIcon extends StatelessWidget {
  const CardTypeIcon({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusTile)),
        child: Icon(icon, size: 22, color: F.green),
      );
}
