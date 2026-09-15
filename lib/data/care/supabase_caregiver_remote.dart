import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/arabic_time.dart';
import '../../domain/wording/rule_wording.dart';
import 'caregiver_remote.dart';

/// تنبيهات السيرفر اللي بتظهر فوق الشاشة.
const Duration alertWindow = Duration(hours: 48);

/// صف escalations بالـembed بتاعه → [CaregiverAlert]. منفصلة عشان تتختبر
/// من غير Supabase.
CaregiverAlert alertFromRow(Map<String, dynamic> row) {
  final event = row['dose_events'] as Map;
  final med = (event['dose_schedules'] as Map?)?['medications'] as Map?;
  DateTime? time(dynamic iso) =>
      iso is String ? DateTime.parse(iso).toLocal() : null;
  return CaregiverAlert(
    uuid: row['uuid'] as String,
    medicationName: (med?['name'] as String?) ?? 'دواء',
    scheduledAt: time(event['scheduled_at'])!,
    doseState: event['state'] as String,
    deliveryStatus: row['delivery_status'] as String,
    createdAt: time(row['created_at'])!,
    sentAt: time(row['sent_at']),
  );
}

/// صف medications بجداوله المضمّنة → [CaregiverMedication]. قواعد الجرعات
/// **نص** من نفس صياغة المريض — مفيش حساب ساعة لمرساة هنا أبداً. الساعة
/// الثابتة بتتعرض لأنها مكتوبة كده في الصف، مش محسوبة. منفصلة عشان تتختبر
/// من غير Supabase.
CaregiverMedication medicationFromRow(Map<String, dynamic> row) {
  final schedules = (row['dose_schedules'] as List?) ?? const [];
  String? rule(Map s) {
    if (s['timing_kind'] == 'fixed') {
      final fixed = s['fixed_timings'];
      final minute = (fixed is List ? (fixed.isEmpty ? null : fixed.first) : fixed) as Map?;
      final m = minute?['minute_of_day'] as int?;
      return m == null ? fixedRuleWording : '$fixedRuleWording · ${arabicTime(DateTime(2026, 1, 1, 0, m))}';
    }
    final word = anchorWords[s['anchor']];
    if (word == null) return null;
    return anchorRuleWording(word, (s['offset_minutes'] as int?) ?? 0);
  }

  return CaregiverMedication(
    uuid: row['uuid'] as String,
    name: row['name'] as String,
    amountLabel: row['amount_label'] as String?,
    rules: [
      for (final s in schedules) ?rule(s as Map),
    ],
  );
}

/// القراءة الحقيقية. العلاقات بتيجي من care_relationships (RLS بتوريني
/// صفوفي أنا)، والمريض بيتحدّد منها — مش من فلترة owner_id على العميل:
/// الابن ممكن يكون مريضاً في تطبيقه هو كمان، وصفّه بيظهر في patients عادي.
class SupabaseCaregiverRemote implements CaregiverRemote {
  SupabaseCaregiverRemote(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<CaregiverPatient?> linkedPatient() => _guard(() async {
        final links = await _supabase
            .from('care_relationships')
            .select('patient_uuid')
            .eq('status', 'accepted')
            .eq('caregiver_id', _supabase.auth.currentUser?.id ?? '');
        if (links.isEmpty) return null;

        final rows = await _supabase
            .from('patients')
            .select('uuid, name')
            .eq('uuid', links.first['patient_uuid'] as String);
        if (rows.isEmpty) return null;
        final row = rows.single;
        return CaregiverPatient(
          uuid: row['uuid'] as String,
          name: row['name'] as String,
        );
      });

  @override
  Future<CaregiverSnapshot?> snapshot() => _guard(() async {
        final patient = await linkedPatient();
        if (patient == null) return null;

        final meds = await _supabase
            .from('medications')
            .select('uuid, name, amount_label, stopped_at, updated_at, '
                'dose_schedules(timing_kind, anchor, offset_minutes, fixed_timings(minute_of_day))')
            .eq('patient_uuid', patient.uuid);

        final since = DateTime.now().toUtc().subtract(const Duration(days: 7));
        final events = await _supabase
            .from('dose_events')
            .select('uuid, scheduled_at, state, acted_at, updated_at, '
                'dose_schedules(medications(name, amount_label))')
            .gte('scheduled_at', since.toIso8601String())
            // «اتغيّرت القاعدة» (0010) مش جرعة — ما تتعرضش على شاشة الابن
            .neq('state', 'superseded')
            .order('scheduled_at', ascending: true);

        final alertsSince =
            DateTime.now().toUtc().subtract(alertWindow).toIso8601String();
        final alerts = await _supabase
            .from('escalations')
            .select('uuid, delivery_status, created_at, sent_at, '
                'dose_events!inner(scheduled_at, state, '
                'dose_schedules!inner(medications!inner(name, patient_uuid)))')
            .eq('caregiver_id', _supabase.auth.currentUser?.id ?? '')
            .inFilter('delivery_status', ['sent', 'no_token', 'failed'])
            .gte('created_at', alertsSince)
            .eq('dose_events.dose_schedules.medications.patient_uuid',
                patient.uuid)
            .order('created_at', ascending: false);

        DateTime? last;
        void bump(dynamic iso) {
          if (iso is! String) return;
          final t = DateTime.tryParse(iso);
          if (t != null && (last == null || t.isAfter(last!))) last = t;
        }

        for (final m in meds) {
          bump(m['updated_at']);
        }
        for (final e in events) {
          bump(e['updated_at']);
        }

        return CaregiverSnapshot(
          patient: patient,
          medications: [
            for (final m in meds)
              if (m['stopped_at'] == null) medicationFromRow(m),
          ],
          events: [
            for (final e in events)
              CaregiverDoseEvent(
                uuid: e['uuid'] as String,
                medicationName: (((e['dose_schedules'] as Map?)?['medications']
                        as Map?)?['name'] as String?) ??
                    'دواء',
                amountLabel: ((e['dose_schedules'] as Map?)?['medications']
                    as Map?)?['amount_label'] as String?,
                scheduledAt:
                    DateTime.parse(e['scheduled_at'] as String).toLocal(),
                state: e['state'] as String,
                actedAt: e['acted_at'] == null
                    ? null
                    : DateTime.parse(e['acted_at'] as String).toLocal(),
              ),
          ],
          alerts: [for (final a in alerts) alertFromRow(a)],
          lastUpdated: last?.toLocal(),
        );
      });

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on SocketException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } on AuthRetryableFetchException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } on PostgrestException catch (e) {
      throw CareCircleException(CareCircleFailure.other, e);
    } catch (e) {
      throw CareCircleException(CareCircleFailure.other, e);
    }
  }
}
