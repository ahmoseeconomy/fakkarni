// الصفوف اللي بترجع من دوال `0021_admin.sql` — دارت ساذجة، من غير Flutter
// ومن غير Supabase، فبتتختبر بأرقام من غير ما نرسم شاشة.
//
// **مفيش اسم دوا ولا سجل ولا نتيجة تحليل ولا قياس ولا بيانات طوارئ في أي
// موديل هنا** — ولا دالة في السحابة بترجّع حاجة من دول. لو حد احتاج يزوّد
// حقل، لازم يعدّي على `returns table` في الترحيل الأول.

/// بيقرا وقت من عمود `timestamptz` — بيرجع بالتوقيت المحلي زي باقي التطبيق.
DateTime? parseUtc(Object? iso) =>
    iso is String ? DateTime.parse(iso).toLocal() : null;

int _int(Object? value) => switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value) ?? 0,
      _ => 0,
    };

/// شريط العدّادات — محسوب من **نفس** صفوف [AdminAccount] في السيرفر.
class AdminCounts {
  const AdminCounts({
    required this.totalPatients,
    required this.totalFollowers,
    required this.active7d,
    required this.batteryRestricted,
  });

  factory AdminCounts.fromRow(Map<String, dynamic> row) => AdminCounts(
        totalPatients: _int(row['total_patients']),
        totalFollowers: _int(row['total_followers']),
        active7d: _int(row['active_7d']),
        batteryRestricted: _int(row['battery_restricted']),
      );

  static const empty =
      AdminCounts(totalPatients: 0, totalFollowers: 0, active7d: 0, batteryRestricted: 0);

  final int totalPatients;
  final int totalFollowers;
  final int active7d;
  final int batteryRestricted;
}

/// صف واحد في الجدول: حساب مريض + آخر نبضة من موبايله.
class AdminAccount {
  const AdminAccount({
    required this.patientUuid,
    required this.patientName,
    required this.createdAt,
    required this.followersCount,
    required this.pendingInvites,
    required this.lastSyncAt,
    required this.missedDoses24h,
    required this.pendingEscalations,
    required this.escalations7d,
    this.platform,
    this.appVersion,
    this.batteryState,
    this.reminderHorizonOk = false,
    this.seenAt,
  });

  factory AdminAccount.fromRow(Map<String, dynamic> row) => AdminAccount(
        patientUuid: row['patient_uuid'] as String? ?? '',
        patientName: (row['patient_name'] as String?)?.trim() ?? '',
        createdAt: parseUtc(row['created_at']),
        followersCount: _int(row['followers_count']),
        pendingInvites: _int(row['pending_invites']),
        lastSyncAt: parseUtc(row['last_sync_at']),
        platform: row['platform'] as String?,
        appVersion: row['app_version'] as String?,
        batteryState: row['battery_state'] as String?,
        reminderHorizonOk: row['reminder_horizon_ok'] == true,
        seenAt: parseUtc(row['seen_at']),
        missedDoses24h: _int(row['missed_doses_24h']),
        pendingEscalations: _int(row['pending_escalations']),
        escalations7d: _int(row['escalations_7d']),
      );

  final String patientUuid;
  final String patientName;
  final DateTime? createdAt;
  final int followersCount;
  final int pendingInvites;

  /// آخر ختم سيرفر على أي صف بتاع المريض — مش دعوى الجهاز عن نفسه.
  final DateTime? lastSyncAt;

  final String? platform;
  final String? appVersion;

  /// `unrestricted` / `restricted` / `unknown` / null (نسخة قبل ٠٠١٩).
  final String? batteryState;

  final bool reminderHorizonOk;

  /// وقت آخر نبضة سلامة. null = الموبايل عمره ما بعت — وده أخطر حاجة.
  final DateTime? seenAt;

  final int missedDoses24h;
  final int pendingEscalations;
  final int escalations7d;

  bool get batteryRestricted => batteryState == 'restricted';
}

/// متابع مربوط — الاسم والصلة والحالة وبس. **مفيش ساعات هدوء ولا نطاق
/// تنبيه** (تفضيلات المتابع نفسه، ٠٠٢٠).
class AdminFollower {
  const AdminFollower({this.displayName, this.relation, this.status, this.linkedAt});

  factory AdminFollower.fromRow(Map<String, dynamic> row) => AdminFollower(
        displayName: (row['display_name'] as String?)?.trim(),
        relation: row['relation'] as String?,
        status: row['status'] as String?,
        linkedAt: parseUtc(row['linked_at']),
      );

  final String? displayName;
  final String? relation;
  final String? status;
  final DateTime? linkedAt;
}

/// تنبيه اتبعت (أو ما اتبعتش) للمتابع — حالة تسليم وبس.
class AdminEscalation {
  const AdminEscalation({
    this.scheduledAt,
    this.rung,
    this.deliveryStatus,
    this.createdAt,
  });

  factory AdminEscalation.fromRow(Map<String, dynamic> row) => AdminEscalation(
        scheduledAt: parseUtc(row['scheduled_at']),
        rung: row['rung'] as String?,
        deliveryStatus: row['delivery_status'] as String?,
        createdAt: parseUtc(row['created_at']),
      );

  final DateTime? scheduledAt;
  final String? rung;
  final String? deliveryStatus;
  final DateTime? createdAt;
}
