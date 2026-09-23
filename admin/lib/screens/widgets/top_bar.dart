import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'brand_mark.dart';
import 'dark_mode_toggle.dart';

/// الشريط العلوي على الأرضية الغامقة: العلامة والاسم، الإيميل، الوضع
/// الليلي، و«خروج». الإيميل بيختفي على الموبايل — الشريط ضيّق، والاسم
/// أهم منه.
class AdminTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminTopBar({required this.email, required this.onSignOut, super.key});

  final String? email;
  final VoidCallback onSignOut;

  static const double height = 60;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < phoneBreakpoint;
    return Material(
      color: brandGround,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: F.s12),
            child: Row(
              children: [
                const BrandMark(size: 30),
                const SizedBox(width: F.s10),
                Flexible(
                  child: Text(
                    'لوحة فكرني',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.careTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.onDark,
                    ),
                  ),
                ),
                const Spacer(),
                if (email != null && !narrow)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: F.s8),
                    child: Text(
                      email!,
                      style: const TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careMicroSize,
                        color: F.onDarkMuted,
                      ),
                    ),
                  ),
                const DarkModeToggle(),
                AdminTextAction(label: 'خروج', onDark: true, onPressed: onSignOut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
