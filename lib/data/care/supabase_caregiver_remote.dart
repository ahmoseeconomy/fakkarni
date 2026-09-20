import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/arabic_time.dart';
import '../../domain/health/lab_range.dart';
import '../../domain/wording/rule_wording.dart';
import 'caregiver_remote.dart';

/// تنبيهات السيرفر اللي بتظهر فوق الشاشة.
const Duration alertWindow = Duration(hours: 48);

/// حدود الملف الصحي (D5.2) — كل استعلام محدود لحد ما السحب بالفرق ييجي.
const recordsLimit = 50;
const readingsWindow = Duration(days: 30);
const readingsLimit = 200;
const questionsLimit = 50;

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
      return m == null ? fixedRuleWording : '$fixedRuleWording — ${arabicTime(DateTime(2026, 1, 1, 0, m))}';
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
      // الجرعة الموقوفة مش قاعدة شغّالة — ما تظهرش عند الابن
      for (final s in schedules)
        if ((s as Map)['stopped_at'] == null) ?rule(s),
    ],
  );
}

DateTime _local(Object? iso) => DateTime.parse(iso! as String).toLocal();

/// صف records بسطور تحاليله المضمّنة → [CaregiverRecord]. سجل ممسوح ناعم
/// بيرجع null — الاستعلام بيفلتره، وده خط دفاع تاني: الأب مسحه، يبقى ما
/// يتعرضش عند الابن أبداً.
CaregiverRecord? recordFromRow(Map<String, dynamic> row) {
  if (row['deleted_at'] != null) return null;
  final lines = (row['lab_results'] as List?) ?? const [];
  return CaregiverRecord(
    uuid: row['uuid'] as String,
    kind: row['kind'] as String,
    title: row['title'] as String,
    happenedAt: _local(row['happened_at']),
    updatedAt: _local(row['updated_at']),
    doctor: row['doctor'] as String?,
    place: row['place'] as String?,
    notes: row['notes'] as String?,
    labLines: [
      for (final l in lines)
        () {
          final map = l as Map;
          // نطاق الورقة زي ما جهاز الأب رفعه. التلاتة null (ورقة من غير
          // نطاق، أو صف اتكتب قبل نسخة ١٨) = مفيش نطاق، وبس.
          final range = LabRange(
            low: (map['ref_low'] as num?)?.toDouble(),
            high: (map['ref_high'] as num?)?.toDouble(),
            text: map['ref_text'] as String?,
          );
          return CaregiverLabLine(
            testName: map['test_name'] as String,
            value: (map['value'] as num).toDouble(),
            unit: map['unit'] as String?,
            range: range.isEmpty ? null : range,
          );
        }(),
    ],
  );
}

CaregiverReading readingFromRow(Map<String, dynamic> row) => CaregiverReading(
      uuid: row['uuid'] as String,
      valueMgDl: row['value_mg_dl'] as int,
      measuredAt: _local(row['measured_at']),
      context: row['context'] as String,
      updatedAt: _local(row['updated_at']),
    );

