import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/care/follower_profile.dart';
import 'care_circle_service.dart' show CareCircleException, CareCircleFailure;
import 'caregiver_preferences.dart';

/// التنفيذ الحقيقي فوق Supabase — الحزمة بتتستورد هنا وبس (قاعدة
/// `supabase_*` في ملف واحد ورا واجهة).
class SupabaseCaregiverPreferences implements CaregiverPreferencesService {
  SupabaseCaregiverPreferences(this._supabase);

  final SupabaseClient _supabase;

  static const table = 'caregiver_preferences';

  String get _me {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) {
      // نفس قاعدة جولة ٢٥: مفيش جلسة = «مش مربوط»، مش «حصل عطل». وبرضه
      // **عمرنا ما نبعت `''` كـuuid** — بوستجرس بيرفضه (22P02) والعطل
      // بيتقري كأنه مشكلة شبكة.
      throw const CareCircleException(CareCircleFailure.other, 'no session');
    }
    return id;
  }

  @override
  Future<CaregiverPreferences> load(String patientUuid) async {
    final row = await _supabase
        .from(table)
        .select()
        .eq('caregiver_id', _me)
        .eq('patient_uuid', patientUuid)
        .maybeSingle();
    if (row == null) return const CaregiverPreferences();
    return CaregiverPreferences(
      name: row['display_name'] as String?,
      relation: FollowerRelation.fromStored(row['relation'] as String?),
      relationOther: row['relation_other'] as String?,
      alertScope: AlertScope.fromStored(row['alert_scope'] as String?),
      quietFromMinute: row['quiet_from_minute'] as int?,
      quietToMinute: row['quiet_to_minute'] as int?,
    );
  }

  @override
  Future<void> save(String patientUuid, CaregiverPreferences preferences) =>
      _supabase.from(table).upsert({
        'caregiver_id': _me,
        'patient_uuid': patientUuid,
        'display_name': preferences.name,
        'relation': preferences.relation?.name,
        'relation_other': preferences.relationOther,
        'alert_scope': preferences.alertScope.name,
        'quiet_from_minute': preferences.quietFromMinute,
        'quiet_to_minute': preferences.quietToMinute,
      }, onConflict: 'caregiver_id,patient_uuid');

  /// **دالة، مش `select` على الجدول.** سياسات بوستجرس على مستوى الصف مش
  /// العمود، فلو الأب اتسمح له يقرا الصف كان هيقرا ساعات هدوء ابنه ونطاق
  /// تنبيهه كمان. الدالة بترجّع العمودين اللي ليه بس.
  @override
  Future<List<FollowerProfile>> followers(String patientUuid) async {
    final rows = await _supabase
        .rpc('followers_of_patient', params: {'p_patient_uuid': patientUuid});
    return [
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        FollowerProfile(
          name: (row['display_name'] as String?)?.trim() ?? '',
          relation: FollowerRelation.fromStored(row['relation'] as String?),
          relationOther: row['relation_other'] as String?,
        ),
      // اللي ما كتبش اسمه ما بيتعرضش كصف فاضي — بيتعدّ وبس.
    ].where((f) => f.name.isNotEmpty).toList();
  }
}
