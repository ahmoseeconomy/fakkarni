import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'motion_widgets.dart';

/// هيكل اللوحة وهي بتجيب أول مرة — مكان الكروت والصفوف، بنفس مقاساتهم،
/// عشان الشاشة ما تنطّش لما الداتا توصل.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({required this.narrow, super.key});

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final width = narrow ? (c.maxWidth - F.careRowGap) / 2 : 210.0;
            return Wrap(
              spacing: F.careRowGap,
              runSpacing: F.careRowGap,
              children: [
                for (var i = 0; i < 4; i++)
                  SizedBox(
                    width: width,
                    // نفس ارتفاع الكارت الحقيقي في الوضعين، عشان الشاشة ما تنطّش.
                    child: narrow
                        ? const AdminCard(
                            padding: EdgeInsets.all(F.s10),
                            child: Row(
                              children: [
                                Shimmer(width: 30, height: 30, radius: 15),
                                SizedBox(width: F.s8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Shimmer(width: 56, height: 22),
                                    SizedBox(height: F.s4),
                                    Shimmer(width: 80, height: 12),
                                  ],
                                ),
                              ],
                            ),
                          )
                        : const AdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Shimmer(width: 34, height: 34, radius: 17),
                                SizedBox(height: F.s10),
                                Shimmer(width: 72, height: 30),
                                SizedBox(height: F.s6),
                                Shimmer(width: 110, height: 14),
                              ],
                            ),
                          ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: F.s16),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: F.careRowGap),
            child: AdminCard(
              child: Row(
                children: [
                  const Shimmer(width: 140, height: 16),
                  const SizedBox(width: F.s12),
                  const Shimmer(width: 90, height: 22, radius: 999),
                  const Spacer(),
                  if (!narrow) const Shimmer(width: 220, height: 14),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
