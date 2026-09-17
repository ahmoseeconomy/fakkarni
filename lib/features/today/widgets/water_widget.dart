import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';

/// ودجت المية (المخطط 4): حلقة بعدّاد بيقل كل ثانية، الكوبايات ٠–٨،
/// و«كل كام ساعة» ١/٢/٣.
///
/// تخزين محلي بسيط (shared_preferences) — مش جدول، ومش بيتزامن. **مفيش
/// إشعار ولا نصيحة**: الفترة اختيار المستخدم، والحد ٨ هو حد العدّاد مش
/// توصية (القاعدة ٦). الحلقة خضرا وهي بتعدّ، وذهبي لما الوقت يخلص —
/// «ده محتاج انتباهك دلوقتي».
///
/// المؤقّت الوحيد هنا بيتلغي في dispose، وما بيشتغلش أصلاً قبل أول كوباية
/// (مفيش حاجة بتعدّ). المؤقّت التاني بتاع التصميم (كشف سطور الروشتة) عايش في
/// شاشة التصوير وبيقف مع `mounted`.
class WaterWidget extends StatefulWidget {
  const WaterWidget({this.now, super.key});

  /// للاختبارات — ساعة ثابتة.
  final DateTime Function()? now;

  static const int maxCups = 8;
  static const _kCups = 'water.cups';
  static const _kDay = 'water.day';
  static const _kEvery = 'water.everyHours';
  static const _kLast = 'water.lastCupMs';

  @override
  State<WaterWidget> createState() => _WaterWidgetState();
}

