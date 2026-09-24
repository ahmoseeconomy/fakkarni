import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../domain/billing/family_plan.dart';
import 'store_purchases.dart';
import 'subscription_remote.dart';

/// **حالة اشتراك العيلة على الموبايل ده** — والبوابة اللي الشاشات بتسأله.
///
/// - آخر حالة معروفة **محفوظة** (`billing.lastKnownAllowed`): لو التحقق
///   مش واصل بنمشي عليها (مهلة) — عمرنا ما نقفل بسبب شبكة.
/// - التذكير مش بيسأل هنا خالص؛ فيه حارس بيقرا المصدر.
/// - محاكاة للتطوير (`debugOverride`) **مش في نسخة المتجر** — الحقل نفسه
///   بيتجاهل تحت `kReleaseMode`.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService({required this.remote, this.store, this.clock = DateTime.now});

  final SubscriptionRemote remote;

  /// null = مفيش متجر على الجهاز ده (اختبارات، أو تنزيلة من غير متجر).
  final StorePurchases? store;
  final DateTime Function() clock;

  static const lastKnownKey = 'billing.lastKnownAllowed';
  static const exportsKey = 'billing.exports';
  static const debugKey = 'billing.debugOverride';

  /// المريض اللي الاشتراك عليه — الأب بيحطّه من صفّه، والابن من الصورة.
  String? patientUuid;

  FamilySubscription? current;
  bool? _lastKnownAllowed;
  int exportsUsed = 0;
  bool? _debugOverride;
  bool loaded = false;

  bool? get debugOverride => kReleaseMode ? null : _debugOverride;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastKnownAllowed = prefs.getBool(lastKnownKey);
      exportsUsed = prefs.getInt(exportsKey) ?? 0;
      final d = prefs.getString(debugKey);
      _debugOverride = d == null ? null : d == 'active';
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  /// بيسأل السحابة؛ الفشل بيسيب [current] زي ما هو والحالة المحفوظة بتمشي.
  Future<void> refresh() async {
    final uuid = patientUuid;
    if (uuid == null) return;
    try {
      current = await remote.load(uuid);
      final allowed = featureAllowed(AppFeature.circle, subscription: current, now: clock());
      _lastKnownAllowed = allowed;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(lastKnownKey, allowed);
      } catch (_) {}
    } catch (error) {
      diag('Billing: قراية الاشتراك وقعت ($error) — ماشيين على آخر حالة معروفة');
    }
    notifyListeners();
  }

  bool allowed(AppFeature feature, {DateTime? now}) {
    if (feature == AppFeature.exportBeyondFree && exportsUsed < freeExports) return true;
    return featureAllowed(
      feature,
      subscription: current,
      now: now ?? clock(),
      lastKnownAllowed: _lastKnownAllowed,
      debugOverride: debugOverride,
    );
  }

  Future<void> noteExport() async {
    exportsUsed++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(exportsKey, exportsUsed);
    } catch (_) {}
    notifyListeners();
  }

  /// محاكاة للتطوير: true نشط، false منتهي، null الحقيقة. مش في نسخة المتجر.
  Future<void> setDebugOverride(bool? value) async {
    if (kReleaseMode) return;
    _debugOverride = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(debugKey);
      } else {
        await prefs.setString(debugKey, value ? 'active' : 'expired');
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<List<StoreProduct>> products() async => store?.products(SubscriptionConfig.productIds) ?? const [];

  /// شراء ← تحقق على السيرفر ← تحديث. بيرجّع نتيجة التحقق (null = لغى).
  Future<VerifyOutcome?> buy(StoreProduct product) async {
    final uuid = patientUuid;
    final s = store;
    if (uuid == null || s == null) return VerifyOutcome.failed;
    final purchase = await s.buy(product);
    if (purchase == null) return null;
    return _verify(uuid, purchase);
  }

  Future<VerifyOutcome> restore() async {
    final uuid = patientUuid;
    final s = store;
    if (uuid == null || s == null) return VerifyOutcome.failed;
    final purchases = await s.restore();
    var outcome = VerifyOutcome.invalid;
    for (final p in purchases) {
      outcome = await _verify(uuid, p);
      if (outcome == VerifyOutcome.active) break;
    }
    return outcome;
  }

  Future<VerifyOutcome> _verify(String uuid, StorePurchase purchase) async {
    final outcome = await remote.verify(
      patientUuid: uuid,
      store: purchase.store,
      productId: purchase.productId,
      receipt: purchase.receipt,
    );
    diag('Billing: ${purchase.store}/${purchase.productId} → ${outcome.name}');
    if (outcome == VerifyOutcome.active) await refresh();
    return outcome;
  }
}
