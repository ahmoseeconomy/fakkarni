import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../format/arabic_time.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';

/// شريط الأربع أرقام. **محسوبين في السيرفر من نفس صفوف الجدول**، فالشريط
/// والجدول ما يقدروش يختلفوا.
class CountsStrip extends StatelessWidget {
  const CountsStrip(this.counts, {super.key});

  final AdminCounts counts;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, int)>[
      ('الحسابات', counts.totalPatients),
      ('المتابعين', counts.totalFollowers),
      ('نشط آخر ٧ أيام', counts.active7d),
      ('بطارية مقيّدة', counts.batteryRestricted),
    ];
    // على الموبايل اتنين في الصف بدل واحد — أربع كروت بعرض ١٩٠ على شاشة
    // ٣٩٠ بيبقوا عمود طوله شاشة كاملة قبل أول حساب في القايمة.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < phoneBreakpoint;
        final width = narrow ? (constraints.maxWidth - F.careRowGap) / 2 : 190.0;
        return Wrap(
          spacing: F.careRowGap,
          runSpacing: F.careRowGap,
          children: [
            for (final (label, value) in cells)
              SizedBox(
                width: width,
                child: AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        arabicNumber(value),
                        style: TextStyle(
                          fontFamily: F.displayFamily,
                          fontSize: narrow ? F.screenTitleSize : F.display3,
                          fontWeight: FontWeight.w700,
                          color: F.ink,
                        ),
                      ),
                      const SizedBox(height: F.s4),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: F.bodyFamily,
                          fontSize: F.careTextSize,
                          color: F.mutedDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
