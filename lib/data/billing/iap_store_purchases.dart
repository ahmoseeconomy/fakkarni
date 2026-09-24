import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/diagnostics.dart';
import 'store_purchases.dart';

/// `in_app_purchase` — **الاستيراد الوحيد في التطبيق**.
class IapStorePurchases implements StorePurchases {
  IapStorePurchases([InAppPurchase? plugin]) : _iap = plugin ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  static const purchaseTimeout = Duration(minutes: 3);

  String get _store => Platform.isIOS ? 'apple' : 'google';

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    try {
      if (!await _iap.isAvailable()) return const [];
      final res = await _iap.queryProductDetails(ids);
      if (res.notFoundIDs.isNotEmpty) diag('Billing: منتجات مش موجودة في المتجر: ${res.notFoundIDs}');
      return [
        for (final p in res.productDetails) StoreProduct(id: p.id, title: p.title, price: p.price),
      ];
    } catch (error) {
      diag('Billing: قراية المنتجات وقعت ($error)');
      return const [];
    }
  }

  @override
  Future<StorePurchase?> buy(StoreProduct product) async {
    final res = await _iap.queryProductDetails({product.id});
    final details = res.productDetails.firstOrNull;
    if (details == null) return null;
    final done = Completer<StorePurchase?>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        if (p.productID != product.id) continue;
        switch (p.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
            if (!done.isCompleted) done.complete(_toPurchase(p));
          case PurchaseStatus.error:
            diag('Billing: الشراء وقع (${p.error?.code}: ${p.error?.message})');
            if (!done.isCompleted) done.complete(null);
          case PurchaseStatus.canceled:
            if (!done.isCompleted) done.complete(null);
          case PurchaseStatus.pending:
            break;
        }
      }
    });
    try {
      final started = await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: details));
      if (!started) return null;
      return await done.future.timeout(purchaseTimeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<List<StorePurchase>> restore() async {
    final found = <StorePurchase>[];
    late final StreamSubscription<List<PurchaseDetails>> sub;
    final settled = Completer<void>();
    sub = _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        if (p.status == PurchaseStatus.restored || p.status == PurchaseStatus.purchased) {
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          found.add(_toPurchase(p));
        }
      }
      if (!settled.isCompleted) settled.complete();
    });
    try {
      await _iap.restorePurchases();
      await settled.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    } catch (error) {
      diag('Billing: الاسترجاع وقع ($error)');
    } finally {
      await sub.cancel();
    }
    return found;
  }

  StorePurchase _toPurchase(PurchaseDetails p) => StorePurchase(
        store: _store,
        productId: p.productID,
        // Apple: transactionId (للـApp Store Server API) — Google: purchaseToken
        receipt: Platform.isIOS ? (p.purchaseID ?? p.verificationData.serverVerificationData) : p.verificationData.serverVerificationData,
      );
}
