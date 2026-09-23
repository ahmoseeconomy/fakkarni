import 'package:flutter/material.dart';

import '../../format/relative_time.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';

/// رأس كل شاشة: العنوان وتحته سطر، وفي النهاية «آخر تحديث» و«حدّث».
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.screen,
    required this.now,
    required this.refreshing,
    required this.onRefresh,
    this.updatedAt,
    super.key,
  });

  final AdminScreen screen;
  final DateTime now;
  final DateTime? updatedAt;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: F.s12,
      runSpacing: F.s8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              screen.title,
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.screenTitleSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: F.s4),
            Text(
              screen.subtitle,
              style: TextStyle(
                fontFamily: F.bodyFamily,
                fontSize: F.careTextSize,
                color: F.mutedDark,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (updatedAt != null)
              Text(
                'آخر تحديث ${timeSince(now, updatedAt!)}',
                style: TextStyle(
                  fontFamily: F.bodyFamily,
                  fontSize: F.careMicroSize,
                  color: F.mutedDark,
                ),
              ),
            AdminTextAction(
              label: 'حدّث',
              icon: Icons.refresh_rounded,
              busy: refreshing,
              onPressed: onRefresh,
            ),
          ],
        ),
      ],
    );
  }
}
