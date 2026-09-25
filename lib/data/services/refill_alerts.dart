import '../../core/diagnostics.dart';
import '../../core/notifications/notification_service.dart';
import '../../domain/medication/stock.dart';
import '../repositories/stock_repository.dart';
import 'reminder_plan.dart';

/// اللي بيعرض الإشعار — الحقيقي `NotificationService.showRefill`، وفيك
/// في الاختبار.
abstract interface class RefillNotifier {
  Future<void> show(int id, String title, String body);
}

class DeviceRefillNotifier implements RefillNotifier {
  const DeviceRefillNotifier();

  @override
  Future<void> show(int id, String title, String body) =>
      NotificationService.showRefill(id: id, title: title, body: body);
}

/// **«قرب يخلص» — تنبيه لما يعدّي الحد أول مرة، وبعدها كل ٣ أيام وهو لسه
/// قرب يخلص.** سكّة لوحدها زي المواعيد: ما بتعرفش حاجة عن الجرعات ولا
/// السلّم ولا التصعيد، وبتتنده **بعد** الجدولة في `try/catch` بتاعها.
///
/// - **معروض لما التطبيق يصحى** (الفتح، الرجوع للمقدمة، تأكيد جرعة) مش
///   متجدول: خانات iOS كلها محجوزة لتذكير الدوا، وده ما ينفعش يدفع تمنه.
///   المريض اللي بيأكّد جرعاته بيصحّي التطبيق كل يوم، فالتكرار بيوصل.
/// - **مش بالليل**: بين ٩ الصبح و٩ بالليل بس — التنبيه ده مش مستعجل زي
///   الجرعة، ويستنى الصحوة الجاية.
class RefillAlerts {
  RefillAlerts({required this.stock, required this.patientId, this.notifier = const DeviceRefillNotifier()});

  final StockRepository stock;
  final int patientId;
  final RefillNotifier notifier;

  static const quietBefore = 9;
  static const quietFrom = 21;

  /// بترجّع عدد التنبيهات اللي اتعرضت.
  Future<int> sync({required DateTime now}) async {
    var shown = 0;
    try {
      for (final view in await stock.all(patientId)) {
        final row = await stock.rowFor(view.medicationId);
        if (row == null) continue;
        if (!view.isLow) {
          // اشترى — الدورة بتبدأ من الأول المرة الجاية
          if (row.notifiedAt != null) await stock.markNotified(view.medicationId, null);
          continue;
        }
        if (now.hour < quietBefore || now.hour >= quietFrom) continue;
        final last = row.notifiedAt;
        if (last != null && now.difference(last) < refillRepeatEvery) continue;
        await notifier.show(
          refillIdFor(view.medicationId),
          stockLowLine(view.name, stock: view.quantity, daysLeft: view.daysLeft ?? 0),
          'لو اشتريت علبة جديدة سجّلها، أو اطلبه من الصيدلية.',
        );
        await stock.markNotified(view.medicationId, now);
        shown++;
      }
    } catch (error) {
      diag('Refill: تنبيه «قرب يخلص» وقع — التذكيرات مش متأثرة ($error)');
    }
    return shown;
  }
}
