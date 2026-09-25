import '../voice/help_button.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/billing/store_purchases.dart';
import '../../data/billing/subscription_remote.dart';
import '../../data/billing/subscription_service.dart';
import '../../domain/billing/family_plan.dart';

/// **«اشتراك العيلة»** — الشاشة الواحدة للدفع (تعليق المختبِر ٣).
///
/// بتقول: إيه المجاني للأبد، وإيه اللي الاشتراك بيغطّيه، ومين في الدائرة
/// متغطّي، وزرارين بأسعار **من المتجر**، و«استرجاع المشتريات»، وسطر
/// «تذكير الدوا مجاني للأبد» بالحرف. بتتفتح من الإعدادات ومن أي ميزة
/// عائلية اتقفلت.
class FamilyPlanScreen extends StatefulWidget {
  const FamilyPlanScreen({
    required this.service,
    required this.patientName,
    this.coveredNames = const [],
    this.now,
    super.key,
  });

  final SubscriptionService service;
  final String patientName;

  /// أسامي اللي بيتابعوا — من الدائرة، أو فاضية.
  final List<String> coveredNames;
  final DateTime? now;

  @override
  State<FamilyPlanScreen> createState() => _FamilyPlanScreenState();
}

class _FamilyPlanScreenState extends State<FamilyPlanScreen> {
  List<StoreProduct>? _products;
  String? _notice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final products = await widget.service.products();
    if (mounted) setState(() => _products = products);
    await widget.service.refresh();
  }

  Future<void> _buy(StoreProduct product) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final outcome = await widget.service.buy(product);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = switch (outcome) {
        null => null, // لغى — مفيش جملة
        VerifyOutcome.active => 'تمام — اشتراك العيلة شغّال.',
        VerifyOutcome.notConfigured => 'الشراء وصلنا، بس التحقق لسه مش متظبط عندنا — كل حاجة شغّالة لحد ما يتظبط.',
        VerifyOutcome.invalid => 'المتجر ما أكّدش الشراء. لو اتخصم منك، «استرجاع المشتريات» تحت.',
        VerifyOutcome.failed => 'مقدرناش نتأكد دلوقتي — كل حاجة شغّالة زي ما هي، وهنحاول تاني لوحدنا.',
      };
    });
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final outcome = await widget.service.restore();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = switch (outcome) {
        VerifyOutcome.active => 'رجع — اشتراك العيلة شغّال.',
        VerifyOutcome.notConfigured => 'التحقق لسه مش متظبط عندنا — كل حاجة شغّالة لحد ما يتظبط.',
        VerifyOutcome.invalid => 'مفيش اشتراك متسجّل على الحساب ده في المتجر.',
        VerifyOutcome.failed => 'مقدرناش نوصل للمتجر دلوقتي.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final now = widget.now ?? DateTime.now();
    final products = _products;
    final covered = [widget.patientName, ...widget.coveredNames];
    return Scaffold(
      appBar: AppBar(title: const Text('اشتراك العيلة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          const Align(alignment: AlignmentDirectional.centerEnd, child: HelpButton('help_family_plan')),
          GoldNote(
            remindersStayFreeLine,
            key: const ValueKey('plan-reminders-free'),
          ),
          const SizedBox(height: F.s12),
          Text(
            subscriptionStatusLine(service.current, now, arabicDate),
            key: const ValueKey('plan-status'),
            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
          ),
          const SizedBox(height: F.gap),
          const FSectionHead('اشتراك واحد للعيلة كلها'),
          const SizedBox(height: F.s6),
          Text(
            'بيغطّي صاحب الحساب ولحد ${arabicNumber(SubscriptionConfig.followerCap)} ناس بيتابعوه — أي حد فيهم يقدر يدفعه.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
          ),
          const SizedBox(height: F.s10),
          FCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('اللي بيغطّيهم', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark)),
                const SizedBox(height: F.s6),
                Text(
                  covered.join('، '),
                  key: const ValueKey('plan-covered'),
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: F.gap),
          const FSectionHead('مجاني للأبد'),
          const SizedBox(height: F.s6),
          for (final f in AppFeature.freeForever) _Line(f.label, Icons.check),
          const SizedBox(height: F.gap),
          const FSectionHead('اللي الاشتراك بيفتحه'),
          const SizedBox(height: F.s6),
          for (final f in AppFeature.familyOnly) _Line(f.label, Icons.family_restroom_outlined),
          const SizedBox(height: F.gap),
          if (products == null)
            Center(child: CircularProgressIndicator(color: F.green))
          else if (products.isEmpty)
            Text(
              'المتجر لسه ما فيهوش الاشتراك — هيظهر هنا بسعره أول ما يتفعّل.',
              key: const ValueKey('plan-no-products'),
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
            )
          else
            for (final p in products) ...[
              FPrimaryButton(
                key: ValueKey('plan-buy-${p.id}'),
                label: '${p.id == SubscriptionConfig.yearlyProductId ? 'سنوي' : 'شهري'} — ${p.price}',
                onPressed: _busy ? null : () => _buy(p),
              ),
              const SizedBox(height: F.s8),
            ],
          FSecondaryButton(
            key: const ValueKey('plan-restore'),
            label: 'استرجاع المشتريات',
            onPressed: _busy || service.store == null ? null : _restore,
          ),
          if (_notice case final n?) ...[
            const SizedBox(height: F.s10),
            Text(n, key: const ValueKey('plan-notice'), style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5)),
          ],
          // محاكاة للتطوير — **مش في نسخة المتجر**
          if (!kReleaseMode) ...[
            const SizedBox(height: F.gap),
            const FSectionHead('للمطوّر — محاكاة'),
            const SizedBox(height: F.s6),
            Row(
              children: [
                for (final (label, value) in const [('حقيقي', null), ('نشط', true), ('منتهي', false)]) ...[
                  Expanded(
                    child: AnchorChip(
                      key: ValueKey('plan-debug-${value == null ? 'real' : value ? 'active' : 'expired'}'),
                      label: label,
                      selected: service.debugOverride == value,
                      onTap: () => service.setDebugOverride(value),
                    ),
                  ),
                  if (value != false) const SizedBox(width: F.s8),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, this.icon);

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: F.green),
            const SizedBox(width: F.s8),
            Expanded(child: Text(text, style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5))),
          ],
        ),
      );
}
