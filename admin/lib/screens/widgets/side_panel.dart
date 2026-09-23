import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/tokens.dart';

/// لوحة جانبية بتنزلق من **بداية** السطر — يمين في العربي — فوق ستارة.
/// الدوسة على الستارة بتقفلها. الإغلاق بيرجّع الحركة، والودجت بتفضل
/// موجودة لحد ما الحركة تخلص.
class SidePanelOverlay extends StatefulWidget {
  const SidePanelOverlay({
    required this.child,
    required this.onDismiss,
    this.panel,
    this.width = 380,
    super.key,
  });

  final Widget child;
  final Widget? panel;
  final VoidCallback onDismiss;
  final double width;

  @override
  State<SidePanelOverlay> createState() => _SidePanelOverlayState();
}

class _SidePanelOverlayState extends State<SidePanelOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );
  Widget? _shown;

  @override
  void initState() {
    super.initState();
    if (widget.panel != null) {
      _shown = widget.panel;
      _c.value = 1;
    }
  }

  @override
  void didUpdateWidget(SidePanelOverlay old) {
    super.didUpdateWidget(old);
    final panel = widget.panel;
    _c.duration = motionDuration(context, Motion.slow);
    if (panel != null) {
      _shown = panel;
      if (_c.status != AnimationStatus.completed) _c.forward();
    } else if (old.panel != null) {
      _c.reverse().whenComplete(() {
        if (mounted && widget.panel == null) setState(() => _shown = null);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final width = math.min(widget.width, MediaQuery.sizeOf(context).width * 0.92);
    final curved = CurvedAnimation(parent: _c, curve: Motion.curve);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (shown != null) ...[
          FadeTransition(
            opacity: curved,
            child: GestureDetector(
              onTap: widget.onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Container(color: F.scrim),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
                  .animate(curved),
              textDirection: Directionality.of(context),
              child: FadeTransition(
                opacity: curved,
                child: SizedBox(
                  width: width,
                  child: Material(
                    color: F.pageGround,
                    elevation: 12,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    child: shown,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
