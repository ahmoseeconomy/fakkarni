import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'motion_widgets.dart';

/// تحت العرض ده مفيش شريط جانبي: الشريط العلوي + تنقّل تحت، والجدول كروت.
const double phoneBreakpoint = 700;

/// من هنا لفوق الشريط الجانبي كامل (٢٤٠)؛ بينه وبين [phoneBreakpoint] سكة
/// أيقونات (٧٢).
const double sidebarBreakpoint = 1100;

// ---- توكنز اللوحة وبس — مش في `tokens.dart` المشترك (نسخة التطبيق).
const double sidebarWidth = 240;
const double railWidth = 72;
const double drawerWidth = 460;
const double contentMaxWidth = 1440;
const double navItemHeight = 44;
const double rowHeight = 52;
const int pageSize = 25;

Color get sidebarHover => Colors.white.withValues(alpha: 0.08);
Color get sidebarActive => Colors.white.withValues(alpha: 0.10);
Color get sidebarBadge => Colors.white.withValues(alpha: 0.12);
Color get sidebarDivider => Colors.white.withValues(alpha: 0.12);

/// أقسام اللوحة. **تلاتة بس النهارده**: سجل التنبيهات والمشرفين محتاجين
/// دوال سيرفر مش موجودة (`0022` المقترحة) — وتبويب بيفتح على فاضي أوحش
/// من تبويب مش موجود.
enum AdminScreen {
  overview('نظرة عامة', 'المنتج شغّال ولا لأ — نبضة كل موبايل، والتنبيهات اللي اتبعتت.',
      Icons.space_dashboard_rounded),
  accounts('الحسابات', 'كل مريض وآخر نبضة من موبايله. دوس على صف عشان تفتحه.',
      Icons.people_alt_rounded),
  devices('صحة الأجهزة', 'البطارية، مدى التذكير، ونسخ التطبيق.', Icons.smartphone_rounded);

  const AdminScreen(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;

  /// اسم التبويب في الشريط — أقصر من عنوان الشاشة.
  String get label => switch (this) {
        AdminScreen.overview => 'نظرة عامة',
        AdminScreen.accounts => 'الحسابات',
        AdminScreen.devices => 'الأجهزة',
      };
}

/// الأرضية الغامقة بتاعة الشريط الجانبي ورأس اللوحة وشاشة الدخول: أخضر
/// غامق بالنهار، وفحمي مخضرّ بالليل. الدهبي هو هو في الحالتين.
Color get brandGround => F.isDark ? F.inkDeep : F.greenDeep;

/// كارت العلامة (الدخول) عاجي بالنهار — الاسم بتاعه في التوكنز — وكارت
/// عادي بالليل.
Color get loginCardGround => F.isDark ? F.cardGround : F.ivory;

/// كارت اللوحة. بيترفع شوية تحت الماوس لو فيه فعل عليه، وبياخد حد جانبي
/// ملوّن لو [edge] اتحدّد — «محتاج نظرة» بيتقال بالحد، مش بأرضية ملوّنة.
class AdminCard extends StatefulWidget {
  const AdminCard({
    required this.child,
    this.edge,
    this.border,
    this.padding,
    this.onTap,
    this.hoverTint = false,
    super.key,
  });

  final Widget child;
  final Color? edge;

  /// حد كامل بلون (١٫٥ بكسل) — بلاطات الفرز.
  final Color? border;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// تحت الماوس: تظليل أخضر بدل الرفع (الصفوف والبلاطات).
  final bool hoverTint;

  @override
  State<AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<AdminCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final hovered = interactive && _hover;
    final lifted = hovered && !widget.hoverTint;
    final body = Padding(
      padding: widget.padding ?? const EdgeInsets.all(F.carePad),
      child: widget.child,
    );
    final edge = widget.edge;
    final card = AnimatedContainer(
      duration: motionDuration(context, Motion.quick),
      curve: Motion.curve,
      transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: hovered && widget.hoverTint ? F.greenTint : F.cardGround,
        border: Border.all(
          color: widget.border ??
              edge ??
              (lifted ? F.green.withValues(alpha: 0.5) : F.line),
          width: widget.border != null || edge != null ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(F.careRadius),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: F.isDark ? 0.4 : 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      clipBehavior: Clip.antiAlias,
      child: edge == null
          ? body
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Container(width: 4, color: edge), Expanded(child: body)],
              ),
            ),
    );
    if (!interactive) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}

