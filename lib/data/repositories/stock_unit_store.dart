import 'package:shared_preferences/shared_preferences.dart';

/// وحدة المخزون اللي الشخص **اختارها** لدوا جرعته ما بتقولش هو إيه
/// («قرص» / «كبسولة» / …) — على الموبايل ده بس (قرار المالك، ٢٩ سبتمبر
/// ٢٠٢٦: مفيش عمود). ما بتتكتبش في جرعة الدوا: «قرص» هناك معناها «قرص في
/// الجرعة» وده رقم ما حدش قاله. العيلة والممرض بيشوفوا الوحدة من الجرعة.
class StockUnitStore {
  const StockUnitStore._();

  static const prefix = 'stock.unit.';

  static Future<String?> read(int medicationId) async {
    try {
      return (await SharedPreferences.getInstance()).getString('$prefix$medicationId');
    } catch (_) {
      return null;
    }
  }

  /// كل اللي اتختار — `medicationId → الوحدة`.
  static Future<Map<int, String>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <int, String>{};
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(prefix)) continue;
        final id = int.tryParse(k.substring(prefix.length));
        final unit = prefs.getString(k);
        if (id != null && unit != null) out[id] = unit;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> write(int medicationId, String unit) async {
    try {
      await (await SharedPreferences.getInstance()).setString('$prefix$medicationId', unit);
    } catch (_) {}
  }
}
