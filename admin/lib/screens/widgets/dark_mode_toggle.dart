import 'package:flutter/material.dart';

import '../../theme/theme_mode_store.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';

/// زرار الوضع الليلي — أيقونة **وكلمة**، والكلمة بتقول هيعمل إيه لما تدوس
/// («ليلي» وإنت في النهار). في الشريط الجانبي بياخد شكل عنصر تنقّل؛ في
/// الشريط العلوي (الموبايل) زرار نص. المنطق واحد.
class DarkModeToggle extends StatelessWidget {
  const DarkModeToggle({this.sidebar = false, this.rail = false, super.key});

  static const toggleKey = Key('dark-mode-toggle');

  final bool sidebar;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.maybeOf(context);
    final dark = F.isDark;
    final icon = dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded;
    final word = dark ? 'نهاري' : 'ليلي';
    if (sidebar) {
      return SidebarItem(
        key: toggleKey,
        icon: icon,
        label: word,
        rail: rail,
        onTap: controller == null ? null : () => controller.toggle(),
      );
    }
    return TextButton.icon(
      key: toggleKey,
      onPressed: controller == null ? null : () => controller.toggle(),
      style: TextButton.styleFrom(
        foregroundColor: F.onDark,
        minimumSize: const Size(0, F.careTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: F.s12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        word,
        style: const TextStyle(
          fontFamily: F.bodyFamily,
          fontSize: F.careTextSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// عنصر في الشريط الجانبي: أيقونة + كلمة (+ شارة). النشط بأرضية بيضا خفيفة
/// وعلامة دهبية على طرف البداية. في السكة الضيّقة الكلمة بتبقى تلميحة.
class SidebarItem extends StatefulWidget {
  const SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge,
    this.badgeGold = false,
    this.rail = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final int? badge;
  final bool badgeGold;
  final bool rail;

  @override
  State<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ink = widget.active ? F.onDark : F.onDarkMuted;
    final badge = widget.badge;
    final content = Row(
      mainAxisAlignment: widget.rail ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(widget.icon, size: 20, color: ink),
        if (!widget.rail) ...[
          const SizedBox(width: F.s10),
          Expanded(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: F.bodyFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          if (badge != null && badge > 0) _Badge(badge, gold: widget.badgeGold),
        ],
      ],
    );
    Widget item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          children: [
            Container(
              height: navItemHeight,
              padding: const EdgeInsets.symmetric(horizontal: F.s12),
              decoration: BoxDecoration(
                color: widget.active ? sidebarActive : (_hover ? sidebarHover : Colors.transparent),
                borderRadius: BorderRadius.circular(F.careRadius),
              ),
              child: content,
            ),
            if (widget.active)
              PositionedDirectional(
                start: -F.s12,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 3,
                  decoration: const BoxDecoration(
                    color: F.gold,
                    borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(3)),
                  ),
                ),
              ),
            if (widget.rail && badge != null && badge > 0)
              PositionedDirectional(
                end: 12,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.badgeGold ? F.gold : F.onDarkMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.rail) item = Tooltip(message: widget.label, child: item);
    return item;
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.count, {required this.gold});

  final int count;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: gold ? F.gold : sidebarBadge,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _short(count),
        style: TextStyle(
          fontFamily: F.bodyFamily,
          fontSize: F.careMicroSize,
          fontWeight: FontWeight.w700,
          color: gold ? F.inkDeep : F.onDarkMuted,
          height: 1.2,
        ),
      ),
    );
  }

  static String _short(int n) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final s = n.toString().split('').map((c) => digits[int.parse(c)]).join();
    if (n < 1000) return s;
    return '${s.substring(0, s.length - 3)}٬${s.substring(s.length - 3)}';
  }
}