class AdminHead extends StatelessWidget {
  const AdminHead(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: TextStyle(
        fontFamily: F.displayFamily,
        fontSize: F.careTitleSize,
        fontWeight: FontWeight.w700,
        color: F.ink,
      ),
    );
    if (trailing == null) return title;
    // الذيل `Flexible` عشان سطر طويل (أو خط مكبّر) يلفّ بدل ما يطلع برّه
    // الصف — العنوان بياخد نصّه على الأقل.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        const SizedBox(width: F.s8),
        Flexible(child: DefaultTextStyle.merge(textAlign: TextAlign.end, child: trailing!)),
      ],
    );
  }
}

/// زرار نص — **الكلمة موجودة دايماً**، مفيش أيقونة لوحدها. الأيقونة بتلفّ
/// وهو [busy]، عشان «حدّث» يقول إنه بيجيب من غير جملة زيادة.
class AdminTextAction extends StatelessWidget {
  const AdminTextAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.onDark = false,
    this.size = F.careBodySize,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// على الشريط الأخضر الغامق النص أبيض، مش أخضر.
  final bool onDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = onDark ? F.onDark : F.green;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: colour,
        padding: const EdgeInsets.symmetric(horizontal: F.s12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.s10)),
      ),
      // الكلمة `Flexible` بقطع في الآخر: زرار في مكان ضيّق يقصّر بدل ما
      // يطلع برّه الصف — الصف مش بيلفّ، والنص بيقدر.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            SpinWhile(spinning: busy, child: Icon(icon, size: 18)),
            const SizedBox(width: F.s6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: F.bodyFamily,
                fontSize: size,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// لوحة رسالة — خطأ، أو «مفيش حاجة هنا».
class AdminPanel extends StatelessWidget {
  const AdminPanel({required this.text, this.action, this.onAction, super.key});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = action;
    final tap = onAction;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(F.carePad),
      decoration: BoxDecoration(
        color: F.railGround,
        borderRadius: BorderRadius.circular(F.careRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: F.bodyFamily,
              fontSize: F.careBodySize,
              color: F.mutedDark,
            ),
          ),
          if (label != null && tap != null)
            AdminTextAction(label: label, onPressed: tap),
        ],
      ),
    );
  }
}

/// لافتة خطأ **فوق** البيانات القديمة، مش بدالها: الأرقام اللي تحت ممكن
/// تكون قديمة، بس قديمة أحسن من فاضية.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(F.s16),
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(color: F.outOfRangeInk, width: 1.5),
        borderRadius: BorderRadius.circular(F.careRadius),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: F.s12,
        runSpacing: F.s8,
        children: [
          Icon(Icons.cloud_off_rounded, size: 22, color: F.outOfRangeInk),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('مش قادرين نوصل للسحابة.',
                  style: TextStyle(
                      fontFamily: F.bodyFamily,
                      fontSize: F.careBodySize,
                      fontWeight: FontWeight.w700,
                      color: F.ink)),
              Text('الأرقام اللي تحت ممكن تكون قديمة. اتأكد من النت وجرّب تاني.',
                  style: TextStyle(
                      fontFamily: F.bodyFamily,
                      fontSize: F.careTextSize,
                      color: F.mutedDark)),
            ],
          ),
          AdminTextAction(label: 'حاول تاني', onPressed: onRetry),
        ],
      ),
    );
  }
}

/// زرار ثانوي: أرضية حقل وحد، والحد بيخضرّ تحت الماوس.
class AdminOutlineButton extends StatefulWidget {
  const AdminOutlineButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.height = 38,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  final double height;

  @override
  State<AdminOutlineButton> createState() => _AdminOutlineButtonState();
}

class _AdminOutlineButtonState extends State<AdminOutlineButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: motionDuration(context, Motion.quick),
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: F.s12),
          decoration: BoxDecoration(
            color: widget.selected ? F.greenTint : F.fieldGround,
            border: Border.all(color: active ? F.green : F.line),
            borderRadius: BorderRadius.circular(F.s10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: F.green),
                const SizedBox(width: F.s6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: F.bodyFamily,
                  fontSize: F.careTextSize,
                  fontWeight: FontWeight.w600,
                  color: F.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
