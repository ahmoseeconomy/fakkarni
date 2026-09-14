import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// جهة اتصال للطوارئ — اللي اتكتب بالإيد، بالحرف.
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone, this.relation});

  final String name;
  final String phone;

  /// «ابني»، «بنتي»، «دكتوري» … null لو ما اتكتبتش.
  final String? relation;

  Map<String, Object?> toJson() => {'name': name, 'phone': phone, 'relation': relation};

  static EmergencyContact? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'], phone = json['phone'], relation = json['relation'];
    if (name is! String || phone is! String) return null;
    return EmergencyContact(name: name, phone: phone, relation: relation is String ? relation : null);
  }

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact && other.name == name && other.phone == phone && other.relation == relation;

  @override
  int get hashCode => Object.hash(name, phone, relation);
}

/// بيانات الطوارئ كقيمة. **null = «لسه ما اتملاش»** — مفيش قيمة افتراضية
/// لأي حقل، ومفيش تخمين.
class EmergencyInfo {
  const EmergencyInfo({this.bloodType, this.allergies, this.chronicConditions, this.contacts = const []});

  final String? bloodType;
  final String? allergies;
  final String? chronicConditions;
  final List<EmergencyContact> contacts;

  static const empty = EmergencyInfo();

  static EmergencyInfo fromRow(EmergencyProfileRow? row) {
    if (row == null) return empty;
    List<EmergencyContact> contacts = const [];
    try {
      final decoded = jsonDecode(row.contactsJson);
      if (decoded is List) {
        contacts = [for (final c in decoded) ?EmergencyContact.fromJson(c)];
      }
    } on FormatException {
      // صف بايظ ما يوقّعش شاشة طوارئ — بتبان «لسه ما اتملاش»
    }
    return EmergencyInfo(
      bloodType: row.bloodType,
      allergies: row.allergies,
      chronicConditions: row.chronicConditions,
      contacts: contacts,
    );
  }
}

/// فصايل الدم اللي بتتختار — «مش عارف» مش هنا: هي null.
const bloodTypes = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

/// «الطوارئ» (D3.4) — صف واحد لكل مريض، محلي. SyncService ما بيقراهوش.
class EmergencyRepository {
  EmergencyRepository(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$EmergencyProfileTable, EmergencyProfileRow> _row(int patientId) =>
      _db.select(_db.emergencyProfile)..where((t) => t.patientId.equals(patientId));

  Stream<EmergencyInfo> watch(int patientId) =>
      _row(patientId).watchSingleOrNull().map(EmergencyInfo.fromRow);

  Future<EmergencyInfo> get(int patientId) async =>
      EmergencyInfo.fromRow(await _row(patientId).getSingleOrNull());

  /// بيحفظ اللي اتكتب بالظبط. نص فاضي أو مسافات = null (ما اتملاش) — مش
  /// «لا يوجد»: «مفيش حساسية» لازم حد يكتبها بإيده.
  Future<void> save(int patientId, EmergencyInfo info) {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final contacts = [
      for (final c in info.contacts)
        if (c.name.trim().isNotEmpty && c.phone.trim().isNotEmpty)
          EmergencyContact(name: c.name.trim(), phone: c.phone.trim(), relation: clean(c.relation)),
    ];
    final blood = clean(info.bloodType);
    if (blood != null && !bloodTypes.contains(blood)) {
      throw ArgumentError.value(blood, 'bloodType', 'مش فصيلة دم');
    }
    final companion = EmergencyProfileCompanion(
      patientId: Value(patientId),
      bloodType: Value(blood),
      allergies: Value(clean(info.allergies)),
      chronicConditions: Value(clean(info.chronicConditions)),
      contactsJson: Value(jsonEncode([for (final c in contacts) c.toJson()])),
    );
    return _db.into(_db.emergencyProfile).insert(
          companion,
          onConflict: DoUpdate((_) => companion, target: [_db.emergencyProfile.patientId]),
        );
  }
}
