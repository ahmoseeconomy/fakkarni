import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'brand_mark.dart';
import 'dark_mode_toggle.dart';

/// الشريط الجانبي على بداية السطر (يمين): العلامة، الأقسام بشاراتها،
/// وفي القاع الهوية والوضع الليلي و«خروج». تحت ١١٠٠ بكسل بيبقى سكة
/// أيقونات بعرض ٧٢ والكلمات تلميحات.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    required this.screen,
    required this.onSelect,
    required this.badges,
    required this.onSignOut,
    this.email,
    this.rail = false,
    super.key,
  });

  final AdminScreen screen;
  final ValueChanged<AdminScreen> onSelect;
  final Map<AdminScreen, int> badges;
  final VoidCallback onSignOut;
  final String? email;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final mail = email;
    return Material(
      color: brandGround,
      child: SafeArea(
        child: SizedBox(
          width: rail ? railWidth : sidebarWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: F.s16, horizontal: F.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(F.s8, F.s4, F.s8, F.s20),
                  child: Row(
                    mainAxisAlignment: rail ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      const BrandMark(size: 30),
                      if (!rail) ...[
                        const SizedBox(width: F.s10),
                        Expanded(
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
                      ],
                    ],
                  ),
                ),
                for (final s in AdminScreen.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: F.s4),
                    child: SidebarItem(
                      icon: s.icon,
                      label: s.label,
                      active: s == screen,
                      badge: badges[s],
                      badgeGold: s == AdminScreen.devices && (badges[s] ?? 0) > 0,
                      rail: rail,
                      onTap: () => onSelect(s),
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.only(top: F.s12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: sidebarDivider)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (mail != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(F.s8, F.s4, F.s8, F.s12),
                          child: Row(
                            mainAxisAlignment: rail ? MainAxisAlignment.center : MainAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 17,
                                backgroundColor: F.gold,
                                child: Text(
                                  mail.isEmpty ? '•' : mail.characters.first.toUpperCase(),
                                  style: const TextStyle(
                                    fontFamily: F.displayFamily,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: F.inkDeep,
                                  ),
                                ),
                              ),
                              if (!rail) ...[
                                const SizedBox(width: F.s10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mail,
                                        textDirection: TextDirection.ltr,
                                        textAlign: TextAlign.right,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: F.bodyFamily,
                                          fontSize: F.careMicroSize,
                                          color: F.onDarkMuted,
                                        ),
                                      ),
                                      const Text(
                                        'مالك — إدارة كاملة',
                                        style: TextStyle(
                                          fontFamily: F.bodyFamily,
                                          fontSize: F.careMicroSize,
                                          fontWeight: FontWeight.w600,
                                          color: F.goldText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      DarkModeToggle(sidebar: true, rail: rail),
                      const SizedBox(height: F.s4),
                      SidebarItem(
                        icon: Icons.logout_rounded,
                        label: 'خروج',
                        rail: rail,
                        onTap: onSignOut,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
