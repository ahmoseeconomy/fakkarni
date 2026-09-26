/// الحد اليومي لسؤال السحابة عن طلب مسموع (المرحلة ٣) — واجهة؛ التنفيذ
/// والعدّ في `data/services/daily_cloud_budget.dart`.
abstract interface class CloudCommandBudget {
  /// لسه فيه من نصيب النهارده؟
  bool allowed();

  /// اتسألت مرة.
  void used();
}
