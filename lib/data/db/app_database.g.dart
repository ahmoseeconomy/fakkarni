// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PatientsTable extends Patients
    with TableInfo<$PatientsTable, PatientRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PatientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncUuid,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: nowMs,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notificationSlotMeta = const VerificationMeta(
    'notificationSlot',
  );
  @override
  late final GeneratedColumn<int> notificationSlot = GeneratedColumn<int>(
    'notification_slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    name,
    notificationSlot,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'patients';
  @override
  VerificationContext validateIntegrity(
    Insertable<PatientRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('notification_slot')) {
      context.handle(
        _notificationSlotMeta,
        notificationSlot.isAcceptableOrUnknown(
          data['notification_slot']!,
          _notificationSlotMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {notificationSlot},
  ];
  @override
  PatientRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PatientRow(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      notificationSlot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notification_slot'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PatientsTable createAlias(String alias) {
    return $PatientsTable(attachedDatabase, alias);
  }
}

class PatientRow extends DataClass implements Insertable<PatientRow> {
  final String uuid;

  /// بتتصان من قاعدة البيانات نفسها (تريجرات في beforeOpen) — مش من نقاط
  /// النداء: اللي لازم حد يفتكره هيتنسي، والصف ده كان هيبطل يتزامن في صمت.
  final int updatedAtMs;

  /// آخر updated_at_ms اتدفع للسحابة — null يعني عمره ما اتدفع.
  final int? syncedAtMs;
  final int id;
  final String name;

  /// خانة المريض في نطاق أرقام الإشعارات (0 → maxPatients-1).
  ///
  /// **مش هي `id`.** الـ`id` بيعدّ لفوق على طول وعمره ما بيرجع، فبعد ١٢٨
  /// صف بيخرج برّه النطاق. الخانة دي بتترد لما المريض يتشال، وبتفضل
  /// صغيرة وثابتة طول عمر المريض.
  final int notificationSlot;
  final DateTime createdAt;
  const PatientRow({
    required this.uuid,
    required this.updatedAtMs,
    this.syncedAtMs,
    required this.id,
    required this.name,
    required this.notificationSlot,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['notification_slot'] = Variable<int>(notificationSlot);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PatientsCompanion toCompanion(bool nullToAbsent) {
    return PatientsCompanion(
      uuid: Value(uuid),
      updatedAtMs: Value(updatedAtMs),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
      id: Value(id),
      name: Value(name),
      notificationSlot: Value(notificationSlot),
      createdAt: Value(createdAt),
    );
  }

  factory PatientRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PatientRow(
      uuid: serializer.fromJson<String>(json['uuid']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      notificationSlot: serializer.fromJson<int>(json['notificationSlot']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'notificationSlot': serializer.toJson<int>(notificationSlot),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PatientRow copyWith({
    String? uuid,
    int? updatedAtMs,
    Value<int?> syncedAtMs = const Value.absent(),
    int? id,
    String? name,
    int? notificationSlot,
    DateTime? createdAt,
  }) => PatientRow(
    uuid: uuid ?? this.uuid,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
    id: id ?? this.id,
    name: name ?? this.name,
    notificationSlot: notificationSlot ?? this.notificationSlot,
    createdAt: createdAt ?? this.createdAt,
  );
  PatientRow copyWithCompanion(PatientsCompanion data) {
    return PatientRow(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      notificationSlot: data.notificationSlot.present
          ? data.notificationSlot.value
          : this.notificationSlot,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PatientRow(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('notificationSlot: $notificationSlot, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    name,
    notificationSlot,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatientRow &&
          other.uuid == this.uuid &&
          other.updatedAtMs == this.updatedAtMs &&
          other.syncedAtMs == this.syncedAtMs &&
          other.id == this.id &&
          other.name == this.name &&
          other.notificationSlot == this.notificationSlot &&
          other.createdAt == this.createdAt);
}

class PatientsCompanion extends UpdateCompanion<PatientRow> {
  final Value<String> uuid;
  final Value<int> updatedAtMs;
  final Value<int?> syncedAtMs;
  final Value<int> id;
  final Value<String> name;
  final Value<int> notificationSlot;
  final Value<DateTime> createdAt;
  const PatientsCompanion({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.notificationSlot = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PatientsCompanion.insert({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    required String name,
    this.notificationSlot = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<PatientRow> custom({
    Expression<String>? uuid,
    Expression<int>? updatedAtMs,
    Expression<int>? syncedAtMs,
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? notificationSlot,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (notificationSlot != null) 'notification_slot': notificationSlot,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PatientsCompanion copyWith({
    Value<String>? uuid,
    Value<int>? updatedAtMs,
    Value<int?>? syncedAtMs,
    Value<int>? id,
    Value<String>? name,
    Value<int>? notificationSlot,
    Value<DateTime>? createdAt,
  }) {
    return PatientsCompanion(
      uuid: uuid ?? this.uuid,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      id: id ?? this.id,
      name: name ?? this.name,
      notificationSlot: notificationSlot ?? this.notificationSlot,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (notificationSlot.present) {
      map['notification_slot'] = Variable<int>(notificationSlot.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PatientsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('notificationSlot: $notificationSlot, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DayRoutinesTable extends DayRoutines
    with TableInfo<$DayRoutinesTable, DayRoutineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayRoutinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncUuid,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: nowMs,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<int> patientId = GeneratedColumn<int>(
    'patient_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES patients (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _wakeMinutesMeta = const VerificationMeta(
    'wakeMinutes',
  );
  @override
  late final GeneratedColumn<int> wakeMinutes = GeneratedColumn<int>(
    'wake_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _breakfastMinutesMeta = const VerificationMeta(
    'breakfastMinutes',
  );
  @override
  late final GeneratedColumn<int> breakfastMinutes = GeneratedColumn<int>(
    'breakfast_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lunchMinutesMeta = const VerificationMeta(
    'lunchMinutes',
  );
  @override
  late final GeneratedColumn<int> lunchMinutes = GeneratedColumn<int>(
    'lunch_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dinnerMinutesMeta = const VerificationMeta(
    'dinnerMinutes',
  );
  @override
  late final GeneratedColumn<int> dinnerMinutes = GeneratedColumn<int>(
    'dinner_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sleepMinutesMeta = const VerificationMeta(
    'sleepMinutes',
  );
  @override
  late final GeneratedColumn<int> sleepMinutes = GeneratedColumn<int>(
    'sleep_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    patientId,
    wakeMinutes,
    breakfastMinutes,
    lunchMinutes,
    dinnerMinutes,
    sleepMinutes,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_routines';
  @override
  VerificationContext validateIntegrity(
    Insertable<DayRoutineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('wake_minutes')) {
      context.handle(
        _wakeMinutesMeta,
        wakeMinutes.isAcceptableOrUnknown(
          data['wake_minutes']!,
          _wakeMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wakeMinutesMeta);
    }
    if (data.containsKey('breakfast_minutes')) {
      context.handle(
        _breakfastMinutesMeta,
        breakfastMinutes.isAcceptableOrUnknown(
          data['breakfast_minutes']!,
          _breakfastMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_breakfastMinutesMeta);
    }
    if (data.containsKey('lunch_minutes')) {
      context.handle(
        _lunchMinutesMeta,
        lunchMinutes.isAcceptableOrUnknown(
          data['lunch_minutes']!,
          _lunchMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lunchMinutesMeta);
    }
    if (data.containsKey('dinner_minutes')) {
      context.handle(
        _dinnerMinutesMeta,
        dinnerMinutes.isAcceptableOrUnknown(
          data['dinner_minutes']!,
          _dinnerMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dinnerMinutesMeta);
    }
    if (data.containsKey('sleep_minutes')) {
      context.handle(
        _sleepMinutesMeta,
        sleepMinutes.isAcceptableOrUnknown(
          data['sleep_minutes']!,
          _sleepMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sleepMinutesMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {patientId},
  ];
  @override
  DayRoutineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayRoutineRow(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}patient_id'],
      )!,
      wakeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wake_minutes'],
      )!,
      breakfastMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}breakfast_minutes'],
      )!,
      lunchMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lunch_minutes'],
      )!,
      dinnerMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dinner_minutes'],
      )!,
      sleepMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_minutes'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DayRoutinesTable createAlias(String alias) {
    return $DayRoutinesTable(attachedDatabase, alias);
  }
}

class DayRoutineRow extends DataClass implements Insertable<DayRoutineRow> {
  final String uuid;

  /// بتتصان من قاعدة البيانات نفسها (تريجرات في beforeOpen) — مش من نقاط
  /// النداء: اللي لازم حد يفتكره هيتنسي، والصف ده كان هيبطل يتزامن في صمت.
  final int updatedAtMs;

  /// آخر updated_at_ms اتدفع للسحابة — null يعني عمره ما اتدفع.
  final int? syncedAtMs;
  final int id;
  final int patientId;

  /// دقايق من منتصف الليل (0 → 1439) — نفس تمثيل [MinuteOfDay].
  final int wakeMinutes;
  final int breakfastMinutes;
  final int lunchMinutes;
  final int dinnerMinutes;
  final int sleepMinutes;
  final DateTime updatedAt;
  const DayRoutineRow({
    required this.uuid,
    required this.updatedAtMs,
    this.syncedAtMs,
    required this.id,
    required this.patientId,
    required this.wakeMinutes,
    required this.breakfastMinutes,
    required this.lunchMinutes,
    required this.dinnerMinutes,
    required this.sleepMinutes,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    map['id'] = Variable<int>(id);
    map['patient_id'] = Variable<int>(patientId);
    map['wake_minutes'] = Variable<int>(wakeMinutes);
    map['breakfast_minutes'] = Variable<int>(breakfastMinutes);
    map['lunch_minutes'] = Variable<int>(lunchMinutes);
    map['dinner_minutes'] = Variable<int>(dinnerMinutes);
    map['sleep_minutes'] = Variable<int>(sleepMinutes);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DayRoutinesCompanion toCompanion(bool nullToAbsent) {
    return DayRoutinesCompanion(
      uuid: Value(uuid),
      updatedAtMs: Value(updatedAtMs),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
      id: Value(id),
      patientId: Value(patientId),
      wakeMinutes: Value(wakeMinutes),
      breakfastMinutes: Value(breakfastMinutes),
      lunchMinutes: Value(lunchMinutes),
      dinnerMinutes: Value(dinnerMinutes),
      sleepMinutes: Value(sleepMinutes),
      updatedAt: Value(updatedAt),
    );
  }

  factory DayRoutineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayRoutineRow(
      uuid: serializer.fromJson<String>(json['uuid']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
      id: serializer.fromJson<int>(json['id']),
      patientId: serializer.fromJson<int>(json['patientId']),
      wakeMinutes: serializer.fromJson<int>(json['wakeMinutes']),
      breakfastMinutes: serializer.fromJson<int>(json['breakfastMinutes']),
      lunchMinutes: serializer.fromJson<int>(json['lunchMinutes']),
      dinnerMinutes: serializer.fromJson<int>(json['dinnerMinutes']),
      sleepMinutes: serializer.fromJson<int>(json['sleepMinutes']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
      'id': serializer.toJson<int>(id),
      'patientId': serializer.toJson<int>(patientId),
      'wakeMinutes': serializer.toJson<int>(wakeMinutes),
      'breakfastMinutes': serializer.toJson<int>(breakfastMinutes),
      'lunchMinutes': serializer.toJson<int>(lunchMinutes),
      'dinnerMinutes': serializer.toJson<int>(dinnerMinutes),
      'sleepMinutes': serializer.toJson<int>(sleepMinutes),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DayRoutineRow copyWith({
    String? uuid,
    int? updatedAtMs,
    Value<int?> syncedAtMs = const Value.absent(),
    int? id,
    int? patientId,
    int? wakeMinutes,
    int? breakfastMinutes,
    int? lunchMinutes,
    int? dinnerMinutes,
    int? sleepMinutes,
    DateTime? updatedAt,
  }) => DayRoutineRow(
    uuid: uuid ?? this.uuid,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    wakeMinutes: wakeMinutes ?? this.wakeMinutes,
    breakfastMinutes: breakfastMinutes ?? this.breakfastMinutes,
    lunchMinutes: lunchMinutes ?? this.lunchMinutes,
    dinnerMinutes: dinnerMinutes ?? this.dinnerMinutes,
    sleepMinutes: sleepMinutes ?? this.sleepMinutes,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DayRoutineRow copyWithCompanion(DayRoutinesCompanion data) {
    return DayRoutineRow(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      wakeMinutes: data.wakeMinutes.present
          ? data.wakeMinutes.value
          : this.wakeMinutes,
      breakfastMinutes: data.breakfastMinutes.present
          ? data.breakfastMinutes.value
          : this.breakfastMinutes,
      lunchMinutes: data.lunchMinutes.present
          ? data.lunchMinutes.value
          : this.lunchMinutes,
      dinnerMinutes: data.dinnerMinutes.present
          ? data.dinnerMinutes.value
          : this.dinnerMinutes,
      sleepMinutes: data.sleepMinutes.present
          ? data.sleepMinutes.value
          : this.sleepMinutes,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayRoutineRow(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('wakeMinutes: $wakeMinutes, ')
          ..write('breakfastMinutes: $breakfastMinutes, ')
          ..write('lunchMinutes: $lunchMinutes, ')
          ..write('dinnerMinutes: $dinnerMinutes, ')
          ..write('sleepMinutes: $sleepMinutes, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    patientId,
    wakeMinutes,
    breakfastMinutes,
    lunchMinutes,
    dinnerMinutes,
    sleepMinutes,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayRoutineRow &&
          other.uuid == this.uuid &&
          other.updatedAtMs == this.updatedAtMs &&
          other.syncedAtMs == this.syncedAtMs &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.wakeMinutes == this.wakeMinutes &&
          other.breakfastMinutes == this.breakfastMinutes &&
          other.lunchMinutes == this.lunchMinutes &&
          other.dinnerMinutes == this.dinnerMinutes &&
          other.sleepMinutes == this.sleepMinutes &&
          other.updatedAt == this.updatedAt);
}

class DayRoutinesCompanion extends UpdateCompanion<DayRoutineRow> {
  final Value<String> uuid;
  final Value<int> updatedAtMs;
  final Value<int?> syncedAtMs;
  final Value<int> id;
  final Value<int> patientId;
  final Value<int> wakeMinutes;
  final Value<int> breakfastMinutes;
  final Value<int> lunchMinutes;
  final Value<int> dinnerMinutes;
  final Value<int> sleepMinutes;
  final Value<DateTime> updatedAt;
  const DayRoutinesCompanion({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.wakeMinutes = const Value.absent(),
    this.breakfastMinutes = const Value.absent(),
    this.lunchMinutes = const Value.absent(),
    this.dinnerMinutes = const Value.absent(),
    this.sleepMinutes = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DayRoutinesCompanion.insert({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    required int patientId,
    required int wakeMinutes,
    required int breakfastMinutes,
    required int lunchMinutes,
    required int dinnerMinutes,
    required int sleepMinutes,
    this.updatedAt = const Value.absent(),
  }) : patientId = Value(patientId),
       wakeMinutes = Value(wakeMinutes),
       breakfastMinutes = Value(breakfastMinutes),
       lunchMinutes = Value(lunchMinutes),
       dinnerMinutes = Value(dinnerMinutes),
       sleepMinutes = Value(sleepMinutes);
  static Insertable<DayRoutineRow> custom({
    Expression<String>? uuid,
    Expression<int>? updatedAtMs,
    Expression<int>? syncedAtMs,
    Expression<int>? id,
    Expression<int>? patientId,
    Expression<int>? wakeMinutes,
    Expression<int>? breakfastMinutes,
    Expression<int>? lunchMinutes,
    Expression<int>? dinnerMinutes,
    Expression<int>? sleepMinutes,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (wakeMinutes != null) 'wake_minutes': wakeMinutes,
      if (breakfastMinutes != null) 'breakfast_minutes': breakfastMinutes,
      if (lunchMinutes != null) 'lunch_minutes': lunchMinutes,
      if (dinnerMinutes != null) 'dinner_minutes': dinnerMinutes,
      if (sleepMinutes != null) 'sleep_minutes': sleepMinutes,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DayRoutinesCompanion copyWith({
    Value<String>? uuid,
    Value<int>? updatedAtMs,
    Value<int?>? syncedAtMs,
    Value<int>? id,
    Value<int>? patientId,
    Value<int>? wakeMinutes,
    Value<int>? breakfastMinutes,
    Value<int>? lunchMinutes,
    Value<int>? dinnerMinutes,
    Value<int>? sleepMinutes,
    Value<DateTime>? updatedAt,
  }) {
    return DayRoutinesCompanion(
      uuid: uuid ?? this.uuid,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      wakeMinutes: wakeMinutes ?? this.wakeMinutes,
      breakfastMinutes: breakfastMinutes ?? this.breakfastMinutes,
      lunchMinutes: lunchMinutes ?? this.lunchMinutes,
      dinnerMinutes: dinnerMinutes ?? this.dinnerMinutes,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<int>(patientId.value);
    }
    if (wakeMinutes.present) {
      map['wake_minutes'] = Variable<int>(wakeMinutes.value);
    }
    if (breakfastMinutes.present) {
      map['breakfast_minutes'] = Variable<int>(breakfastMinutes.value);
    }
    if (lunchMinutes.present) {
      map['lunch_minutes'] = Variable<int>(lunchMinutes.value);
    }
    if (dinnerMinutes.present) {
      map['dinner_minutes'] = Variable<int>(dinnerMinutes.value);
    }
    if (sleepMinutes.present) {
      map['sleep_minutes'] = Variable<int>(sleepMinutes.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayRoutinesCompanion(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('wakeMinutes: $wakeMinutes, ')
          ..write('breakfastMinutes: $breakfastMinutes, ')
          ..write('lunchMinutes: $lunchMinutes, ')
          ..write('dinnerMinutes: $dinnerMinutes, ')
          ..write('sleepMinutes: $sleepMinutes, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $MedicationsTable extends Medications
    with TableInfo<$MedicationsTable, MedicationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MedicationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncUuid,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: nowMs,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<int> patientId = GeneratedColumn<int>(
    'patient_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES patients (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountLabelMeta = const VerificationMeta(
    'amountLabel',
  );
  @override
  late final GeneratedColumn<String> amountLabel = GeneratedColumn<String>(
    'amount_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountUnknownMeta = const VerificationMeta(
    'amountUnknown',
  );
  @override
  late final GeneratedColumn<bool> amountUnknown = GeneratedColumn<bool>(
    'amount_unknown',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("amount_unknown" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stoppedAtMeta = const VerificationMeta(
    'stoppedAt',
  );
  @override
  late final GeneratedColumn<DateTime> stoppedAt = GeneratedColumn<DateTime>(
    'stopped_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    patientId,
    name,
    amountLabel,
    amountUnknown,
    notes,
    stoppedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'medications';
  @override
  VerificationContext validateIntegrity(
    Insertable<MedicationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('amount_label')) {
      context.handle(
        _amountLabelMeta,
        amountLabel.isAcceptableOrUnknown(
          data['amount_label']!,
          _amountLabelMeta,
        ),
      );
    }
    if (data.containsKey('amount_unknown')) {
      context.handle(
        _amountUnknownMeta,
        amountUnknown.isAcceptableOrUnknown(
          data['amount_unknown']!,
          _amountUnknownMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('stopped_at')) {
      context.handle(
        _stoppedAtMeta,
        stoppedAt.isAcceptableOrUnknown(data['stopped_at']!, _stoppedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MedicationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MedicationRow(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}patient_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      amountLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_label'],
      ),
      amountUnknown: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}amount_unknown'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      stoppedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}stopped_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MedicationsTable createAlias(String alias) {
    return $MedicationsTable(attachedDatabase, alias);
  }
}

class MedicationRow extends DataClass implements Insertable<MedicationRow> {
  final String uuid;

  /// بتتصان من قاعدة البيانات نفسها (تريجرات في beforeOpen) — مش من نقاط
  /// النداء: اللي لازم حد يفتكره هيتنسي، والصف ده كان هيبطل يتزامن في صمت.
  final int updatedAtMs;

  /// آخر updated_at_ms اتدفع للسحابة — null يعني عمره ما اتدفع.
  final int? syncedAtMs;
  final int id;
  final int patientId;
  final String name;
  final String? amountLabel;

  /// الورقة ما قالتش الجرعة. مسجّل عشان نسأل عنه بعدين — مجهول اتكتب
  /// ونقدر نتابعه كويس؛ مجهول اتنسي في صمت لأ.
  final bool amountUnknown;
  final String? notes;

  /// null معناها الدوا لسه شغّال.
  ///
  /// العمود ده ما بيتكتبش غير من `stopMedication` — يعني بإيد إنسان. مفيش
  /// أي مسار في التطبيق بيوقف دوا من نفسه.
  final DateTime? stoppedAt;
  final DateTime createdAt;
  const MedicationRow({
    required this.uuid,
    required this.updatedAtMs,
    this.syncedAtMs,
    required this.id,
    required this.patientId,
    required this.name,
    this.amountLabel,
    required this.amountUnknown,
    this.notes,
    this.stoppedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    map['id'] = Variable<int>(id);
    map['patient_id'] = Variable<int>(patientId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || amountLabel != null) {
      map['amount_label'] = Variable<String>(amountLabel);
    }
    map['amount_unknown'] = Variable<bool>(amountUnknown);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || stoppedAt != null) {
      map['stopped_at'] = Variable<DateTime>(stoppedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MedicationsCompanion toCompanion(bool nullToAbsent) {
    return MedicationsCompanion(
      uuid: Value(uuid),
      updatedAtMs: Value(updatedAtMs),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
      id: Value(id),
      patientId: Value(patientId),
      name: Value(name),
      amountLabel: amountLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(amountLabel),
      amountUnknown: Value(amountUnknown),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      stoppedAt: stoppedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(stoppedAt),
      createdAt: Value(createdAt),
    );
  }

  factory MedicationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MedicationRow(
      uuid: serializer.fromJson<String>(json['uuid']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
      id: serializer.fromJson<int>(json['id']),
      patientId: serializer.fromJson<int>(json['patientId']),
      name: serializer.fromJson<String>(json['name']),
      amountLabel: serializer.fromJson<String?>(json['amountLabel']),
      amountUnknown: serializer.fromJson<bool>(json['amountUnknown']),
      notes: serializer.fromJson<String?>(json['notes']),
      stoppedAt: serializer.fromJson<DateTime?>(json['stoppedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
      'id': serializer.toJson<int>(id),
      'patientId': serializer.toJson<int>(patientId),
      'name': serializer.toJson<String>(name),
      'amountLabel': serializer.toJson<String?>(amountLabel),
      'amountUnknown': serializer.toJson<bool>(amountUnknown),
      'notes': serializer.toJson<String?>(notes),
      'stoppedAt': serializer.toJson<DateTime?>(stoppedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MedicationRow copyWith({
    String? uuid,
    int? updatedAtMs,
    Value<int?> syncedAtMs = const Value.absent(),
    int? id,
    int? patientId,
    String? name,
    Value<String?> amountLabel = const Value.absent(),
    bool? amountUnknown,
    Value<String?> notes = const Value.absent(),
    Value<DateTime?> stoppedAt = const Value.absent(),
    DateTime? createdAt,
  }) => MedicationRow(
    uuid: uuid ?? this.uuid,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    name: name ?? this.name,
    amountLabel: amountLabel.present ? amountLabel.value : this.amountLabel,
    amountUnknown: amountUnknown ?? this.amountUnknown,
    notes: notes.present ? notes.value : this.notes,
    stoppedAt: stoppedAt.present ? stoppedAt.value : this.stoppedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  MedicationRow copyWithCompanion(MedicationsCompanion data) {
    return MedicationRow(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      name: data.name.present ? data.name.value : this.name,
      amountLabel: data.amountLabel.present
          ? data.amountLabel.value
          : this.amountLabel,
      amountUnknown: data.amountUnknown.present
          ? data.amountUnknown.value
          : this.amountUnknown,
      notes: data.notes.present ? data.notes.value : this.notes,
      stoppedAt: data.stoppedAt.present ? data.stoppedAt.value : this.stoppedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MedicationRow(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('name: $name, ')
          ..write('amountLabel: $amountLabel, ')
          ..write('amountUnknown: $amountUnknown, ')
          ..write('notes: $notes, ')
          ..write('stoppedAt: $stoppedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    patientId,
    name,
    amountLabel,
    amountUnknown,
    notes,
    stoppedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MedicationRow &&
          other.uuid == this.uuid &&
          other.updatedAtMs == this.updatedAtMs &&
          other.syncedAtMs == this.syncedAtMs &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.name == this.name &&
          other.amountLabel == this.amountLabel &&
          other.amountUnknown == this.amountUnknown &&
          other.notes == this.notes &&
          other.stoppedAt == this.stoppedAt &&
          other.createdAt == this.createdAt);
}

class MedicationsCompanion extends UpdateCompanion<MedicationRow> {
  final Value<String> uuid;
  final Value<int> updatedAtMs;
  final Value<int?> syncedAtMs;
  final Value<int> id;
  final Value<int> patientId;
  final Value<String> name;
  final Value<String?> amountLabel;
  final Value<bool> amountUnknown;
  final Value<String?> notes;
  final Value<DateTime?> stoppedAt;
  final Value<DateTime> createdAt;
  const MedicationsCompanion({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.name = const Value.absent(),
    this.amountLabel = const Value.absent(),
    this.amountUnknown = const Value.absent(),
    this.notes = const Value.absent(),
    this.stoppedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MedicationsCompanion.insert({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    required int patientId,
    required String name,
    this.amountLabel = const Value.absent(),
    this.amountUnknown = const Value.absent(),
    this.notes = const Value.absent(),
    this.stoppedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : patientId = Value(patientId),
       name = Value(name);
  static Insertable<MedicationRow> custom({
    Expression<String>? uuid,
    Expression<int>? updatedAtMs,
    Expression<int>? syncedAtMs,
    Expression<int>? id,
    Expression<int>? patientId,
    Expression<String>? name,
    Expression<String>? amountLabel,
    Expression<bool>? amountUnknown,
    Expression<String>? notes,
    Expression<DateTime>? stoppedAt,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (name != null) 'name': name,
      if (amountLabel != null) 'amount_label': amountLabel,
      if (amountUnknown != null) 'amount_unknown': amountUnknown,
      if (notes != null) 'notes': notes,
      if (stoppedAt != null) 'stopped_at': stoppedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MedicationsCompanion copyWith({
    Value<String>? uuid,
    Value<int>? updatedAtMs,
    Value<int?>? syncedAtMs,
    Value<int>? id,
    Value<int>? patientId,
    Value<String>? name,
    Value<String?>? amountLabel,
    Value<bool>? amountUnknown,
    Value<String?>? notes,
    Value<DateTime?>? stoppedAt,
    Value<DateTime>? createdAt,
  }) {
    return MedicationsCompanion(
      uuid: uuid ?? this.uuid,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      name: name ?? this.name,
      amountLabel: amountLabel ?? this.amountLabel,
      amountUnknown: amountUnknown ?? this.amountUnknown,
      notes: notes ?? this.notes,
      stoppedAt: stoppedAt ?? this.stoppedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<int>(patientId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (amountLabel.present) {
      map['amount_label'] = Variable<String>(amountLabel.value);
    }
    if (amountUnknown.present) {
      map['amount_unknown'] = Variable<bool>(amountUnknown.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (stoppedAt.present) {
      map['stopped_at'] = Variable<DateTime>(stoppedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MedicationsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('name: $name, ')
          ..write('amountLabel: $amountLabel, ')
          ..write('amountUnknown: $amountUnknown, ')
          ..write('notes: $notes, ')
          ..write('stoppedAt: $stoppedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DoseSchedulesTable extends DoseSchedules
    with TableInfo<$DoseSchedulesTable, DoseScheduleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DoseSchedulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncUuid,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: nowMs,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _medicationIdMeta = const VerificationMeta(
    'medicationId',
  );
  @override
  late final GeneratedColumn<int> medicationId = GeneratedColumn<int>(
    'medication_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES medications (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DoseTimingKind, String>
  timingKind = GeneratedColumn<String>(
    'timing_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: Constant(DoseTimingKind.anchor.name),
  ).withConverter<DoseTimingKind>($DoseSchedulesTable.$convertertimingKind);
  @override
  late final GeneratedColumnWithTypeConverter<DayAnchor?, String> anchor =
      GeneratedColumn<String>(
        'anchor',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DayAnchor?>($DoseSchedulesTable.$converteranchorn);
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DoseRepeat, String> repeat =
      GeneratedColumn<String>(
        'repeat',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DoseRepeat>($DoseSchedulesTable.$converterrepeat);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> startDate =
      GeneratedColumn<String>(
        'start_date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DoseSchedulesTable.$converterstartDate);
  static const VerificationMeta _durationDaysMeta = const VerificationMeta(
    'durationDays',
  );
  @override
  late final GeneratedColumn<int> durationDays = GeneratedColumn<int>(
    'duration_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    medicationId,
    timingKind,
    anchor,
    offsetMinutes,
    repeat,
    startDate,
    durationDays,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dose_schedules';
  @override
  VerificationContext validateIntegrity(
    Insertable<DoseScheduleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('medication_id')) {
      context.handle(
        _medicationIdMeta,
        medicationId.isAcceptableOrUnknown(
          data['medication_id']!,
          _medicationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_medicationIdMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    }
    if (data.containsKey('duration_days')) {
      context.handle(
        _durationDaysMeta,
        durationDays.isAcceptableOrUnknown(
          data['duration_days']!,
          _durationDaysMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DoseScheduleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DoseScheduleRow(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      medicationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}medication_id'],
      )!,
      timingKind: $DoseSchedulesTable.$convertertimingKind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}timing_kind'],
        )!,
      ),
      anchor: $DoseSchedulesTable.$converteranchorn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}anchor'],
        ),
      ),
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      ),
      repeat: $DoseSchedulesTable.$converterrepeat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}repeat'],
        )!,
      ),
      startDate: $DoseSchedulesTable.$converterstartDate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}start_date'],
        )!,
      ),
      durationDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_days'],
      ),
    );
  }

  @override
  $DoseSchedulesTable createAlias(String alias) {
    return $DoseSchedulesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DoseTimingKind, String, String>
  $convertertimingKind = const EnumNameConverter<DoseTimingKind>(
    DoseTimingKind.values,
  );
  static JsonTypeConverter2<DayAnchor, String, String> $converteranchor =
      const EnumNameConverter<DayAnchor>(DayAnchor.values);
  static JsonTypeConverter2<DayAnchor?, String?, String?> $converteranchorn =
      JsonTypeConverter2.asNullable($converteranchor);
  static JsonTypeConverter2<DoseRepeat, String, String> $converterrepeat =
      const EnumNameConverter<DoseRepeat>(DoseRepeat.values);
  static TypeConverter<DateTime, String> $converterstartDate =
      const DateOnlyConverter();
}

class DoseScheduleRow extends DataClass implements Insertable<DoseScheduleRow> {
  final String uuid;

  /// بتتصان من قاعدة البيانات نفسها (تريجرات في beforeOpen) — مش من نقاط
  /// النداء: اللي لازم حد يفتكره هيتنسي، والصف ده كان هيبطل يتزامن في صمت.
  final int updatedAtMs;

  /// آخر updated_at_ms اتدفع للسحابة — null يعني عمره ما اتدفع.
  final int? syncedAtMs;
  final int id;
  final int medicationId;

  /// الافتراضي مرساة — وده اللي الصفوف القديمة بتاخده في الترحيل.
  final DoseTimingKind timingKind;

  /// المرساة — null بس لو [timingKind] ساعة ثابتة.
  final DayAnchor? anchor;

  /// بالسالب = قبل المرساة، بالموجب = بعدها. null لو ساعة ثابتة.
  final int? offsetMinutes;
  final DoseRepeat repeat;
  final DateTime startDate;

  /// null = مدة مفتوحة. ما بيتحطّش تخميناً أبداً.
  final int? durationDays;
  const DoseScheduleRow({
    required this.uuid,
    required this.updatedAtMs,
    this.syncedAtMs,
    required this.id,
    required this.medicationId,
    required this.timingKind,
    this.anchor,
    this.offsetMinutes,
    required this.repeat,
    required this.startDate,
    this.durationDays,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    map['id'] = Variable<int>(id);
    map['medication_id'] = Variable<int>(medicationId);
    {
      map['timing_kind'] = Variable<String>(
        $DoseSchedulesTable.$convertertimingKind.toSql(timingKind),
      );
    }
    if (!nullToAbsent || anchor != null) {
      map['anchor'] = Variable<String>(
        $DoseSchedulesTable.$converteranchorn.toSql(anchor),
      );
    }
    if (!nullToAbsent || offsetMinutes != null) {
      map['offset_minutes'] = Variable<int>(offsetMinutes);
    }
    {
      map['repeat'] = Variable<String>(
        $DoseSchedulesTable.$converterrepeat.toSql(repeat),
      );
    }
    {
      map['start_date'] = Variable<String>(
        $DoseSchedulesTable.$converterstartDate.toSql(startDate),
      );
    }
    if (!nullToAbsent || durationDays != null) {
      map['duration_days'] = Variable<int>(durationDays);
    }
    return map;
  }

  DoseSchedulesCompanion toCompanion(bool nullToAbsent) {
    return DoseSchedulesCompanion(
      uuid: Value(uuid),
      updatedAtMs: Value(updatedAtMs),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
      id: Value(id),
      medicationId: Value(medicationId),
      timingKind: Value(timingKind),
      anchor: anchor == null && nullToAbsent
          ? const Value.absent()
          : Value(anchor),
      offsetMinutes: offsetMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(offsetMinutes),
      repeat: Value(repeat),
      startDate: Value(startDate),
      durationDays: durationDays == null && nullToAbsent
          ? const Value.absent()
          : Value(durationDays),
    );
  }

  factory DoseScheduleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DoseScheduleRow(
      uuid: serializer.fromJson<String>(json['uuid']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
      id: serializer.fromJson<int>(json['id']),
      medicationId: serializer.fromJson<int>(json['medicationId']),
      timingKind: $DoseSchedulesTable.$convertertimingKind.fromJson(
        serializer.fromJson<String>(json['timingKind']),
      ),
      anchor: $DoseSchedulesTable.$converteranchorn.fromJson(
        serializer.fromJson<String?>(json['anchor']),
      ),
      offsetMinutes: serializer.fromJson<int?>(json['offsetMinutes']),
      repeat: $DoseSchedulesTable.$converterrepeat.fromJson(
        serializer.fromJson<String>(json['repeat']),
      ),
      startDate: serializer.fromJson<DateTime>(json['startDate']),
      durationDays: serializer.fromJson<int?>(json['durationDays']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
      'id': serializer.toJson<int>(id),
      'medicationId': serializer.toJson<int>(medicationId),
      'timingKind': serializer.toJson<String>(
        $DoseSchedulesTable.$convertertimingKind.toJson(timingKind),
      ),
      'anchor': serializer.toJson<String?>(
        $DoseSchedulesTable.$converteranchorn.toJson(anchor),
      ),
      'offsetMinutes': serializer.toJson<int?>(offsetMinutes),
      'repeat': serializer.toJson<String>(
        $DoseSchedulesTable.$converterrepeat.toJson(repeat),
      ),
      'startDate': serializer.toJson<DateTime>(startDate),
      'durationDays': serializer.toJson<int?>(durationDays),
    };
  }

  DoseScheduleRow copyWith({
    String? uuid,
    int? updatedAtMs,
    Value<int?> syncedAtMs = const Value.absent(),
    int? id,
    int? medicationId,
    DoseTimingKind? timingKind,
    Value<DayAnchor?> anchor = const Value.absent(),
    Value<int?> offsetMinutes = const Value.absent(),
    DoseRepeat? repeat,
    DateTime? startDate,
    Value<int?> durationDays = const Value.absent(),
  }) => DoseScheduleRow(
    uuid: uuid ?? this.uuid,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
    id: id ?? this.id,
    medicationId: medicationId ?? this.medicationId,
    timingKind: timingKind ?? this.timingKind,
    anchor: anchor.present ? anchor.value : this.anchor,
    offsetMinutes: offsetMinutes.present
        ? offsetMinutes.value
        : this.offsetMinutes,
    repeat: repeat ?? this.repeat,
    startDate: startDate ?? this.startDate,
    durationDays: durationDays.present ? durationDays.value : this.durationDays,
  );
  DoseScheduleRow copyWithCompanion(DoseSchedulesCompanion data) {
    return DoseScheduleRow(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
      id: data.id.present ? data.id.value : this.id,
      medicationId: data.medicationId.present
          ? data.medicationId.value
          : this.medicationId,
      timingKind: data.timingKind.present
          ? data.timingKind.value
          : this.timingKind,
      anchor: data.anchor.present ? data.anchor.value : this.anchor,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      repeat: data.repeat.present ? data.repeat.value : this.repeat,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      durationDays: data.durationDays.present
          ? data.durationDays.value
          : this.durationDays,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DoseScheduleRow(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('medicationId: $medicationId, ')
          ..write('timingKind: $timingKind, ')
          ..write('anchor: $anchor, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('repeat: $repeat, ')
          ..write('startDate: $startDate, ')
          ..write('durationDays: $durationDays')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    medicationId,
    timingKind,
    anchor,
    offsetMinutes,
    repeat,
    startDate,
    durationDays,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DoseScheduleRow &&
          other.uuid == this.uuid &&
          other.updatedAtMs == this.updatedAtMs &&
          other.syncedAtMs == this.syncedAtMs &&
          other.id == this.id &&
          other.medicationId == this.medicationId &&
          other.timingKind == this.timingKind &&
          other.anchor == this.anchor &&
          other.offsetMinutes == this.offsetMinutes &&
          other.repeat == this.repeat &&
          other.startDate == this.startDate &&
          other.durationDays == this.durationDays);
}

class DoseSchedulesCompanion extends UpdateCompanion<DoseScheduleRow> {
  final Value<String> uuid;
  final Value<int> updatedAtMs;
  final Value<int?> syncedAtMs;
  final Value<int> id;
  final Value<int> medicationId;
  final Value<DoseTimingKind> timingKind;
  final Value<DayAnchor?> anchor;
  final Value<int?> offsetMinutes;
  final Value<DoseRepeat> repeat;
  final Value<DateTime> startDate;
  final Value<int?> durationDays;
  const DoseSchedulesCompanion({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    this.medicationId = const Value.absent(),
    this.timingKind = const Value.absent(),
    this.anchor = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.repeat = const Value.absent(),
    this.startDate = const Value.absent(),
    this.durationDays = const Value.absent(),
  });
  DoseSchedulesCompanion.insert({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    required int medicationId,
    this.timingKind = const Value.absent(),
    this.anchor = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    required DoseRepeat repeat,
    required DateTime startDate,
    this.durationDays = const Value.absent(),
  }) : medicationId = Value(medicationId),
       repeat = Value(repeat),
       startDate = Value(startDate);
  static Insertable<DoseScheduleRow> custom({
    Expression<String>? uuid,
    Expression<int>? updatedAtMs,
    Expression<int>? syncedAtMs,
    Expression<int>? id,
    Expression<int>? medicationId,
    Expression<String>? timingKind,
    Expression<String>? anchor,
    Expression<int>? offsetMinutes,
    Expression<String>? repeat,
    Expression<String>? startDate,
    Expression<int>? durationDays,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
      if (id != null) 'id': id,
      if (medicationId != null) 'medication_id': medicationId,
      if (timingKind != null) 'timing_kind': timingKind,
      if (anchor != null) 'anchor': anchor,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (repeat != null) 'repeat': repeat,
      if (startDate != null) 'start_date': startDate,
      if (durationDays != null) 'duration_days': durationDays,
    });
  }

  DoseSchedulesCompanion copyWith({
    Value<String>? uuid,
    Value<int>? updatedAtMs,
    Value<int?>? syncedAtMs,
    Value<int>? id,
    Value<int>? medicationId,
    Value<DoseTimingKind>? timingKind,
    Value<DayAnchor?>? anchor,
    Value<int?>? offsetMinutes,
    Value<DoseRepeat>? repeat,
    Value<DateTime>? startDate,
    Value<int?>? durationDays,
  }) {
    return DoseSchedulesCompanion(
      uuid: uuid ?? this.uuid,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      id: id ?? this.id,
      medicationId: medicationId ?? this.medicationId,
      timingKind: timingKind ?? this.timingKind,
      anchor: anchor ?? this.anchor,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      repeat: repeat ?? this.repeat,
      startDate: startDate ?? this.startDate,
      durationDays: durationDays ?? this.durationDays,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (medicationId.present) {
      map['medication_id'] = Variable<int>(medicationId.value);
    }
    if (timingKind.present) {
      map['timing_kind'] = Variable<String>(
        $DoseSchedulesTable.$convertertimingKind.toSql(timingKind.value),
      );
    }
    if (anchor.present) {
      map['anchor'] = Variable<String>(
        $DoseSchedulesTable.$converteranchorn.toSql(anchor.value),
      );
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (repeat.present) {
      map['repeat'] = Variable<String>(
        $DoseSchedulesTable.$converterrepeat.toSql(repeat.value),
      );
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(
        $DoseSchedulesTable.$converterstartDate.toSql(startDate.value),
      );
    }
    if (durationDays.present) {
      map['duration_days'] = Variable<int>(durationDays.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DoseSchedulesCompanion(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('medicationId: $medicationId, ')
          ..write('timingKind: $timingKind, ')
          ..write('anchor: $anchor, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('repeat: $repeat, ')
          ..write('startDate: $startDate, ')
          ..write('durationDays: $durationDays')
          ..write(')'))
        .toString();
  }
}

class $FixedTimingsTable extends FixedTimings
    with TableInfo<$FixedTimingsTable, FixedTimingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixedTimingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncUuid,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: nowMs,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doseScheduleIdMeta = const VerificationMeta(
    'doseScheduleId',
  );
  @override
  late final GeneratedColumn<int> doseScheduleId = GeneratedColumn<int>(
    'dose_schedule_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dose_schedules (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _minuteOfDayMeta = const VerificationMeta(
    'minuteOfDay',
  );
  @override
  late final GeneratedColumn<int> minuteOfDay = GeneratedColumn<int>(
    'minute_of_day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    uuid,
    updatedAtMs,
    syncedAtMs,
    doseScheduleId,
    minuteOfDay,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixed_timings';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixedTimingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('dose_schedule_id')) {
      context.handle(
        _doseScheduleIdMeta,
        doseScheduleId.isAcceptableOrUnknown(
          data['dose_schedule_id']!,
          _doseScheduleIdMeta,
        ),
      );
    }
    if (data.containsKey('minute_of_day')) {
      context.handle(
        _minuteOfDayMeta,
        minuteOfDay.isAcceptableOrUnknown(
          data['minute_of_day']!,
          _minuteOfDayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_minuteOfDayMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {doseScheduleId};
  @override
  FixedTimingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixedTimingRow(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
      doseScheduleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dose_schedule_id'],
      )!,
      minuteOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minute_of_day'],
      )!,
    );
  }

  @override
  $FixedTimingsTable createAlias(String alias) {
    return $FixedTimingsTable(attachedDatabase, alias);
  }
}

class FixedTimingRow extends DataClass implements Insertable<FixedTimingRow> {
  final String uuid;

  /// بتتصان من قاعدة البيانات نفسها (تريجرات في beforeOpen) — مش من نقاط
  /// النداء: اللي لازم حد يفتكره هيتنسي، والصف ده كان هيبطل يتزامن في صمت.
  final int updatedAtMs;

  /// آخر updated_at_ms اتدفع للسحابة — null يعني عمره ما اتدفع.
  final int? syncedAtMs;
  final int doseScheduleId;

  /// دقايق من منتصف الليل (0 → 1439) — نفس تمثيل [MinuteOfDay].
  final int minuteOfDay;
  const FixedTimingRow({
    required this.uuid,
    required this.updatedAtMs,
    this.syncedAtMs,
    required this.doseScheduleId,
    required this.minuteOfDay,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    map['dose_schedule_id'] = Variable<int>(doseScheduleId);
    map['minute_of_day'] = Variable<int>(minuteOfDay);
    return map;
  }

  FixedTimingsCompanion toCompanion(bool nullToAbsent) {
    return FixedTimingsCompanion(
      uuid: Value(uuid),
      updatedAtMs: Value(updatedAtMs),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
      doseScheduleId: Value(doseScheduleId),
      minuteOfDay: Value(minuteOfDay),
    );
  }

  factory FixedTimingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixedTimingRow(
      uuid: serializer.fromJson<String>(json['uuid']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
      doseScheduleId: serializer.fromJson<int>(json['doseScheduleId']),
      minuteOfDay: serializer.fromJson<int>(json['minuteOfDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
      'doseScheduleId': serializer.toJson<int>(doseScheduleId),
      'minuteOfDay': serializer.toJson<int>(minuteOfDay),
    };
  }

  FixedTimingRow copyWith({
    String? uuid,
    int? updatedAtMs,
    Value<int?> syncedAtMs = const Value.absent(),
    int? doseScheduleId,
    int? minuteOfDay,
  }) => FixedTimingRow(
    uuid: uuid ?? this.uuid,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
    doseScheduleId: doseScheduleId ?? this.doseScheduleId,
    minuteOfDay: minuteOfDay ?? this.minuteOfDay,
  );
  FixedTimingRow copyWithCompanion(FixedTimingsCompanion data) {
    return FixedTimingRow(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
      doseScheduleId: data.doseScheduleId.present
          ? data.doseScheduleId.value
          : this.doseScheduleId,
      minuteOfDay: data.minuteOfDay.present
          ? data.minuteOfDay.value
          : this.minuteOfDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixedTimingRow(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('doseScheduleId: $doseScheduleId, ')
          ..write('minuteOfDay: $minuteOfDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(uuid, updatedAtMs, syncedAtMs, doseScheduleId, minuteOfDay);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixedTimingRow &&
          other.uuid == this.uuid &&
          other.updatedAtMs == this.updatedAtMs &&
          other.syncedAtMs == this.syncedAtMs &&
          other.doseScheduleId == this.doseScheduleId &&
          other.minuteOfDay == this.minuteOfDay);
}

class FixedTimingsCompanion extends UpdateCompanion<FixedTimingRow> {
  final Value<String> uuid;
  final Value<int> updatedAtMs;
  final Value<int?> syncedAtMs;
  final Value<int> doseScheduleId;
  final Value<int> minuteOfDay;
  const FixedTimingsCompanion({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.doseScheduleId = const Value.absent(),
    this.minuteOfDay = const Value.absent(),
  });
  FixedTimingsCompanion.insert({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.doseScheduleId = const Value.absent(),
    required int minuteOfDay,
  }) : minuteOfDay = Value(minuteOfDay);
  static Insertable<FixedTimingRow> custom({
    Expression<String>? uuid,
    Expression<int>? updatedAtMs,
    Expression<int>? syncedAtMs,
    Expression<int>? doseScheduleId,
    Expression<int>? minuteOfDay,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
      if (doseScheduleId != null) 'dose_schedule_id': doseScheduleId,
      if (minuteOfDay != null) 'minute_of_day': minuteOfDay,
    });
  }

  FixedTimingsCompanion copyWith({
    Value<String>? uuid,
    Value<int>? updatedAtMs,
    Value<int?>? syncedAtMs,
    Value<int>? doseScheduleId,
    Value<int>? minuteOfDay,
  }) {
    return FixedTimingsCompanion(
      uuid: uuid ?? this.uuid,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      doseScheduleId: doseScheduleId ?? this.doseScheduleId,
      minuteOfDay: minuteOfDay ?? this.minuteOfDay,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    if (doseScheduleId.present) {
      map['dose_schedule_id'] = Variable<int>(doseScheduleId.value);
    }
    if (minuteOfDay.present) {
      map['minute_of_day'] = Variable<int>(minuteOfDay.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixedTimingsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('doseScheduleId: $doseScheduleId, ')
          ..write('minuteOfDay: $minuteOfDay')
          ..write(')'))
        .toString();
  }
}

class $DoseEventsTable extends DoseEvents
    with TableInfo<$DoseEventsTable, DoseEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DoseEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncUuid,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: nowMs,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _doseScheduleIdMeta = const VerificationMeta(
    'doseScheduleId',
  );
  @override
  late final GeneratedColumn<int> doseScheduleId = GeneratedColumn<int>(
    'dose_schedule_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dose_schedules (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> routineDay =
      GeneratedColumn<String>(
        'routine_day',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DoseEventsTable.$converterroutineDay);
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DoseState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DoseState>($DoseEventsTable.$converterstate);
  static const VerificationMeta _actedAtMeta = const VerificationMeta(
    'actedAt',
  );
  @override
  late final GeneratedColumn<DateTime> actedAt = GeneratedColumn<DateTime>(
    'acted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    doseScheduleId,
    routineDay,
    scheduledAt,
    state,
    actedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dose_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<DoseEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('dose_schedule_id')) {
      context.handle(
        _doseScheduleIdMeta,
        doseScheduleId.isAcceptableOrUnknown(
          data['dose_schedule_id']!,
          _doseScheduleIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_doseScheduleIdMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('acted_at')) {
      context.handle(
        _actedAtMeta,
        actedAt.isAcceptableOrUnknown(data['acted_at']!, _actedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {doseScheduleId, routineDay},
  ];
  @override
  DoseEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DoseEventRow(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      doseScheduleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dose_schedule_id'],
      )!,
      routineDay: $DoseEventsTable.$converterroutineDay.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}routine_day'],
        )!,
      ),
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      )!,
      state: $DoseEventsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      actedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}acted_at'],
      ),
    );
  }

  @override
  $DoseEventsTable createAlias(String alias) {
    return $DoseEventsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $converterroutineDay =
      const DateOnlyConverter();
  static JsonTypeConverter2<DoseState, String, String> $converterstate =
      const EnumNameConverter<DoseState>(DoseState.values);
}

class DoseEventRow extends DataClass implements Insertable<DoseEventRow> {
  final String uuid;

  /// بتتصان من قاعدة البيانات نفسها (تريجرات في beforeOpen) — مش من نقاط
  /// النداء: اللي لازم حد يفتكره هيتنسي، والصف ده كان هيبطل يتزامن في صمت.
  final int updatedAtMs;

  /// آخر updated_at_ms اتدفع للسحابة — null يعني عمره ما اتدفع.
  final int? syncedAtMs;
  final int id;
  final int doseScheduleId;
  final DateTime routineDay;

  /// الساعة اللي كانت مستحقة فيها وقت ما الحدث اتسجّل.
  final DateTime scheduledAt;
  final DoseState state;
  final DateTime? actedAt;
  const DoseEventRow({
    required this.uuid,
    required this.updatedAtMs,
    this.syncedAtMs,
    required this.id,
    required this.doseScheduleId,
    required this.routineDay,
    required this.scheduledAt,
    required this.state,
    this.actedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    map['id'] = Variable<int>(id);
    map['dose_schedule_id'] = Variable<int>(doseScheduleId);
    {
      map['routine_day'] = Variable<String>(
        $DoseEventsTable.$converterroutineDay.toSql(routineDay),
      );
    }
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    {
      map['state'] = Variable<String>(
        $DoseEventsTable.$converterstate.toSql(state),
      );
    }
    if (!nullToAbsent || actedAt != null) {
      map['acted_at'] = Variable<DateTime>(actedAt);
    }
    return map;
  }

  DoseEventsCompanion toCompanion(bool nullToAbsent) {
    return DoseEventsCompanion(
      uuid: Value(uuid),
      updatedAtMs: Value(updatedAtMs),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
      id: Value(id),
      doseScheduleId: Value(doseScheduleId),
      routineDay: Value(routineDay),
      scheduledAt: Value(scheduledAt),
      state: Value(state),
      actedAt: actedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(actedAt),
    );
  }

  factory DoseEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DoseEventRow(
      uuid: serializer.fromJson<String>(json['uuid']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
      id: serializer.fromJson<int>(json['id']),
      doseScheduleId: serializer.fromJson<int>(json['doseScheduleId']),
      routineDay: serializer.fromJson<DateTime>(json['routineDay']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      state: $DoseEventsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      actedAt: serializer.fromJson<DateTime?>(json['actedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
      'id': serializer.toJson<int>(id),
      'doseScheduleId': serializer.toJson<int>(doseScheduleId),
      'routineDay': serializer.toJson<DateTime>(routineDay),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'state': serializer.toJson<String>(
        $DoseEventsTable.$converterstate.toJson(state),
      ),
      'actedAt': serializer.toJson<DateTime?>(actedAt),
    };
  }

  DoseEventRow copyWith({
    String? uuid,
    int? updatedAtMs,
    Value<int?> syncedAtMs = const Value.absent(),
    int? id,
    int? doseScheduleId,
    DateTime? routineDay,
    DateTime? scheduledAt,
    DoseState? state,
    Value<DateTime?> actedAt = const Value.absent(),
  }) => DoseEventRow(
    uuid: uuid ?? this.uuid,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
    id: id ?? this.id,
    doseScheduleId: doseScheduleId ?? this.doseScheduleId,
    routineDay: routineDay ?? this.routineDay,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    state: state ?? this.state,
    actedAt: actedAt.present ? actedAt.value : this.actedAt,
  );
  DoseEventRow copyWithCompanion(DoseEventsCompanion data) {
    return DoseEventRow(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
      id: data.id.present ? data.id.value : this.id,
      doseScheduleId: data.doseScheduleId.present
          ? data.doseScheduleId.value
          : this.doseScheduleId,
      routineDay: data.routineDay.present
          ? data.routineDay.value
          : this.routineDay,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      state: data.state.present ? data.state.value : this.state,
      actedAt: data.actedAt.present ? data.actedAt.value : this.actedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DoseEventRow(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('doseScheduleId: $doseScheduleId, ')
          ..write('routineDay: $routineDay, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('state: $state, ')
          ..write('actedAt: $actedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uuid,
    updatedAtMs,
    syncedAtMs,
    id,
    doseScheduleId,
    routineDay,
    scheduledAt,
    state,
    actedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DoseEventRow &&
          other.uuid == this.uuid &&
          other.updatedAtMs == this.updatedAtMs &&
          other.syncedAtMs == this.syncedAtMs &&
          other.id == this.id &&
          other.doseScheduleId == this.doseScheduleId &&
          other.routineDay == this.routineDay &&
          other.scheduledAt == this.scheduledAt &&
          other.state == this.state &&
          other.actedAt == this.actedAt);
}

class DoseEventsCompanion extends UpdateCompanion<DoseEventRow> {
  final Value<String> uuid;
  final Value<int> updatedAtMs;
  final Value<int?> syncedAtMs;
  final Value<int> id;
  final Value<int> doseScheduleId;
  final Value<DateTime> routineDay;
  final Value<DateTime> scheduledAt;
  final Value<DoseState> state;
  final Value<DateTime?> actedAt;
  const DoseEventsCompanion({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    this.doseScheduleId = const Value.absent(),
    this.routineDay = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.state = const Value.absent(),
    this.actedAt = const Value.absent(),
  });
  DoseEventsCompanion.insert({
    this.uuid = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.id = const Value.absent(),
    required int doseScheduleId,
    required DateTime routineDay,
    required DateTime scheduledAt,
    required DoseState state,
    this.actedAt = const Value.absent(),
  }) : doseScheduleId = Value(doseScheduleId),
       routineDay = Value(routineDay),
       scheduledAt = Value(scheduledAt),
       state = Value(state);
  static Insertable<DoseEventRow> custom({
    Expression<String>? uuid,
    Expression<int>? updatedAtMs,
    Expression<int>? syncedAtMs,
    Expression<int>? id,
    Expression<int>? doseScheduleId,
    Expression<String>? routineDay,
    Expression<DateTime>? scheduledAt,
    Expression<String>? state,
    Expression<DateTime>? actedAt,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
      if (id != null) 'id': id,
      if (doseScheduleId != null) 'dose_schedule_id': doseScheduleId,
      if (routineDay != null) 'routine_day': routineDay,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (state != null) 'state': state,
      if (actedAt != null) 'acted_at': actedAt,
    });
  }

  DoseEventsCompanion copyWith({
    Value<String>? uuid,
    Value<int>? updatedAtMs,
    Value<int?>? syncedAtMs,
    Value<int>? id,
    Value<int>? doseScheduleId,
    Value<DateTime>? routineDay,
    Value<DateTime>? scheduledAt,
    Value<DoseState>? state,
    Value<DateTime?>? actedAt,
  }) {
    return DoseEventsCompanion(
      uuid: uuid ?? this.uuid,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      id: id ?? this.id,
      doseScheduleId: doseScheduleId ?? this.doseScheduleId,
      routineDay: routineDay ?? this.routineDay,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      state: state ?? this.state,
      actedAt: actedAt ?? this.actedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (doseScheduleId.present) {
      map['dose_schedule_id'] = Variable<int>(doseScheduleId.value);
    }
    if (routineDay.present) {
      map['routine_day'] = Variable<String>(
        $DoseEventsTable.$converterroutineDay.toSql(routineDay.value),
      );
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $DoseEventsTable.$converterstate.toSql(state.value),
      );
    }
    if (actedAt.present) {
      map['acted_at'] = Variable<DateTime>(actedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DoseEventsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('id: $id, ')
          ..write('doseScheduleId: $doseScheduleId, ')
          ..write('routineDay: $routineDay, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('state: $state, ')
          ..write('actedAt: $actedAt')
          ..write(')'))
        .toString();
  }
}

class $RoutineBackupsTable extends RoutineBackups
    with TableInfo<$RoutineBackupsTable, RoutineBackupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoutineBackupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<int> patientId = GeneratedColumn<int>(
    'patient_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES patients (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _wakeMinutesMeta = const VerificationMeta(
    'wakeMinutes',
  );
  @override
  late final GeneratedColumn<int> wakeMinutes = GeneratedColumn<int>(
    'wake_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _breakfastMinutesMeta = const VerificationMeta(
    'breakfastMinutes',
  );
  @override
  late final GeneratedColumn<int> breakfastMinutes = GeneratedColumn<int>(
    'breakfast_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lunchMinutesMeta = const VerificationMeta(
    'lunchMinutes',
  );
  @override
  late final GeneratedColumn<int> lunchMinutes = GeneratedColumn<int>(
    'lunch_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dinnerMinutesMeta = const VerificationMeta(
    'dinnerMinutes',
  );
  @override
  late final GeneratedColumn<int> dinnerMinutes = GeneratedColumn<int>(
    'dinner_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sleepMinutesMeta = const VerificationMeta(
    'sleepMinutes',
  );
  @override
  late final GeneratedColumn<int> sleepMinutes = GeneratedColumn<int>(
    'sleep_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iftarMinutesMeta = const VerificationMeta(
    'iftarMinutes',
  );
  @override
  late final GeneratedColumn<int> iftarMinutes = GeneratedColumn<int>(
    'iftar_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _suhoorMinutesMeta = const VerificationMeta(
    'suhoorMinutes',
  );
  @override
  late final GeneratedColumn<int> suhoorMinutes = GeneratedColumn<int>(
    'suhoor_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    patientId,
    wakeMinutes,
    breakfastMinutes,
    lunchMinutes,
    dinnerMinutes,
    sleepMinutes,
    iftarMinutes,
    suhoorMinutes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'routine_backups';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoutineBackupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    }
    if (data.containsKey('wake_minutes')) {
      context.handle(
        _wakeMinutesMeta,
        wakeMinutes.isAcceptableOrUnknown(
          data['wake_minutes']!,
          _wakeMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_wakeMinutesMeta);
    }
    if (data.containsKey('breakfast_minutes')) {
      context.handle(
        _breakfastMinutesMeta,
        breakfastMinutes.isAcceptableOrUnknown(
          data['breakfast_minutes']!,
          _breakfastMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_breakfastMinutesMeta);
    }
    if (data.containsKey('lunch_minutes')) {
      context.handle(
        _lunchMinutesMeta,
        lunchMinutes.isAcceptableOrUnknown(
          data['lunch_minutes']!,
          _lunchMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lunchMinutesMeta);
    }
    if (data.containsKey('dinner_minutes')) {
      context.handle(
        _dinnerMinutesMeta,
        dinnerMinutes.isAcceptableOrUnknown(
          data['dinner_minutes']!,
          _dinnerMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dinnerMinutesMeta);
    }
    if (data.containsKey('sleep_minutes')) {
      context.handle(
        _sleepMinutesMeta,
        sleepMinutes.isAcceptableOrUnknown(
          data['sleep_minutes']!,
          _sleepMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sleepMinutesMeta);
    }
    if (data.containsKey('iftar_minutes')) {
      context.handle(
        _iftarMinutesMeta,
        iftarMinutes.isAcceptableOrUnknown(
          data['iftar_minutes']!,
          _iftarMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_iftarMinutesMeta);
    }
    if (data.containsKey('suhoor_minutes')) {
      context.handle(
        _suhoorMinutesMeta,
        suhoorMinutes.isAcceptableOrUnknown(
          data['suhoor_minutes']!,
          _suhoorMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_suhoorMinutesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {patientId};
  @override
  RoutineBackupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoutineBackupRow(
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}patient_id'],
      )!,
      wakeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wake_minutes'],
      )!,
      breakfastMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}breakfast_minutes'],
      )!,
      lunchMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lunch_minutes'],
      )!,
      dinnerMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dinner_minutes'],
      )!,
      sleepMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_minutes'],
      )!,
      iftarMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}iftar_minutes'],
      )!,
      suhoorMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}suhoor_minutes'],
      )!,
    );
  }

  @override
  $RoutineBackupsTable createAlias(String alias) {
    return $RoutineBackupsTable(attachedDatabase, alias);
  }
}

class RoutineBackupRow extends DataClass
    implements Insertable<RoutineBackupRow> {
  final int patientId;

  /// الخمس مواعيد الأصلية زي ما كانت في day_routines بالظبط.
  final int wakeMinutes;
  final int breakfastMinutes;
  final int lunchMinutes;
  final int dinnerMinutes;
  final int sleepMinutes;
  final int iftarMinutes;
  final int suhoorMinutes;
  const RoutineBackupRow({
    required this.patientId,
    required this.wakeMinutes,
    required this.breakfastMinutes,
    required this.lunchMinutes,
    required this.dinnerMinutes,
    required this.sleepMinutes,
    required this.iftarMinutes,
    required this.suhoorMinutes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['patient_id'] = Variable<int>(patientId);
    map['wake_minutes'] = Variable<int>(wakeMinutes);
    map['breakfast_minutes'] = Variable<int>(breakfastMinutes);
    map['lunch_minutes'] = Variable<int>(lunchMinutes);
    map['dinner_minutes'] = Variable<int>(dinnerMinutes);
    map['sleep_minutes'] = Variable<int>(sleepMinutes);
    map['iftar_minutes'] = Variable<int>(iftarMinutes);
    map['suhoor_minutes'] = Variable<int>(suhoorMinutes);
    return map;
  }

  RoutineBackupsCompanion toCompanion(bool nullToAbsent) {
    return RoutineBackupsCompanion(
      patientId: Value(patientId),
      wakeMinutes: Value(wakeMinutes),
      breakfastMinutes: Value(breakfastMinutes),
      lunchMinutes: Value(lunchMinutes),
      dinnerMinutes: Value(dinnerMinutes),
      sleepMinutes: Value(sleepMinutes),
      iftarMinutes: Value(iftarMinutes),
      suhoorMinutes: Value(suhoorMinutes),
    );
  }

  factory RoutineBackupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoutineBackupRow(
      patientId: serializer.fromJson<int>(json['patientId']),
      wakeMinutes: serializer.fromJson<int>(json['wakeMinutes']),
      breakfastMinutes: serializer.fromJson<int>(json['breakfastMinutes']),
      lunchMinutes: serializer.fromJson<int>(json['lunchMinutes']),
      dinnerMinutes: serializer.fromJson<int>(json['dinnerMinutes']),
      sleepMinutes: serializer.fromJson<int>(json['sleepMinutes']),
      iftarMinutes: serializer.fromJson<int>(json['iftarMinutes']),
      suhoorMinutes: serializer.fromJson<int>(json['suhoorMinutes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'patientId': serializer.toJson<int>(patientId),
      'wakeMinutes': serializer.toJson<int>(wakeMinutes),
      'breakfastMinutes': serializer.toJson<int>(breakfastMinutes),
      'lunchMinutes': serializer.toJson<int>(lunchMinutes),
      'dinnerMinutes': serializer.toJson<int>(dinnerMinutes),
      'sleepMinutes': serializer.toJson<int>(sleepMinutes),
      'iftarMinutes': serializer.toJson<int>(iftarMinutes),
      'suhoorMinutes': serializer.toJson<int>(suhoorMinutes),
    };
  }

  RoutineBackupRow copyWith({
    int? patientId,
    int? wakeMinutes,
    int? breakfastMinutes,
    int? lunchMinutes,
    int? dinnerMinutes,
    int? sleepMinutes,
    int? iftarMinutes,
    int? suhoorMinutes,
  }) => RoutineBackupRow(
    patientId: patientId ?? this.patientId,
    wakeMinutes: wakeMinutes ?? this.wakeMinutes,
    breakfastMinutes: breakfastMinutes ?? this.breakfastMinutes,
    lunchMinutes: lunchMinutes ?? this.lunchMinutes,
    dinnerMinutes: dinnerMinutes ?? this.dinnerMinutes,
    sleepMinutes: sleepMinutes ?? this.sleepMinutes,
    iftarMinutes: iftarMinutes ?? this.iftarMinutes,
    suhoorMinutes: suhoorMinutes ?? this.suhoorMinutes,
  );
  RoutineBackupRow copyWithCompanion(RoutineBackupsCompanion data) {
    return RoutineBackupRow(
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      wakeMinutes: data.wakeMinutes.present
          ? data.wakeMinutes.value
          : this.wakeMinutes,
      breakfastMinutes: data.breakfastMinutes.present
          ? data.breakfastMinutes.value
          : this.breakfastMinutes,
      lunchMinutes: data.lunchMinutes.present
          ? data.lunchMinutes.value
          : this.lunchMinutes,
      dinnerMinutes: data.dinnerMinutes.present
          ? data.dinnerMinutes.value
          : this.dinnerMinutes,
      sleepMinutes: data.sleepMinutes.present
          ? data.sleepMinutes.value
          : this.sleepMinutes,
      iftarMinutes: data.iftarMinutes.present
          ? data.iftarMinutes.value
          : this.iftarMinutes,
      suhoorMinutes: data.suhoorMinutes.present
          ? data.suhoorMinutes.value
          : this.suhoorMinutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoutineBackupRow(')
          ..write('patientId: $patientId, ')
          ..write('wakeMinutes: $wakeMinutes, ')
          ..write('breakfastMinutes: $breakfastMinutes, ')
          ..write('lunchMinutes: $lunchMinutes, ')
          ..write('dinnerMinutes: $dinnerMinutes, ')
          ..write('sleepMinutes: $sleepMinutes, ')
          ..write('iftarMinutes: $iftarMinutes, ')
          ..write('suhoorMinutes: $suhoorMinutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    patientId,
    wakeMinutes,
    breakfastMinutes,
    lunchMinutes,
    dinnerMinutes,
    sleepMinutes,
    iftarMinutes,
    suhoorMinutes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutineBackupRow &&
          other.patientId == this.patientId &&
          other.wakeMinutes == this.wakeMinutes &&
          other.breakfastMinutes == this.breakfastMinutes &&
          other.lunchMinutes == this.lunchMinutes &&
          other.dinnerMinutes == this.dinnerMinutes &&
          other.sleepMinutes == this.sleepMinutes &&
          other.iftarMinutes == this.iftarMinutes &&
          other.suhoorMinutes == this.suhoorMinutes);
}

class RoutineBackupsCompanion extends UpdateCompanion<RoutineBackupRow> {
  final Value<int> patientId;
  final Value<int> wakeMinutes;
  final Value<int> breakfastMinutes;
  final Value<int> lunchMinutes;
  final Value<int> dinnerMinutes;
  final Value<int> sleepMinutes;
  final Value<int> iftarMinutes;
  final Value<int> suhoorMinutes;
  const RoutineBackupsCompanion({
    this.patientId = const Value.absent(),
    this.wakeMinutes = const Value.absent(),
    this.breakfastMinutes = const Value.absent(),
    this.lunchMinutes = const Value.absent(),
    this.dinnerMinutes = const Value.absent(),
    this.sleepMinutes = const Value.absent(),
    this.iftarMinutes = const Value.absent(),
    this.suhoorMinutes = const Value.absent(),
  });
  RoutineBackupsCompanion.insert({
    this.patientId = const Value.absent(),
    required int wakeMinutes,
    required int breakfastMinutes,
    required int lunchMinutes,
    required int dinnerMinutes,
    required int sleepMinutes,
    required int iftarMinutes,
    required int suhoorMinutes,
  }) : wakeMinutes = Value(wakeMinutes),
       breakfastMinutes = Value(breakfastMinutes),
       lunchMinutes = Value(lunchMinutes),
       dinnerMinutes = Value(dinnerMinutes),
       sleepMinutes = Value(sleepMinutes),
       iftarMinutes = Value(iftarMinutes),
       suhoorMinutes = Value(suhoorMinutes);
  static Insertable<RoutineBackupRow> custom({
    Expression<int>? patientId,
    Expression<int>? wakeMinutes,
    Expression<int>? breakfastMinutes,
    Expression<int>? lunchMinutes,
    Expression<int>? dinnerMinutes,
    Expression<int>? sleepMinutes,
    Expression<int>? iftarMinutes,
    Expression<int>? suhoorMinutes,
  }) {
    return RawValuesInsertable({
      if (patientId != null) 'patient_id': patientId,
      if (wakeMinutes != null) 'wake_minutes': wakeMinutes,
      if (breakfastMinutes != null) 'breakfast_minutes': breakfastMinutes,
      if (lunchMinutes != null) 'lunch_minutes': lunchMinutes,
      if (dinnerMinutes != null) 'dinner_minutes': dinnerMinutes,
      if (sleepMinutes != null) 'sleep_minutes': sleepMinutes,
      if (iftarMinutes != null) 'iftar_minutes': iftarMinutes,
      if (suhoorMinutes != null) 'suhoor_minutes': suhoorMinutes,
    });
  }

  RoutineBackupsCompanion copyWith({
    Value<int>? patientId,
    Value<int>? wakeMinutes,
    Value<int>? breakfastMinutes,
    Value<int>? lunchMinutes,
    Value<int>? dinnerMinutes,
    Value<int>? sleepMinutes,
    Value<int>? iftarMinutes,
    Value<int>? suhoorMinutes,
  }) {
    return RoutineBackupsCompanion(
      patientId: patientId ?? this.patientId,
      wakeMinutes: wakeMinutes ?? this.wakeMinutes,
      breakfastMinutes: breakfastMinutes ?? this.breakfastMinutes,
      lunchMinutes: lunchMinutes ?? this.lunchMinutes,
      dinnerMinutes: dinnerMinutes ?? this.dinnerMinutes,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      iftarMinutes: iftarMinutes ?? this.iftarMinutes,
      suhoorMinutes: suhoorMinutes ?? this.suhoorMinutes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (patientId.present) {
      map['patient_id'] = Variable<int>(patientId.value);
    }
    if (wakeMinutes.present) {
      map['wake_minutes'] = Variable<int>(wakeMinutes.value);
    }
    if (breakfastMinutes.present) {
      map['breakfast_minutes'] = Variable<int>(breakfastMinutes.value);
    }
    if (lunchMinutes.present) {
      map['lunch_minutes'] = Variable<int>(lunchMinutes.value);
    }
    if (dinnerMinutes.present) {
      map['dinner_minutes'] = Variable<int>(dinnerMinutes.value);
    }
    if (sleepMinutes.present) {
      map['sleep_minutes'] = Variable<int>(sleepMinutes.value);
    }
    if (iftarMinutes.present) {
      map['iftar_minutes'] = Variable<int>(iftarMinutes.value);
    }
    if (suhoorMinutes.present) {
      map['suhoor_minutes'] = Variable<int>(suhoorMinutes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutineBackupsCompanion(')
          ..write('patientId: $patientId, ')
          ..write('wakeMinutes: $wakeMinutes, ')
          ..write('breakfastMinutes: $breakfastMinutes, ')
          ..write('lunchMinutes: $lunchMinutes, ')
          ..write('dinnerMinutes: $dinnerMinutes, ')
          ..write('sleepMinutes: $sleepMinutes, ')
          ..write('iftarMinutes: $iftarMinutes, ')
          ..write('suhoorMinutes: $suhoorMinutes')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PatientsTable patients = $PatientsTable(this);
  late final $DayRoutinesTable dayRoutines = $DayRoutinesTable(this);
  late final $MedicationsTable medications = $MedicationsTable(this);
  late final $DoseSchedulesTable doseSchedules = $DoseSchedulesTable(this);
  late final $FixedTimingsTable fixedTimings = $FixedTimingsTable(this);
  late final $DoseEventsTable doseEvents = $DoseEventsTable(this);
  late final $RoutineBackupsTable routineBackups = $RoutineBackupsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    patients,
    dayRoutines,
    medications,
    doseSchedules,
    fixedTimings,
    doseEvents,
    routineBackups,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'patients',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('day_routines', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'patients',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('medications', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'medications',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dose_schedules', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dose_schedules',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('fixed_timings', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'dose_schedules',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dose_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'patients',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('routine_backups', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$PatientsTableCreateCompanionBuilder = PatientsCompanion Function({
  Value<String> uuid,
  Value<int> updatedAtMs,
  Value<int?> syncedAtMs,
  Value<int> id,
  required String name,
  Value<int> notificationSlot,
  Value<DateTime> createdAt,
});
typedef $$PatientsTableUpdateCompanionBuilder = PatientsCompanion Function({
  Value<String> uuid,
  Value<int> updatedAtMs,
  Value<int?> syncedAtMs,
  Value<int> id,
  Value<String> name,
  Value<int> notificationSlot,
  Value<DateTime> createdAt,
});

final class $$PatientsTableReferences
    extends BaseReferences<_$AppDatabase, $PatientsTable, PatientRow> {
  $$PatientsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DayRoutinesTable, List<DayRoutineRow>>
  _dayRoutinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.dayRoutines,
    aliasName: 'patients__id__day_routines__patient_id',
  );

  $$DayRoutinesTableProcessedTableManager get dayRoutinesRefs {
    final manager = $$DayRoutinesTableTableManager(
      $_db,
      $_db.dayRoutines,
    ).filter((f) => f.patientId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_dayRoutinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MedicationsTable, List<MedicationRow>>
  _medicationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.medications,
    aliasName: 'patients__id__medications__patient_id',
  );

  $$MedicationsTableProcessedTableManager get medicationsRefs {
    final manager = $$MedicationsTableTableManager(
      $_db,
      $_db.medications,
    ).filter((f) => f.patientId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_medicationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RoutineBackupsTable, List<RoutineBackupRow>>
  _routineBackupsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.routineBackups,
    aliasName: 'patients__id__routine_backups__patient_id',
  );

  $$RoutineBackupsTableProcessedTableManager get routineBackupsRefs {
    final manager = $$RoutineBackupsTableTableManager(
      $_db,
      $_db.routineBackups,
    ).filter((f) => f.patientId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_routineBackupsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PatientsTableFilterComposer
    extends Composer<_$AppDatabase, $PatientsTable> {
  $$PatientsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notificationSlot => $composableBuilder(
    column: $table.notificationSlot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> dayRoutinesRefs(
    Expression<bool> Function($$DayRoutinesTableFilterComposer f) f,
  ) {
    final $$DayRoutinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayRoutines,
      getReferencedColumn: (t) => t.patientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayRoutinesTableFilterComposer(
            $db: $db,
            $table: $db.dayRoutines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> medicationsRefs(
    Expression<bool> Function($$MedicationsTableFilterComposer f) f,
  ) {
    final $$MedicationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.medications,
      getReferencedColumn: (t) => t.patientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicationsTableFilterComposer(
            $db: $db,
            $table: $db.medications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> routineBackupsRefs(
    Expression<bool> Function($$RoutineBackupsTableFilterComposer f) f,
  ) {
    final $$RoutineBackupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.routineBackups,
      getReferencedColumn: (t) => t.patientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoutineBackupsTableFilterComposer(
            $db: $db,
            $table: $db.routineBackups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PatientsTableOrderingComposer
    extends Composer<_$AppDatabase, $PatientsTable> {
  $$PatientsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notificationSlot => $composableBuilder(
    column: $table.notificationSlot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PatientsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PatientsTable> {
  $$PatientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get notificationSlot => $composableBuilder(
    column: $table.notificationSlot,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> dayRoutinesRefs<T extends Object>(
    Expression<T> Function($$DayRoutinesTableAnnotationComposer a) f,
  ) {
    final $$DayRoutinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayRoutines,
      getReferencedColumn: (t) => t.patientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayRoutinesTableAnnotationComposer(
            $db: $db,
            $table: $db.dayRoutines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> medicationsRefs<T extends Object>(
    Expression<T> Function($$MedicationsTableAnnotationComposer a) f,
  ) {
    final $$MedicationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.medications,
      getReferencedColumn: (t) => t.patientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicationsTableAnnotationComposer(
            $db: $db,
            $table: $db.medications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> routineBackupsRefs<T extends Object>(
    Expression<T> Function($$RoutineBackupsTableAnnotationComposer a) f,
  ) {
    final $$RoutineBackupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.routineBackups,
      getReferencedColumn: (t) => t.patientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoutineBackupsTableAnnotationComposer(
            $db: $db,
            $table: $db.routineBackups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PatientsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PatientsTable,
          PatientRow,
          $$PatientsTableFilterComposer,
          $$PatientsTableOrderingComposer,
          $$PatientsTableAnnotationComposer,
          $$PatientsTableCreateCompanionBuilder,
          $$PatientsTableUpdateCompanionBuilder,
          (PatientRow, $$PatientsTableReferences),
          PatientRow,
          PrefetchHooks Function({
            bool dayRoutinesRefs,
            bool medicationsRefs,
            bool routineBackupsRefs,
          })
        > {
  $$PatientsTableTableManager(_$AppDatabase db, $PatientsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PatientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PatientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PatientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> notificationSlot = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PatientsCompanion(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                name: name,
                notificationSlot: notificationSlot,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                required String name,
                Value<int> notificationSlot = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PatientsCompanion.insert(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                name: name,
                notificationSlot: notificationSlot,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PatientsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                dayRoutinesRefs = false,
                medicationsRefs = false,
                routineBackupsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dayRoutinesRefs) db.dayRoutines,
                    if (medicationsRefs) db.medications,
                    if (routineBackupsRefs) db.routineBackups,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dayRoutinesRefs)
                        await $_getPrefetchedData<
                          PatientRow,
                          $PatientsTable,
                          DayRoutineRow
                        >(
                          currentTable: table,
                          referencedTable: $$PatientsTableReferences
                              ._dayRoutinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PatientsTableReferences(
                                db,
                                table,
                                p0,
                              ).dayRoutinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.patientId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (medicationsRefs)
                        await $_getPrefetchedData<
                          PatientRow,
                          $PatientsTable,
                          MedicationRow
                        >(
                          currentTable: table,
                          referencedTable: $$PatientsTableReferences
                              ._medicationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PatientsTableReferences(
                                db,
                                table,
                                p0,
                              ).medicationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.patientId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (routineBackupsRefs)
                        await $_getPrefetchedData<
                          PatientRow,
                          $PatientsTable,
                          RoutineBackupRow
                        >(
                          currentTable: table,
                          referencedTable: $$PatientsTableReferences
                              ._routineBackupsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PatientsTableReferences(
                                db,
                                table,
                                p0,
                              ).routineBackupsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.patientId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PatientsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PatientsTable,
      PatientRow,
      $$PatientsTableFilterComposer,
      $$PatientsTableOrderingComposer,
      $$PatientsTableAnnotationComposer,
      $$PatientsTableCreateCompanionBuilder,
      $$PatientsTableUpdateCompanionBuilder,
      (PatientRow, $$PatientsTableReferences),
      PatientRow,
      PrefetchHooks Function({
        bool dayRoutinesRefs,
        bool medicationsRefs,
        bool routineBackupsRefs,
      })
    >;
typedef $$DayRoutinesTableCreateCompanionBuilder =
    DayRoutinesCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> id,
      required int patientId,
      required int wakeMinutes,
      required int breakfastMinutes,
      required int lunchMinutes,
      required int dinnerMinutes,
      required int sleepMinutes,
      Value<DateTime> updatedAt,
    });
typedef $$DayRoutinesTableUpdateCompanionBuilder =
    DayRoutinesCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> id,
      Value<int> patientId,
      Value<int> wakeMinutes,
      Value<int> breakfastMinutes,
      Value<int> lunchMinutes,
      Value<int> dinnerMinutes,
      Value<int> sleepMinutes,
      Value<DateTime> updatedAt,
    });

final class $$DayRoutinesTableReferences
    extends BaseReferences<_$AppDatabase, $DayRoutinesTable, DayRoutineRow> {
  $$DayRoutinesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PatientsTable _patientIdTable(_$AppDatabase db) =>
      db.patients.createAlias('day_routines__patient_id__patients__id');

  $$PatientsTableProcessedTableManager get patientId {
    final $_column = $_itemColumn<int>('patient_id')!;

    final manager = $$PatientsTableTableManager(
      $_db,
      $_db.patients,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_patientIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DayRoutinesTableFilterComposer
    extends Composer<_$AppDatabase, $DayRoutinesTable> {
  $$DayRoutinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wakeMinutes => $composableBuilder(
    column: $table.wakeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get breakfastMinutes => $composableBuilder(
    column: $table.breakfastMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lunchMinutes => $composableBuilder(
    column: $table.lunchMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dinnerMinutes => $composableBuilder(
    column: $table.dinnerMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepMinutes => $composableBuilder(
    column: $table.sleepMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PatientsTableFilterComposer get patientId {
    final $$PatientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableFilterComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayRoutinesTableOrderingComposer
    extends Composer<_$AppDatabase, $DayRoutinesTable> {
  $$DayRoutinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wakeMinutes => $composableBuilder(
    column: $table.wakeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get breakfastMinutes => $composableBuilder(
    column: $table.breakfastMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lunchMinutes => $composableBuilder(
    column: $table.lunchMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dinnerMinutes => $composableBuilder(
    column: $table.dinnerMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepMinutes => $composableBuilder(
    column: $table.sleepMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PatientsTableOrderingComposer get patientId {
    final $$PatientsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableOrderingComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayRoutinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DayRoutinesTable> {
  $$DayRoutinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get wakeMinutes => $composableBuilder(
    column: $table.wakeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get breakfastMinutes => $composableBuilder(
    column: $table.breakfastMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lunchMinutes => $composableBuilder(
    column: $table.lunchMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dinnerMinutes => $composableBuilder(
    column: $table.dinnerMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sleepMinutes => $composableBuilder(
    column: $table.sleepMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PatientsTableAnnotationComposer get patientId {
    final $$PatientsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableAnnotationComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayRoutinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DayRoutinesTable,
          DayRoutineRow,
          $$DayRoutinesTableFilterComposer,
          $$DayRoutinesTableOrderingComposer,
          $$DayRoutinesTableAnnotationComposer,
          $$DayRoutinesTableCreateCompanionBuilder,
          $$DayRoutinesTableUpdateCompanionBuilder,
          (DayRoutineRow, $$DayRoutinesTableReferences),
          DayRoutineRow,
          PrefetchHooks Function({bool patientId})
        > {
  $$DayRoutinesTableTableManager(_$AppDatabase db, $DayRoutinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayRoutinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayRoutinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DayRoutinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<int> patientId = const Value.absent(),
                Value<int> wakeMinutes = const Value.absent(),
                Value<int> breakfastMinutes = const Value.absent(),
                Value<int> lunchMinutes = const Value.absent(),
                Value<int> dinnerMinutes = const Value.absent(),
                Value<int> sleepMinutes = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DayRoutinesCompanion(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                patientId: patientId,
                wakeMinutes: wakeMinutes,
                breakfastMinutes: breakfastMinutes,
                lunchMinutes: lunchMinutes,
                dinnerMinutes: dinnerMinutes,
                sleepMinutes: sleepMinutes,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                required int patientId,
                required int wakeMinutes,
                required int breakfastMinutes,
                required int lunchMinutes,
                required int dinnerMinutes,
                required int sleepMinutes,
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DayRoutinesCompanion.insert(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                patientId: patientId,
                wakeMinutes: wakeMinutes,
                breakfastMinutes: breakfastMinutes,
                lunchMinutes: lunchMinutes,
                dinnerMinutes: dinnerMinutes,
                sleepMinutes: sleepMinutes,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DayRoutinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({patientId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (patientId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.patientId,
                        referencedTable: $$DayRoutinesTableReferences
                            ._patientIdTable(db),
                        referencedColumn: $$DayRoutinesTableReferences
                            ._patientIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DayRoutinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DayRoutinesTable,
      DayRoutineRow,
      $$DayRoutinesTableFilterComposer,
      $$DayRoutinesTableOrderingComposer,
      $$DayRoutinesTableAnnotationComposer,
      $$DayRoutinesTableCreateCompanionBuilder,
      $$DayRoutinesTableUpdateCompanionBuilder,
      (DayRoutineRow, $$DayRoutinesTableReferences),
      DayRoutineRow,
      PrefetchHooks Function({bool patientId})
    >;
typedef $$MedicationsTableCreateCompanionBuilder =
    MedicationsCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> id,
      required int patientId,
      required String name,
      Value<String?> amountLabel,
      Value<bool> amountUnknown,
      Value<String?> notes,
      Value<DateTime?> stoppedAt,
      Value<DateTime> createdAt,
    });
typedef $$MedicationsTableUpdateCompanionBuilder =
    MedicationsCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> id,
      Value<int> patientId,
      Value<String> name,
      Value<String?> amountLabel,
      Value<bool> amountUnknown,
      Value<String?> notes,
      Value<DateTime?> stoppedAt,
      Value<DateTime> createdAt,
    });

final class $$MedicationsTableReferences
    extends BaseReferences<_$AppDatabase, $MedicationsTable, MedicationRow> {
  $$MedicationsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PatientsTable _patientIdTable(_$AppDatabase db) =>
      db.patients.createAlias('medications__patient_id__patients__id');

  $$PatientsTableProcessedTableManager get patientId {
    final $_column = $_itemColumn<int>('patient_id')!;

    final manager = $$PatientsTableTableManager(
      $_db,
      $_db.patients,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_patientIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DoseSchedulesTable, List<DoseScheduleRow>>
  _doseSchedulesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.doseSchedules,
    aliasName: 'medications__id__dose_schedules__medication_id',
  );

  $$DoseSchedulesTableProcessedTableManager get doseSchedulesRefs {
    final manager = $$DoseSchedulesTableTableManager(
      $_db,
      $_db.doseSchedules,
    ).filter((f) => f.medicationId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_doseSchedulesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MedicationsTableFilterComposer
    extends Composer<_$AppDatabase, $MedicationsTable> {
  $$MedicationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountLabel => $composableBuilder(
    column: $table.amountLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get amountUnknown => $composableBuilder(
    column: $table.amountUnknown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get stoppedAt => $composableBuilder(
    column: $table.stoppedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PatientsTableFilterComposer get patientId {
    final $$PatientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableFilterComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> doseSchedulesRefs(
    Expression<bool> Function($$DoseSchedulesTableFilterComposer f) f,
  ) {
    final $$DoseSchedulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.medicationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableFilterComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MedicationsTableOrderingComposer
    extends Composer<_$AppDatabase, $MedicationsTable> {
  $$MedicationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountLabel => $composableBuilder(
    column: $table.amountLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get amountUnknown => $composableBuilder(
    column: $table.amountUnknown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get stoppedAt => $composableBuilder(
    column: $table.stoppedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PatientsTableOrderingComposer get patientId {
    final $$PatientsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableOrderingComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MedicationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MedicationsTable> {
  $$MedicationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get amountLabel => $composableBuilder(
    column: $table.amountLabel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get amountUnknown => $composableBuilder(
    column: $table.amountUnknown,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get stoppedAt =>
      $composableBuilder(column: $table.stoppedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PatientsTableAnnotationComposer get patientId {
    final $$PatientsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableAnnotationComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> doseSchedulesRefs<T extends Object>(
    Expression<T> Function($$DoseSchedulesTableAnnotationComposer a) f,
  ) {
    final $$DoseSchedulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.medicationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableAnnotationComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MedicationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MedicationsTable,
          MedicationRow,
          $$MedicationsTableFilterComposer,
          $$MedicationsTableOrderingComposer,
          $$MedicationsTableAnnotationComposer,
          $$MedicationsTableCreateCompanionBuilder,
          $$MedicationsTableUpdateCompanionBuilder,
          (MedicationRow, $$MedicationsTableReferences),
          MedicationRow,
          PrefetchHooks Function({bool patientId, bool doseSchedulesRefs})
        > {
  $$MedicationsTableTableManager(_$AppDatabase db, $MedicationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MedicationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MedicationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MedicationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<int> patientId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> amountLabel = const Value.absent(),
                Value<bool> amountUnknown = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> stoppedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MedicationsCompanion(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                patientId: patientId,
                name: name,
                amountLabel: amountLabel,
                amountUnknown: amountUnknown,
                notes: notes,
                stoppedAt: stoppedAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                required int patientId,
                required String name,
                Value<String?> amountLabel = const Value.absent(),
                Value<bool> amountUnknown = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> stoppedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MedicationsCompanion.insert(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                patientId: patientId,
                name: name,
                amountLabel: amountLabel,
                amountUnknown: amountUnknown,
                notes: notes,
                stoppedAt: stoppedAt,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MedicationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({patientId = false, doseSchedulesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (doseSchedulesRefs) db.doseSchedules,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (patientId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.patientId,
                            referencedTable: $$MedicationsTableReferences
                                ._patientIdTable(db),
                            referencedColumn: $$MedicationsTableReferences
                                ._patientIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (doseSchedulesRefs)
                        await $_getPrefetchedData<
                          MedicationRow,
                          $MedicationsTable,
                          DoseScheduleRow
                        >(
                          currentTable: table,
                          referencedTable: $$MedicationsTableReferences
                              ._doseSchedulesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MedicationsTableReferences(
                                db,
                                table,
                                p0,
                              ).doseSchedulesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.medicationId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MedicationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MedicationsTable,
      MedicationRow,
      $$MedicationsTableFilterComposer,
      $$MedicationsTableOrderingComposer,
      $$MedicationsTableAnnotationComposer,
      $$MedicationsTableCreateCompanionBuilder,
      $$MedicationsTableUpdateCompanionBuilder,
      (MedicationRow, $$MedicationsTableReferences),
      MedicationRow,
      PrefetchHooks Function({bool patientId, bool doseSchedulesRefs})
    >;
typedef $$DoseSchedulesTableCreateCompanionBuilder =
    DoseSchedulesCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> id,
      required int medicationId,
      Value<DoseTimingKind> timingKind,
      Value<DayAnchor?> anchor,
      Value<int?> offsetMinutes,
      required DoseRepeat repeat,
      required DateTime startDate,
      Value<int?> durationDays,
    });
typedef $$DoseSchedulesTableUpdateCompanionBuilder =
    DoseSchedulesCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> id,
      Value<int> medicationId,
      Value<DoseTimingKind> timingKind,
      Value<DayAnchor?> anchor,
      Value<int?> offsetMinutes,
      Value<DoseRepeat> repeat,
      Value<DateTime> startDate,
      Value<int?> durationDays,
    });

final class $$DoseSchedulesTableReferences
    extends
        BaseReferences<_$AppDatabase, $DoseSchedulesTable, DoseScheduleRow> {
  $$DoseSchedulesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MedicationsTable _medicationIdTable(_$AppDatabase db) => db
      .medications
      .createAlias('dose_schedules__medication_id__medications__id');

  $$MedicationsTableProcessedTableManager get medicationId {
    final $_column = $_itemColumn<int>('medication_id')!;

    final manager = $$MedicationsTableTableManager(
      $_db,
      $_db.medications,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_medicationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$FixedTimingsTable, List<FixedTimingRow>>
  _fixedTimingsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.fixedTimings,
    aliasName: 'dose_schedules__id__fixed_timings__dose_schedule_id',
  );

  $$FixedTimingsTableProcessedTableManager get fixedTimingsRefs {
    final manager = $$FixedTimingsTableTableManager(
      $_db,
      $_db.fixedTimings,
    ).filter((f) => f.doseScheduleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_fixedTimingsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DoseEventsTable, List<DoseEventRow>>
  _doseEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.doseEvents,
    aliasName: 'dose_schedules__id__dose_events__dose_schedule_id',
  );

  $$DoseEventsTableProcessedTableManager get doseEventsRefs {
    final manager = $$DoseEventsTableTableManager(
      $_db,
      $_db.doseEvents,
    ).filter((f) => f.doseScheduleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_doseEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DoseSchedulesTableFilterComposer
    extends Composer<_$AppDatabase, $DoseSchedulesTable> {
  $$DoseSchedulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DoseTimingKind, DoseTimingKind, String>
  get timingKind => $composableBuilder(
    column: $table.timingKind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DayAnchor?, DayAnchor, String> get anchor =>
      $composableBuilder(
        column: $table.anchor,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get offsetMinutes => $composableBuilder(
    column: $table.offsetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DoseRepeat, DoseRepeat, String> get repeat =>
      $composableBuilder(
        column: $table.repeat,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get startDate =>
      $composableBuilder(
        column: $table.startDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get durationDays => $composableBuilder(
    column: $table.durationDays,
    builder: (column) => ColumnFilters(column),
  );

  $$MedicationsTableFilterComposer get medicationId {
    final $$MedicationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.medicationId,
      referencedTable: $db.medications,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicationsTableFilterComposer(
            $db: $db,
            $table: $db.medications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> fixedTimingsRefs(
    Expression<bool> Function($$FixedTimingsTableFilterComposer f) f,
  ) {
    final $$FixedTimingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fixedTimings,
      getReferencedColumn: (t) => t.doseScheduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FixedTimingsTableFilterComposer(
            $db: $db,
            $table: $db.fixedTimings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> doseEventsRefs(
    Expression<bool> Function($$DoseEventsTableFilterComposer f) f,
  ) {
    final $$DoseEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.doseEvents,
      getReferencedColumn: (t) => t.doseScheduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseEventsTableFilterComposer(
            $db: $db,
            $table: $db.doseEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DoseSchedulesTableOrderingComposer
    extends Composer<_$AppDatabase, $DoseSchedulesTable> {
  $$DoseSchedulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timingKind => $composableBuilder(
    column: $table.timingKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get anchor => $composableBuilder(
    column: $table.anchor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offsetMinutes => $composableBuilder(
    column: $table.offsetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeat => $composableBuilder(
    column: $table.repeat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationDays => $composableBuilder(
    column: $table.durationDays,
    builder: (column) => ColumnOrderings(column),
  );

  $$MedicationsTableOrderingComposer get medicationId {
    final $$MedicationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.medicationId,
      referencedTable: $db.medications,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicationsTableOrderingComposer(
            $db: $db,
            $table: $db.medications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DoseSchedulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DoseSchedulesTable> {
  $$DoseSchedulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DoseTimingKind, String> get timingKind =>
      $composableBuilder(
        column: $table.timingKind,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DayAnchor?, String> get anchor =>
      $composableBuilder(column: $table.anchor, builder: (column) => column);

  GeneratedColumn<int> get offsetMinutes => $composableBuilder(
    column: $table.offsetMinutes,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DoseRepeat, String> get repeat =>
      $composableBuilder(column: $table.repeat, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<int> get durationDays => $composableBuilder(
    column: $table.durationDays,
    builder: (column) => column,
  );

  $$MedicationsTableAnnotationComposer get medicationId {
    final $$MedicationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.medicationId,
      referencedTable: $db.medications,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicationsTableAnnotationComposer(
            $db: $db,
            $table: $db.medications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> fixedTimingsRefs<T extends Object>(
    Expression<T> Function($$FixedTimingsTableAnnotationComposer a) f,
  ) {
    final $$FixedTimingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fixedTimings,
      getReferencedColumn: (t) => t.doseScheduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FixedTimingsTableAnnotationComposer(
            $db: $db,
            $table: $db.fixedTimings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> doseEventsRefs<T extends Object>(
    Expression<T> Function($$DoseEventsTableAnnotationComposer a) f,
  ) {
    final $$DoseEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.doseEvents,
      getReferencedColumn: (t) => t.doseScheduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.doseEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DoseSchedulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DoseSchedulesTable,
          DoseScheduleRow,
          $$DoseSchedulesTableFilterComposer,
          $$DoseSchedulesTableOrderingComposer,
          $$DoseSchedulesTableAnnotationComposer,
          $$DoseSchedulesTableCreateCompanionBuilder,
          $$DoseSchedulesTableUpdateCompanionBuilder,
          (DoseScheduleRow, $$DoseSchedulesTableReferences),
          DoseScheduleRow,
          PrefetchHooks Function({
            bool medicationId,
            bool fixedTimingsRefs,
            bool doseEventsRefs,
          })
        > {
  $$DoseSchedulesTableTableManager(_$AppDatabase db, $DoseSchedulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DoseSchedulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DoseSchedulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DoseSchedulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<int> medicationId = const Value.absent(),
                Value<DoseTimingKind> timingKind = const Value.absent(),
                Value<DayAnchor?> anchor = const Value.absent(),
                Value<int?> offsetMinutes = const Value.absent(),
                Value<DoseRepeat> repeat = const Value.absent(),
                Value<DateTime> startDate = const Value.absent(),
                Value<int?> durationDays = const Value.absent(),
              }) => DoseSchedulesCompanion(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                medicationId: medicationId,
                timingKind: timingKind,
                anchor: anchor,
                offsetMinutes: offsetMinutes,
                repeat: repeat,
                startDate: startDate,
                durationDays: durationDays,
              ),
          createCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                required int medicationId,
                Value<DoseTimingKind> timingKind = const Value.absent(),
                Value<DayAnchor?> anchor = const Value.absent(),
                Value<int?> offsetMinutes = const Value.absent(),
                required DoseRepeat repeat,
                required DateTime startDate,
                Value<int?> durationDays = const Value.absent(),
              }) => DoseSchedulesCompanion.insert(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                medicationId: medicationId,
                timingKind: timingKind,
                anchor: anchor,
                offsetMinutes: offsetMinutes,
                repeat: repeat,
                startDate: startDate,
                durationDays: durationDays,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DoseSchedulesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                medicationId = false,
                fixedTimingsRefs = false,
                doseEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (fixedTimingsRefs) db.fixedTimings,
                    if (doseEventsRefs) db.doseEvents,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (medicationId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.medicationId,
                            referencedTable: $$DoseSchedulesTableReferences
                                ._medicationIdTable(db),
                            referencedColumn: $$DoseSchedulesTableReferences
                                ._medicationIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (fixedTimingsRefs)
                        await $_getPrefetchedData<
                          DoseScheduleRow,
                          $DoseSchedulesTable,
                          FixedTimingRow
                        >(
                          currentTable: table,
                          referencedTable: $$DoseSchedulesTableReferences
                              ._fixedTimingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DoseSchedulesTableReferences(
                                db,
                                table,
                                p0,
                              ).fixedTimingsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.doseScheduleId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (doseEventsRefs)
                        await $_getPrefetchedData<
                          DoseScheduleRow,
                          $DoseSchedulesTable,
                          DoseEventRow
                        >(
                          currentTable: table,
                          referencedTable: $$DoseSchedulesTableReferences
                              ._doseEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DoseSchedulesTableReferences(
                                db,
                                table,
                                p0,
                              ).doseEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.doseScheduleId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DoseSchedulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DoseSchedulesTable,
      DoseScheduleRow,
      $$DoseSchedulesTableFilterComposer,
      $$DoseSchedulesTableOrderingComposer,
      $$DoseSchedulesTableAnnotationComposer,
      $$DoseSchedulesTableCreateCompanionBuilder,
      $$DoseSchedulesTableUpdateCompanionBuilder,
      (DoseScheduleRow, $$DoseSchedulesTableReferences),
      DoseScheduleRow,
      PrefetchHooks Function({
        bool medicationId,
        bool fixedTimingsRefs,
        bool doseEventsRefs,
      })
    >;
typedef $$FixedTimingsTableCreateCompanionBuilder =
    FixedTimingsCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> doseScheduleId,
      required int minuteOfDay,
    });
typedef $$FixedTimingsTableUpdateCompanionBuilder =
    FixedTimingsCompanion Function({
      Value<String> uuid,
      Value<int> updatedAtMs,
      Value<int?> syncedAtMs,
      Value<int> doseScheduleId,
      Value<int> minuteOfDay,
    });

final class $$FixedTimingsTableReferences
    extends BaseReferences<_$AppDatabase, $FixedTimingsTable, FixedTimingRow> {
  $$FixedTimingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DoseSchedulesTable _doseScheduleIdTable(_$AppDatabase db) => db
      .doseSchedules
      .createAlias('fixed_timings__dose_schedule_id__dose_schedules__id');

  $$DoseSchedulesTableProcessedTableManager get doseScheduleId {
    final $_column = $_itemColumn<int>('dose_schedule_id')!;

    final manager = $$DoseSchedulesTableTableManager(
      $_db,
      $_db.doseSchedules,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_doseScheduleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FixedTimingsTableFilterComposer
    extends Composer<_$AppDatabase, $FixedTimingsTable> {
  $$FixedTimingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minuteOfDay => $composableBuilder(
    column: $table.minuteOfDay,
    builder: (column) => ColumnFilters(column),
  );

  $$DoseSchedulesTableFilterComposer get doseScheduleId {
    final $$DoseSchedulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.doseScheduleId,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableFilterComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FixedTimingsTableOrderingComposer
    extends Composer<_$AppDatabase, $FixedTimingsTable> {
  $$FixedTimingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minuteOfDay => $composableBuilder(
    column: $table.minuteOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  $$DoseSchedulesTableOrderingComposer get doseScheduleId {
    final $$DoseSchedulesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.doseScheduleId,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableOrderingComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FixedTimingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FixedTimingsTable> {
  $$FixedTimingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minuteOfDay => $composableBuilder(
    column: $table.minuteOfDay,
    builder: (column) => column,
  );

  $$DoseSchedulesTableAnnotationComposer get doseScheduleId {
    final $$DoseSchedulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.doseScheduleId,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableAnnotationComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FixedTimingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FixedTimingsTable,
          FixedTimingRow,
          $$FixedTimingsTableFilterComposer,
          $$FixedTimingsTableOrderingComposer,
          $$FixedTimingsTableAnnotationComposer,
          $$FixedTimingsTableCreateCompanionBuilder,
          $$FixedTimingsTableUpdateCompanionBuilder,
          (FixedTimingRow, $$FixedTimingsTableReferences),
          FixedTimingRow,
          PrefetchHooks Function({bool doseScheduleId})
        > {
  $$FixedTimingsTableTableManager(_$AppDatabase db, $FixedTimingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixedTimingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixedTimingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixedTimingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> doseScheduleId = const Value.absent(),
                Value<int> minuteOfDay = const Value.absent(),
              }) => FixedTimingsCompanion(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                doseScheduleId: doseScheduleId,
                minuteOfDay: minuteOfDay,
              ),
          createCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> doseScheduleId = const Value.absent(),
                required int minuteOfDay,
              }) => FixedTimingsCompanion.insert(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                doseScheduleId: doseScheduleId,
                minuteOfDay: minuteOfDay,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FixedTimingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({doseScheduleId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (doseScheduleId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.doseScheduleId,
                        referencedTable: $$FixedTimingsTableReferences
                            ._doseScheduleIdTable(db),
                        referencedColumn: $$FixedTimingsTableReferences
                            ._doseScheduleIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FixedTimingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FixedTimingsTable,
      FixedTimingRow,
      $$FixedTimingsTableFilterComposer,
      $$FixedTimingsTableOrderingComposer,
      $$FixedTimingsTableAnnotationComposer,
      $$FixedTimingsTableCreateCompanionBuilder,
      $$FixedTimingsTableUpdateCompanionBuilder,
      (FixedTimingRow, $$FixedTimingsTableReferences),
      FixedTimingRow,
      PrefetchHooks Function({bool doseScheduleId})
    >;
typedef $$DoseEventsTableCreateCompanionBuilder = DoseEventsCompanion Function({
  Value<String> uuid,
  Value<int> updatedAtMs,
  Value<int?> syncedAtMs,
  Value<int> id,
  required int doseScheduleId,
  required DateTime routineDay,
  required DateTime scheduledAt,
  required DoseState state,
  Value<DateTime?> actedAt,
});
typedef $$DoseEventsTableUpdateCompanionBuilder = DoseEventsCompanion Function({
  Value<String> uuid,
  Value<int> updatedAtMs,
  Value<int?> syncedAtMs,
  Value<int> id,
  Value<int> doseScheduleId,
  Value<DateTime> routineDay,
  Value<DateTime> scheduledAt,
  Value<DoseState> state,
  Value<DateTime?> actedAt,
});

final class $$DoseEventsTableReferences
    extends BaseReferences<_$AppDatabase, $DoseEventsTable, DoseEventRow> {
  $$DoseEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DoseSchedulesTable _doseScheduleIdTable(_$AppDatabase db) => db
      .doseSchedules
      .createAlias('dose_events__dose_schedule_id__dose_schedules__id');

  $$DoseSchedulesTableProcessedTableManager get doseScheduleId {
    final $_column = $_itemColumn<int>('dose_schedule_id')!;

    final manager = $$DoseSchedulesTableTableManager(
      $_db,
      $_db.doseSchedules,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_doseScheduleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DoseEventsTableFilterComposer
    extends Composer<_$AppDatabase, $DoseEventsTable> {
  $$DoseEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get routineDay =>
      $composableBuilder(
        column: $table.routineDay,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DoseState, DoseState, String> get state =>
      $composableBuilder(
        column: $table.state,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get actedAt => $composableBuilder(
    column: $table.actedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$DoseSchedulesTableFilterComposer get doseScheduleId {
    final $$DoseSchedulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.doseScheduleId,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableFilterComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DoseEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $DoseEventsTable> {
  $$DoseEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routineDay => $composableBuilder(
    column: $table.routineDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actedAt => $composableBuilder(
    column: $table.actedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$DoseSchedulesTableOrderingComposer get doseScheduleId {
    final $$DoseSchedulesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.doseScheduleId,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableOrderingComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DoseEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DoseEventsTable> {
  $$DoseEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get routineDay =>
      $composableBuilder(
        column: $table.routineDay,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DoseState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get actedAt =>
      $composableBuilder(column: $table.actedAt, builder: (column) => column);

  $$DoseSchedulesTableAnnotationComposer get doseScheduleId {
    final $$DoseSchedulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.doseScheduleId,
      referencedTable: $db.doseSchedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseSchedulesTableAnnotationComposer(
            $db: $db,
            $table: $db.doseSchedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DoseEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DoseEventsTable,
          DoseEventRow,
          $$DoseEventsTableFilterComposer,
          $$DoseEventsTableOrderingComposer,
          $$DoseEventsTableAnnotationComposer,
          $$DoseEventsTableCreateCompanionBuilder,
          $$DoseEventsTableUpdateCompanionBuilder,
          (DoseEventRow, $$DoseEventsTableReferences),
          DoseEventRow,
          PrefetchHooks Function({bool doseScheduleId})
        > {
  $$DoseEventsTableTableManager(_$AppDatabase db, $DoseEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DoseEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DoseEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DoseEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<int> doseScheduleId = const Value.absent(),
                Value<DateTime> routineDay = const Value.absent(),
                Value<DateTime> scheduledAt = const Value.absent(),
                Value<DoseState> state = const Value.absent(),
                Value<DateTime?> actedAt = const Value.absent(),
              }) => DoseEventsCompanion(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                doseScheduleId: doseScheduleId,
                routineDay: routineDay,
                scheduledAt: scheduledAt,
                state: state,
                actedAt: actedAt,
              ),
          createCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<int> id = const Value.absent(),
                required int doseScheduleId,
                required DateTime routineDay,
                required DateTime scheduledAt,
                required DoseState state,
                Value<DateTime?> actedAt = const Value.absent(),
              }) => DoseEventsCompanion.insert(
                uuid: uuid,
                updatedAtMs: updatedAtMs,
                syncedAtMs: syncedAtMs,
                id: id,
                doseScheduleId: doseScheduleId,
                routineDay: routineDay,
                scheduledAt: scheduledAt,
                state: state,
                actedAt: actedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DoseEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({doseScheduleId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (doseScheduleId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.doseScheduleId,
                        referencedTable: $$DoseEventsTableReferences
                            ._doseScheduleIdTable(db),
                        referencedColumn: $$DoseEventsTableReferences
                            ._doseScheduleIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DoseEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DoseEventsTable,
      DoseEventRow,
      $$DoseEventsTableFilterComposer,
      $$DoseEventsTableOrderingComposer,
      $$DoseEventsTableAnnotationComposer,
      $$DoseEventsTableCreateCompanionBuilder,
      $$DoseEventsTableUpdateCompanionBuilder,
      (DoseEventRow, $$DoseEventsTableReferences),
      DoseEventRow,
      PrefetchHooks Function({bool doseScheduleId})
    >;
typedef $$RoutineBackupsTableCreateCompanionBuilder =
    RoutineBackupsCompanion Function({
      Value<int> patientId,
      required int wakeMinutes,
      required int breakfastMinutes,
      required int lunchMinutes,
      required int dinnerMinutes,
      required int sleepMinutes,
      required int iftarMinutes,
      required int suhoorMinutes,
    });
typedef $$RoutineBackupsTableUpdateCompanionBuilder =
    RoutineBackupsCompanion Function({
      Value<int> patientId,
      Value<int> wakeMinutes,
      Value<int> breakfastMinutes,
      Value<int> lunchMinutes,
      Value<int> dinnerMinutes,
      Value<int> sleepMinutes,
      Value<int> iftarMinutes,
      Value<int> suhoorMinutes,
    });

final class $$RoutineBackupsTableReferences
    extends
        BaseReferences<_$AppDatabase, $RoutineBackupsTable, RoutineBackupRow> {
  $$RoutineBackupsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PatientsTable _patientIdTable(_$AppDatabase db) =>
      db.patients.createAlias('routine_backups__patient_id__patients__id');

  $$PatientsTableProcessedTableManager get patientId {
    final $_column = $_itemColumn<int>('patient_id')!;

    final manager = $$PatientsTableTableManager(
      $_db,
      $_db.patients,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_patientIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RoutineBackupsTableFilterComposer
    extends Composer<_$AppDatabase, $RoutineBackupsTable> {
  $$RoutineBackupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get wakeMinutes => $composableBuilder(
    column: $table.wakeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get breakfastMinutes => $composableBuilder(
    column: $table.breakfastMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lunchMinutes => $composableBuilder(
    column: $table.lunchMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dinnerMinutes => $composableBuilder(
    column: $table.dinnerMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepMinutes => $composableBuilder(
    column: $table.sleepMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get iftarMinutes => $composableBuilder(
    column: $table.iftarMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get suhoorMinutes => $composableBuilder(
    column: $table.suhoorMinutes,
    builder: (column) => ColumnFilters(column),
  );

  $$PatientsTableFilterComposer get patientId {
    final $$PatientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableFilterComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoutineBackupsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoutineBackupsTable> {
  $$RoutineBackupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get wakeMinutes => $composableBuilder(
    column: $table.wakeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get breakfastMinutes => $composableBuilder(
    column: $table.breakfastMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lunchMinutes => $composableBuilder(
    column: $table.lunchMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dinnerMinutes => $composableBuilder(
    column: $table.dinnerMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepMinutes => $composableBuilder(
    column: $table.sleepMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get iftarMinutes => $composableBuilder(
    column: $table.iftarMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get suhoorMinutes => $composableBuilder(
    column: $table.suhoorMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  $$PatientsTableOrderingComposer get patientId {
    final $$PatientsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableOrderingComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoutineBackupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoutineBackupsTable> {
  $$RoutineBackupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get wakeMinutes => $composableBuilder(
    column: $table.wakeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get breakfastMinutes => $composableBuilder(
    column: $table.breakfastMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lunchMinutes => $composableBuilder(
    column: $table.lunchMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dinnerMinutes => $composableBuilder(
    column: $table.dinnerMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sleepMinutes => $composableBuilder(
    column: $table.sleepMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get iftarMinutes => $composableBuilder(
    column: $table.iftarMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get suhoorMinutes => $composableBuilder(
    column: $table.suhoorMinutes,
    builder: (column) => column,
  );

  $$PatientsTableAnnotationComposer get patientId {
    final $$PatientsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.patientId,
      referencedTable: $db.patients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PatientsTableAnnotationComposer(
            $db: $db,
            $table: $db.patients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoutineBackupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoutineBackupsTable,
          RoutineBackupRow,
          $$RoutineBackupsTableFilterComposer,
          $$RoutineBackupsTableOrderingComposer,
          $$RoutineBackupsTableAnnotationComposer,
          $$RoutineBackupsTableCreateCompanionBuilder,
          $$RoutineBackupsTableUpdateCompanionBuilder,
          (RoutineBackupRow, $$RoutineBackupsTableReferences),
          RoutineBackupRow,
          PrefetchHooks Function({bool patientId})
        > {
  $$RoutineBackupsTableTableManager(
    _$AppDatabase db,
    $RoutineBackupsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoutineBackupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoutineBackupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoutineBackupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> patientId = const Value.absent(),
                Value<int> wakeMinutes = const Value.absent(),
                Value<int> breakfastMinutes = const Value.absent(),
                Value<int> lunchMinutes = const Value.absent(),
                Value<int> dinnerMinutes = const Value.absent(),
                Value<int> sleepMinutes = const Value.absent(),
                Value<int> iftarMinutes = const Value.absent(),
                Value<int> suhoorMinutes = const Value.absent(),
              }) => RoutineBackupsCompanion(
                patientId: patientId,
                wakeMinutes: wakeMinutes,
                breakfastMinutes: breakfastMinutes,
                lunchMinutes: lunchMinutes,
                dinnerMinutes: dinnerMinutes,
                sleepMinutes: sleepMinutes,
                iftarMinutes: iftarMinutes,
                suhoorMinutes: suhoorMinutes,
              ),
          createCompanionCallback:
              ({
                Value<int> patientId = const Value.absent(),
                required int wakeMinutes,
                required int breakfastMinutes,
                required int lunchMinutes,
                required int dinnerMinutes,
                required int sleepMinutes,
                required int iftarMinutes,
                required int suhoorMinutes,
              }) => RoutineBackupsCompanion.insert(
                patientId: patientId,
                wakeMinutes: wakeMinutes,
                breakfastMinutes: breakfastMinutes,
                lunchMinutes: lunchMinutes,
                dinnerMinutes: dinnerMinutes,
                sleepMinutes: sleepMinutes,
                iftarMinutes: iftarMinutes,
                suhoorMinutes: suhoorMinutes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RoutineBackupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({patientId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (patientId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.patientId,
                        referencedTable: $$RoutineBackupsTableReferences
                            ._patientIdTable(db),
                        referencedColumn: $$RoutineBackupsTableReferences
                            ._patientIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RoutineBackupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoutineBackupsTable,
      RoutineBackupRow,
      $$RoutineBackupsTableFilterComposer,
      $$RoutineBackupsTableOrderingComposer,
      $$RoutineBackupsTableAnnotationComposer,
      $$RoutineBackupsTableCreateCompanionBuilder,
      $$RoutineBackupsTableUpdateCompanionBuilder,
      (RoutineBackupRow, $$RoutineBackupsTableReferences),
      RoutineBackupRow,
      PrefetchHooks Function({bool patientId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PatientsTableTableManager get patients =>
      $$PatientsTableTableManager(_db, _db.patients);
  $$DayRoutinesTableTableManager get dayRoutines =>
      $$DayRoutinesTableTableManager(_db, _db.dayRoutines);
  $$MedicationsTableTableManager get medications =>
      $$MedicationsTableTableManager(_db, _db.medications);
  $$DoseSchedulesTableTableManager get doseSchedules =>
      $$DoseSchedulesTableTableManager(_db, _db.doseSchedules);
  $$FixedTimingsTableTableManager get fixedTimings =>
      $$FixedTimingsTableTableManager(_db, _db.fixedTimings);
  $$DoseEventsTableTableManager get doseEvents =>
      $$DoseEventsTableTableManager(_db, _db.doseEvents);
  $$RoutineBackupsTableTableManager get routineBackups =>
      $$RoutineBackupsTableTableManager(_db, _db.routineBackups);
}
