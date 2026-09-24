/// المتجر (App Store / Google Play) من وراء واجهة — الـSDK في
/// `iap_store_purchases.dart` وبس، والاختبارات بتحط فيك.
library;

class StoreProduct {
  const StoreProduct({required this.id, required this.title, required this.price});

  final String id;
  final String title;

  /// **من المتجر بالحرف** بعملته — عمره ما يتكتب في الكود.
  final String price;
}

class StorePurchase {
  const StorePurchase({required this.store, required this.productId, required this.receipt});

  /// `apple` أو `google`.
  final String store;
  final String productId;

  /// Apple: transactionId — Google: purchaseToken. بيروح للـEdge Function.
  final String receipt;
}

abstract interface class StorePurchases {
  /// المنتجات اللي المتجر عارفها — فاضية لو المنتجات لسه ما اتعملتش (B7).
  Future<List<StoreProduct>> products(Set<String> ids);

  /// null = المستخدم لغى.
  Future<StorePurchase?> buy(StoreProduct product);

  /// المشتريات اللي المتجر بيرجّعها للحساب ده.
  Future<List<StorePurchase>> restore();
}
