import 'package:drift/drift.dart';

import '../../domain/escalation/alert_mode.dart';
import '../../domain/escalation/escalation_ladder.dart';
import '../db/app_database.dart';

/// تفضيلات الجهاز كقيمة — من غير صف في القاعدة بترجع الافتراضي.
class DeviceSettings {
  const DeviceSettings({
    this.elderMode = false,
    this.rungFirstOn = true,
    this.rungSecondOn = true,
    this.alertMode = AlertMode.standard,
  });

  final bool elderMode;
  final bool rungFirstOn;
  final bool rungSecondOn;

  /// نوع التنبيه الافتراضي — الدوا اللي مالوش نوع بياخده.
  final AlertMode alertMode;

  /// الدرجات المحلية اللي تتجدول. التذكير نفسه وإشعار الابن مش هنا —
  /// مالهمش مفتاح.
  Set<EscalationRung> get enabledRungs => {
        if (rungFirstOn) EscalationRung.first,
        if (rungSecondOn) EscalationRung.second,
      };

  bool isOn(EscalationRung rung) => switch (rung) {
        EscalationRung.first => rungFirstOn,
        EscalationRung.second => rungSecondOn,
      };

  static DeviceSettings fromRow(DevicePreferencesRow? row) => row == null
      ? const DeviceSettings()
      : DeviceSettings(
          elderMode: row.elderMode,
          rungFirstOn: row.rungFirstOn,
          rungSecondOn: row.rungSecondOn,
          alertMode: AlertMode.fromStorage(row.alertMode) ?? AlertMode.standard,
        );
}

/// «نمط كبار السن» و«التنبيهات» (D3.3) — صف واحد محلي، مش بيتزامن.
class PreferencesRepository {
  PreferencesRepository(this._db);

  final AppDatabase _db;

  static const _rowId = 1;

  SimpleSelectStatement<$DevicePreferencesTable, DevicePreferencesRow> get _row =>
      _db.select(_db.devicePreferences)..where((t) => t.id.equals(_rowId));

  Future<DeviceSettings> get() async => DeviceSettings.fromRow(await _row.getSingleOrNull());

  Stream<DeviceSettings> watch() => _row.watchSingleOrNull().map(DeviceSettings.fromRow);

  Future<void> setElderMode(bool on) => _write(DevicePreferencesCompanion(elderMode: Value(on)));

  /// درجة +١٥ أو +٣٠. الاستدعاء بعده لازم يعيد الجدولة — الشاشة بتعمل ده.
  Future<void> setRung(EscalationRung rung, bool on) => _write(switch (rung) {
        EscalationRung.first => DevicePreferencesCompanion(rungFirstOn: Value(on)),
        EscalationRung.second => DevicePreferencesCompanion(rungSecondOn: Value(on)),
      });

  /// نوع التنبيه الافتراضي. الاستدعاء بعده لازم يعيد الجدولة — الشاشة بتعمل ده.
  /// «صيدليتي» — اسم ورقم واتساب (v26). على الموبايل ده بس.
  Future<({String? name, String? whatsapp, String? call})> pharmacy() async {
    final row = await _row.getSingleOrNull();
    return (name: row?.pharmacyName, whatsapp: row?.pharmacyWhatsapp, call: row?.pharmacyCall);
  }

  /// [call] (v31): رقم الاتصال. `absent` = ما يتلمسش (اللي كان بينده الدالة
  /// بالاسم والواتساب بس لسه شغّال).
  Future<void> setPharmacy({required String? name, required String? whatsapp, String? call, bool clearCall = false}) async {
    await _write(DevicePreferencesCompanion(
      pharmacyName: Value(_blank(name)),
      pharmacyWhatsapp: Value(_blank(whatsapp)),
      pharmacyCall: clearCall ? const Value(null) : (call == null ? const Value.absent() : Value(_blank(call))),
    ));
    // «صيدليتي» بتركب صف المريض في السحابة (0035) — الصف بيتوسّخ عشان
    // الدفعة الجاية تاخده. تريجر الساعة هو اللي بيحرّك updated_at_ms.
    await _db.customStatement('UPDATE patients SET name = name');
  }

  /// **مرة واحدة** بعد v31: رقم الاتصال كان في `shared_preferences`
  /// (`pharmacy.call`) جولة واحدة — بيتنقل للعمود ويتمسح من هناك.
  static const legacyCallKey = 'pharmacy.call';

  Future<void> migrateLegacyPharmacyCall(Future<String?> Function() readLegacy, Future<void> Function() clearLegacy) async {
    try {
      final legacy = await readLegacy();
      if (legacy == null || legacy.trim().isEmpty) return;
      final current = await pharmacy();
      if (current.call == null) {
        await _write(DevicePreferencesCompanion(pharmacyCall: Value(legacy.trim())));
        await _db.customStatement('UPDATE patients SET name = name');
      }
      await clearLegacy();
    } catch (_) {}
  }

  static String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  Future<void> setAlertMode(AlertMode mode) =>
      _write(DevicePreferencesCompanion(alertMode: Value(mode.storageName)));

  Future<void> _write(DevicePreferencesCompanion change) =>
      _db.into(_db.devicePreferences).insert(
            change.copyWith(id: const Value(_rowId)),
            onConflict: DoUpdate((_) => change),
          );
}