class _WaterWidgetState extends State<WaterWidget> {
  SharedPreferences? _prefs;
  int _cups = 0;
  int _every = 2;
  DateTime? _lastCup;
  Timer? _tick;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  static String _dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final today = _dayKey(_now);
      final sameDay = prefs.getString(WaterWidget._kDay) == today;
      final lastMs = prefs.getInt(WaterWidget._kLast);
      setState(() {
        _prefs = prefs;
        _every = prefs.getInt(WaterWidget._kEvery) ?? 2;
        // يوم جديد = عدّاد جديد
        _cups = sameDay ? (prefs.getInt(WaterWidget._kCups) ?? 0) : 0;
        _lastCup = sameDay && lastMs != null ? DateTime.fromMillisecondsSinceEpoch(lastMs) : null;
      });
      _syncTimer();
    } catch (_) {
      // من غير التخزين (اختبار من غير mock) الودجت شغّال في الذاكرة بس
    }
  }

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(WaterWidget._kDay, _dayKey(_now));
    await prefs.setInt(WaterWidget._kCups, _cups);
    await prefs.setInt(WaterWidget._kEvery, _every);
    if (_lastCup != null) {
      await prefs.setInt(WaterWidget._kLast, _lastCup!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(WaterWidget._kLast);
    }
  }

  /// المؤقّت بيشتغل بس لما فيه حاجة بتعدّ — وبيتلغي أول ما مفيش.
  void _syncTimer() {
    if (_lastCup == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }

  void _addCup(int delta) {
    final next = (_cups + delta).clamp(0, WaterWidget.maxCups);
    if (next == _cups) return;
    setState(() {
      _cups = next;
      if (delta > 0) _lastCup = _now;
      if (_cups == 0) _lastCup = null;
    });
    _syncTimer();
    _save();
  }

  void _setEvery(int hours) {
    setState(() => _every = hours);
    _save();
  }

  Duration get _remaining {
    final last = _lastCup;
    if (last == null) return Duration.zero;
    final left = last.add(Duration(hours: _every)).difference(_now);
    return left.isNegative ? Duration.zero : left;
  }

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int v) => arabicDigits(v.toString().padLeft(2, '0'));
    return h > 0 ? '${arabicNumber(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final total = Duration(hours: _every);
    final started = _lastCup != null;
    final due = started && remaining == Duration.zero;
    final progress = started ? remaining.inSeconds / total.inSeconds : 0.0;

    return Container(
      // المية بلون المية — أزرق **محجوز ليها وبس** في التوكنز
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: F.waterGround,
        borderRadius: BorderRadius.circular(F.radiusLarge),
        border: Border.all(color: F.waterDrop.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Stack(
        children: [
          const PositionedDirectional(top: 0, end: 0, child: _FlashingDrop()),
          Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 96,
                child: CustomPaint(
                  painter: _Ring(progress: progress, colour: due ? F.gold : F.green),
                  child: Center(
                    child: Text(
                      started ? _clock(remaining) : '—',
                      key: const ValueKey('water-countdown'),
                      style: TextStyle(
                        fontSize: F.minTextSize,
                        fontWeight: FontWeight.w700,
                        color: due ? F.ink : F.greenDeep,
                        fontFamily: F.monoFamily,
                        fontFamilyFallback: F.monoFallback,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: F.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المية',
                      style: TextStyle(fontSize: F.sectionHeadSize, fontWeight: FontWeight.w700, color: F.ink),
                    ),
                    Text(
                      '${arabicNumber(_cups)} من ${arabicNumber(WaterWidget.maxCups)} كوبايات النهارده',
                      key: const ValueKey('water-cups'),
                      style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                    ),
                    Text(
                      !started
                          ? 'العدّاد بيبدأ مع أول كوباية'
                          : due
                              ? 'جه وقت كوباية'
                              : 'الكوباية الجاية',
                      style: TextStyle(
                        fontSize: F.minTextSize,
                        fontWeight: due ? FontWeight.w700 : FontWeight.w400,
                        color: due ? F.ink : F.mutedDark,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s12),
          Row(
            children: [
              Expanded(
                child: FSecondaryButton(label: '− كوباية', onPressed: _cups == 0 ? null : () => _addCup(-1)),
              ),
              const SizedBox(width: F.s10),
              Expanded(
                child: FSecondaryButton(
                  label: '+ كوباية',
                  onPressed: _cups >= WaterWidget.maxCups ? null : () => _addCup(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s12),
          // «كل» مرة واحدة فوق — «كل ساعتين» جوّه شريحة من تلاتة كانت بتلف وتتقص
          Text(
            'كوباية كل:',
            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
          ),
          const SizedBox(height: F.s6),
          Row(
            children: [
              for (final h in [1, 2, 3]) ...[
                Expanded(
                  child: AnchorChip(
                    label: switch (h) { 1 => 'ساعة', 2 => 'ساعتين', _ => '٣ ساعات' },
                    selected: _every == h,
                    onTap: () => _setEvery(h),
                  ),
                ),
                if (h != 3) const SizedBox(width: F.s8),
              ],
            ],
          ),
            ],
          ),
        ],
      ),
    );
  }
}

/// نقطة مية بتلمع في ركن الكارت — بتنوّر وتكبر وحواليها هالة، على طول.
///
/// دي **أنيميشن دائم**، وده بيخلي `pumpAndSettle` ما تنتهيش أبداً لأنها
/// بتفضل مستنية إطار جديد. علشان كده `settle` في الاختبارات بقت ضخّ محدود
/// بعدد إطارات، مش `pumpAndSettle` — الشاشة اللي فيها حاجة بتتحرك على طول
/// ما ينفعش تتسنّى. التحرّك بيقف لوحده تحت «تقليل الحركة».
class _FlashingDrop extends StatefulWidget {
  const _FlashingDrop();

  @override
  State<_FlashingDrop> createState() => _FlashingDropState();
}

class _FlashingDropState extends State<_FlashingDrop> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _flash.repeat(reverse: true);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Icon(Icons.water_drop, size: 26, color: F.waterDrop);
    }
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_flash.value);
        return Container(
          padding: const EdgeInsets.all(F.s6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: F.waterDrop.withValues(alpha: 0.35 * t), blurRadius: 14 + 10 * t),
            ],
          ),
          child: Opacity(
            opacity: 0.45 + 0.55 * t,
            child: Transform.scale(scale: 0.88 + 0.24 * t, child: child),
          ),
        );
      },
      child: Icon(Icons.water_drop, size: 26, color: F.waterDrop),
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring({required this.progress, required this.colour});

  final double progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = F.lineSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final arc = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final inner = rect.deflate(6);
    canvas.drawArc(inner, 0, math.pi * 2, false, track);
    if (progress > 0) {
      canvas.drawArc(inner, -math.pi / 2, math.pi * 2 * progress, false, arc);
    } else if (colour == F.gold) {
      canvas.drawArc(inner, 0, math.pi * 2, false, arc);
    }
  }

  @override
  bool shouldRepaint(_Ring old) => old.progress != progress || old.colour != colour;
}
