import 'package:drift/drift.dart';

import '../../domain/escalation/escalation_ladder.dart';
import '../db/app_database.dart';

/// تفضيلات الجهاز كقيمة — من غير صف في القاعدة بترجع الافتراضي.
class DeviceSettings {
  const DeviceSettings({
    this.elderMode = false,
    this.rungFirstOn = true,
    this.rungSecondOn = true,
  });

  final bool elderMode;
  final bool rungFirstOn;
  final bool rungSecondOn;

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

  Future<void> _write(DevicePreferencesCompanion change) =>
      _db.into(_db.devicePreferences).insert(
            change.copyWith(id: const Value(_rowId)),
            onConflict: DoUpdate((_) => change),
          );
}