/// صف فاضي كله (الأب فتح الشاشة وما كتبش) = null، زي «مفيش حاجة».
CaregiverEmergency? emergencyFromRow(Map<String, dynamic>? row) {
  if (row == null) return null;
  String? text(String key) {
    final v = (row[key] as String?)?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  final e = CaregiverEmergency(
    bloodType: text('blood_type'),
    allergies: text('allergies'),
    chronicConditions: text('chronic_conditions'),
  );
  return e.bloodType == null && e.allergies == null && e.chronicConditions == null ? null : e;
}

CaregiverQuestion questionFromRow(Map<String, dynamic> row) => CaregiverQuestion(
      uuid: row['uuid'] as String,
      body: row['body'] as String,
      writtenAt: _local(row['written_at']),
      asked: row['asked'] as bool? ?? false,
      updatedAt: _local(row['updated_at']),
    );

/// القراءة الحقيقية. العلاقات بتيجي من care_relationships (RLS بتوريني
/// صفوفي أنا)، والمريض بيتحدّد منها — مش من فلترة owner_id على العميل:
/// الابن ممكن يكون مريضاً في تطبيقه هو كمان، وصفّه بيظهر في patients عادي.
class SupabaseCaregiverRemote implements CaregiverRemote {
  SupabaseCaregiverRemote(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<CaregiverPatient?> linkedPatient() => _guard(() async {
        // **ترتيب حتمي إجباري.** موبايل واحد ممكن يكون متربط بأكتر من أب
        // (اختبارات، أو ابن بيتابع أبوه وأمه). من غير order بيرجّع Postgres
        // أي صف — فالعنوان ييجي من أب والأدوية من أب تاني، والشاشة تبان
        // فاضية من غير أي خطأ. الأحدث هو المقصود: آخر كود اتفكّ.
        // **مفيش جلسة = مفيش ربط، مش «حصل خطأ».**
        //
        // كان هنا `?? ''`، وده كان بيبعت `caregiver_id=eq.` — وPostgres
        // بيرفض `''` كـuuid (22P02). الرمية دي كانت بتترجم لـ«مقدرناش
        // نكمّل. جرّب تاني.»، وبتقع **قبل** أي استعلام تاني، فشاشة الابن
        // كلها تفضل فاضية كمان. مفيش جلسة حالة عادية — جهاز اتمسح، أو
        // توكن انتهى — ومعناها «ما اتربطش»، واللي بيتعمل معاها إنه يرجع
        // لشاشة البداية، مش رسالة عطل.
        final me = _supabase.auth.currentUser?.id;
        if (me == null) return null;

        final links = await _supabase
            .from('care_relationships')
            .select('patient_uuid')
            .eq('status', 'accepted')
            .eq('caregiver_id', me)
            .order('created_at', ascending: false)
            .limit(1);
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
        // وصلنا لهنا يعني فيه جلسة ([linkedPatient] بترجع null من غيرها) —
        // بس بنقراها مرة واحدة بدل ما كل استعلام يعمل `?? ''` لوحده.
        final me = _supabase.auth.currentUser?.id;
        if (me == null) return null;

        // الدوا المتشال مالوش وجود عند الابن، والجرعة الموقوفة مش قاعدة
        // شغّالة — من غير الفلترين دول الابن بيشوف دوا أبوه شاله.
        final meds = await _supabase
            .from('medications')
            .select('uuid, name, amount_label, stopped_at, updated_at, '
                'dose_schedules(timing_kind, anchor, offset_minutes, stopped_at, '
                'fixed_timings(minute_of_day))')
            .eq('patient_uuid', patient.uuid)
            .isFilter('removed_at', null);

        final since = DateTime.now().toUtc().subtract(const Duration(days: 7));
        final events = await _supabase
            .from('dose_events')
            .select('uuid, scheduled_at, state, acted_at, updated_at, '
                'dose_schedules!inner(medications!inner(name, amount_label, removed_at))')
            .gte('scheduled_at', since.toIso8601String())
            // «اتغيّرت القاعدة» (0010) مش جرعة — ما تتعرضش على شاشة الابن
            .neq('state', 'superseded')
            // ولا جرعة دوا الأب شاله
            .isFilter('dose_schedules.medications.removed_at', null)
            .order('scheduled_at', ascending: true);

        final alertsSince =
            DateTime.now().toUtc().subtract(alertWindow).toIso8601String();
        final alerts = await _supabase
            .from('escalations')
            .select('uuid, delivery_status, created_at, sent_at, '
                'dose_events!inner(scheduled_at, state, '
                'dose_schedules!inner(medications!inner(name, patient_uuid)))')
            .eq('caregiver_id', me)
            // **الجرعة اللي اتقفلت مالهاش تنبيه — والفلتر في السحابة مش في
            // الودجت.** تنبيه بيقول «والدك ما أكّدش» عن جرعة خدها هو أسوأ
            // غلط ممكن على الشاشة دي: الابن اللي يكتشف إن التنبيهات بتكدب
            // بيبطّل يقراها كلها. والفلترة هنا معناها إن الصفوف دي عمرها
            // ما بتتحمّل أصلاً. ([openDoseStateNames] — والقايمة مشتقة من
            // switch شامل، فحالة جديدة بتكسر الترجمة بدل ما تبقى تنبيه.)
            .inFilter('dose_events.state', openDoseStateNames)
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

        // ---- الملف الصحي (D5.2). **كل استعلام محدود** لحد ما السحب بالفرق
        // (delta) ييجي — مفيش select من غير حد.
        final records = await _supabase
            .from('records')
            .select('uuid, kind, title, happened_at, doctor, place, notes, deleted_at, updated_at, '
                'lab_results(test_name, value, unit, ref_low, ref_high, ref_text)')
            .eq('patient_uuid', patient.uuid)
            .isFilter('deleted_at', null)
            .order('updated_at', ascending: false)
            .limit(recordsLimit);

        final readingsSince = DateTime.now().toUtc().subtract(readingsWindow).toIso8601String();
        final readings = await _supabase
            .from('readings')
            .select('uuid, value_mg_dl, measured_at, context, updated_at')
            .eq('patient_uuid', patient.uuid)
            .gte('measured_at', readingsSince)
            .order('measured_at', ascending: false)
            .limit(readingsLimit);

        final emergency = await _supabase
            .from('emergency_profile')
            .select('blood_type, allergies, chronic_conditions, updated_at')
            .eq('patient_uuid', patient.uuid)
            .limit(1);

        final questions = await _supabase
            .from('visit_questions')
            .select('uuid, body, written_at, asked, updated_at')
            .eq('patient_uuid', patient.uuid)
            .order('updated_at', ascending: false)
            .limit(questionsLimit);

        for (final rows in [records, readings, emergency, questions]) {
          for (final r in rows) {
            bump(r['updated_at']);
          }
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
          records: [for (final r in records) ?recordFromRow(r)],
          readings: [for (final r in readings) readingFromRow(r)],
          emergency: emergencyFromRow(emergency.isEmpty ? null : emergency.first),
          questions: [for (final q in questions) questionFromRow(q)],
        );
      });

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CareCircleException {
      // **اتصنّفت خلاص — تعدّي زي ما هي.**
      //
      // `snapshot()` بتنده `linkedPatient()`، والاتنين متلفّفين. من غير
      // السطر ده، اللفّة البرّانية كانت بتمسك الاستثناء اللي الجوّانية
      // رمته وتعيد تصنيفه `other` — يعني **عطل الشبكة جوّه
      // `linkedPatient` كان بيوصل الابن كـ«مقدرناش نكمّل» بدل جملة
      // «إنت مش متصل»**. ودي الحالة الشايعة، لأن `linkedPatient` أول
      // حاجة بتتنفّذ.
      rethrow;
    } on SocketException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } on AuthRetryableFetchException catch (e) {
      throw CareCircleException(CareCircleFailure.offline, e);
    } on PostgrestException catch (e, st) {
      // **الشاشة بتقول جملة واحدة — واللوج بيقول اللي حصل فعلاً.**
      // من غير السطر ده، «مقدرناش نكمّل» هي كل اللي قدام اللي بيصلّح:
      // عمود ناقص، أو علاقة PostgREST مش لاقياها، أو RLS رافضة — التلاتة
      // شكلهم واحد على الشاشة. `code` و`details` و`hint` هي اللي بتسمّي
      // العمود أو الجدول، فبتترمي هنا كلها.
      _logFailure(
        'PostgrestException code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
        st,
      );
      throw CareCircleException(CareCircleFailure.other, e);
    } catch (e, st) {
      _logFailure('${e.runtimeType}: $e', st);
      throw CareCircleException(CareCircleFailure.other, e);
    }
  }

  /// بيطبع في نسخ التطوير بس. **عمره ما بيوصل الشاشة**: الجملة اللي
  /// المستخدم بيقراها هي هي، والنص الخام ده للمطوّر لوحده.
  void _logFailure(String what, StackTrace st) {
    if (!kDebugMode) return;
    debugPrint('Care: قراية بيانات الأب فشلت — $what');
    debugPrintStack(stackTrace: st, label: 'Care');
  }
}
