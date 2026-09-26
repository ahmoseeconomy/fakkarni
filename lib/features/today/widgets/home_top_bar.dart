import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/dark_mode_toggle.dart';
import '../../../core/widgets/fa_mark.dart';
import '../../emergency/emergency_pill.dart';

/// الشريط العلوي — العلامة، مفتاح الوضع الليلي، و«طوارئ» — **على «يومك» بس،
/// وجزء من الصفحة** (المالك، ٢٦ سبتمبر ٢٠٢٦): بيتزحلق ويطلع مع المحتوى، مش
/// مثبّت، من غير خط ولا ظل، وبنفس أرضية الصفحة. باقي التبويبات من غيره.
/// كان `AppBar` على هيكل التطبيق كله من ١٤ سبتمبر.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: kToolbarHeight,
        child: Row(
          children: [
            // علامة ف على بلاطة خضرا عشان العاجي يبان
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: F.greenDeep,
                borderRadius: BorderRadius.circular(F.radiusTile),
              ),
              alignment: Alignment.center,
              child: const FaMark(size: 24, breathing: true),
            ),
            const Spacer(),
            // مكان الشخص بقى مفتاح الوضع الليلي
            const DarkModeToggle(),
            const EmergencyPill(),
          ],
        ),
      );
}
