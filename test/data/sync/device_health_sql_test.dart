// 0037 — الفحص الذاتي في السحابة: حالة الجهاز مكتوبة مرتين (دارت وSQL)،
// والسياسات على أعمدة الصف نفسه، والساكت كل ساعة، والـview للمالك بس.
// Postgres ما بيقراش دارت — الاختبار ده هو المرآة الوحيدة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/health/supabase_health_remote.dart';
import 'package:fakkarni/domain/health/health_check.dart';
import 'package:fakkarni/domain/health/health_report.dart';

const _migration = 'supabase/migrations/0037_device_self_check.sql';

void main() {
  late String sql;

  setUp(() {
    final file = File(_migration);
    expect(file.existsSync(), isTrue, reason: 'مش لاقي $_migration');
    sql = file.readAsStringSync();
  });

  test('0036 محجوز (PRN) — ما اتاخدش', () {
    final files = Directory('supabase/migrations').listSync().map((f) => f.path.split('/').last).toList();
    expect(files.where((f) => f.startsWith('0036')), isEmpty, reason: '0036 محجوز لـPRN');
    expect(files.where((f) => f.startsWith('0037')), ['0037_device_self_check.sql']);
  });

  test('قيد الحالة في SQL = كلمات HealthStatus.wire + silent (بتاعة السيرفر)', () {
    final check = RegExp(r"device_health_status_check\s+check\s*\(status in \(([^)]*)\)\)").firstMatch(sql);
    expect(check, isNotNull);
    final allowed = RegExp(r"'(\w+)'").allMatches(check!.group(1)!).map((m) => m.group(1)).toSet();
    for (final s in HealthStatus.values) {
      expect(allowed, contains(s.wire), reason: '${s.name} مش في قيد SQL');
    }
    expect(allowed, contains('silent'));
    expect(allowed.length, HealthStatus.values.length + 1, reason: 'حالة في SQL مالهاش نظير في دارت');
    // الكلمات على السلك بالشرطة السفلية زي المواصفة
    expect(HealthStatus.needsUser.wire, 'needs_user');
    expect(HealthStatus.values.map((s) => s.wire), ['ok', 'healed', 'needs_user', 'broken']);
  });

  test('الأعمدة اللي الموبايل بيبعتها اختيارية قبل 0037 — ونفسها اللي الملف بيضيفها', () {
    for (final c in SupabaseHealthRemote.optionalColumns) {
      expect(sql, contains('add column if not exists $c '), reason: '$c مش في 0037');
    }
    expect(SupabaseHealthRemote.optionalColumns, {'status', 'codes', 'user_id'});
    expect(sql, contains('check (private.health_codes_ok(codes))'), reason: 'الأكواد قايمة نصوص قصيرة وبس');
  });

  test('السياسات على أعمدة الصف — user_id = auth.uid()، ولا owns_patient، ولا grant لـanon', () {
    // الاسم بيتذكر في تعليق الرأس (ليه اتشال) — الكود نفسه لأ
    final code = sql.replaceAll(RegExp(r'--[^\n]*'), '');
    // owns_patient مسموح في مكان واحد: USING بتاع التعديل (جلسة جديدة لصاحب المريض)
    final update = RegExp(r'create policy device_health_update[\s\S]*?;').firstMatch(code)!.group(0)!;
    expect(update, contains('using (user_id = (select auth.uid()) or private.owns_patient(patient_uuid))'));
    expect(update, contains('with check (user_id = (select auth.uid()))'));
    expect(update, isNot(contains('can_access_patient')), reason: 'ابن أو ممرض ما يكتبش فوق صف موبايل أبوه');
    // **القراية لازم تبقى بعرض USING بتاع التعديل — ما تضيّقهاش.**
    // `INSERT … ON CONFLICT DO UPDATE` بيفحص الصف الموجود بسياسة SELECT كمان مش
    // UPDATE بس. لما القراية كانت `user_id = auth.uid()` لوحدها، جلسة جديدة على
    // نفس الموبايل (مجهول جديد — الدين ٢) رجعت 42501 وهي بتكمّل على صف
    // تنزيلتها، والفحص الذاتي وقع على المشروع الحقيقي بالظبط عند الخطوة دي.
    final select = RegExp(r'create policy device_health_select[\s\S]*?;').firstMatch(code)!.group(0)!;
    expect(select, contains('using (user_id = (select auth.uid()) or private.owns_patient(patient_uuid))'));
    expect(select, isNot(contains('can_access_patient')), reason: 'الابن ما يشوفش صف موبايل أبوه');
    // owns_patient في القراية والتعديل بس — مش في الإدخال (42501 القديم)
    expect('owns_patient'.allMatches(code).length, 2);
    final insert = RegExp(r'create policy device_health_insert[\s\S]*?;').firstMatch(code)!.group(0)!;
    expect(insert, isNot(contains('owns_patient')));
    expect(sql, contains('for delete to authenticated\n  using (user_id = (select auth.uid()))'));
    expect(sql, contains('with check (user_id = (select auth.uid()) and private.can_access_patient(patient_uuid))'));
    expect(sql, contains('revoke all on public.device_health from anon, public;'));
    expect(RegExp(r'grant\s[^;]*\bto\s+[^;]*\banon\b', caseSensitive: false).hasMatch(sql), isFalse,
        reason: 'ولا grant لـanon');
    // grant واحد بس: EXECUTE لدالة قيد الأكواد على authenticated (القيد بيتنفّذ بصلاحية الكاتب)
    final grants = RegExp(r'\bgrant\b[^;]*;', caseSensitive: false)
        .allMatches(sql.replaceAll(RegExp(r'--[^\n]*'), ''))
        .map((m) => m.group(0)!)
        .toList();
    expect(grants, ['grant execute on function private.health_codes_ok(jsonb) to authenticated;'],
        reason: 'مفيش grant تاني — القراية للمالك من اللوحة');
  });

  test('الساكت: ٤٨ ساعة، جداول شغّالة بس، كل ساعة', () {
    expect(RegExp(r"function\s+private\.device_silent_after\s*\(\s*\)[\s\S]*?interval\s*'48\s*hours'").hasMatch(sql), isTrue);
    final body = RegExp(r"function\s+private\.mark_silent_devices[\s\S]*?\$\$;").firstMatch(sql)?.group(0);
    expect(body, isNotNull);
    expect(body, contains("set status = 'silent'"));
    expect(body, contains('private.device_silent_after()'));
    expect(body, contains('m.removed_at is null'));
    expect(body, contains('m.stopped_at is null'));
    expect(body, contains('s.stopped_at is null'));
    // موبايل المريض بس، وأحدث تنزيلة بس
    expect(body, contains('p.owner_id = h.user_id'));
    expect(body, contains('h2.user_id = p2.owner_id'));
    expect(body, contains('h2.checked_at > h.checked_at'));
    expect(sql, contains("cron.schedule(\n  'fakkarni-device-silent',\n  '7 * * * *',"));
  });

  test('الـview في private، security_invoker مقفول، ومسحوبة من anon/authenticated، وبأعمدة المواصفة', () {
    final view = RegExp(r"create view private\.admin_device_health[\s\S]*?;").firstMatch(sql)?.group(0);
    expect(view, isNotNull);
    expect(view, contains('with (security_invoker = false)'));
    for (final col in ['device_id', 'patient_id', 'status', 'codes', 'since', 'app_version', 'platform', 'last_seen']) {
      expect(view, contains(col), reason: 'عمود $col ناقص');
    }
    expect(view, contains("where h.status <> 'ok'"));
    expect(sql, contains('revoke all on private.admin_device_health from anon, authenticated, public;'));
    // ولا بيان طبي: الـview بتقرا device_health وبس
    expect(RegExp(r'from\s+public\.(medications|dose_events|records|readings|vitals)', caseSensitive: false).hasMatch(view!), isFalse);
  });

  test('التصعيد والإشعارات ما اتلمسوش', () {
    expect(sql, isNot(contains('due_escalations')));
    expect(sql, isNot(contains('escalations')));
    expect(sql, isNot(contains('pg_net')));
  });

  test('الفحص الذاتي آخر جملة في الملف', () {
    final check = sql.indexOf('-- ================================================================ فحص ذاتي');
    expect(check, greaterThan(0));
    final after = sql.substring(check);
    expect(RegExp(r'^(create|alter|grant|revoke|drop|select cron)\s', multiLine: true).hasMatch(after), isFalse,
        reason: 'فيه جملة بعد الفحص الذاتي');
    expect(after.trimRight().endsWith(r'end $$;'), isTrue);
    expect(sql.indexOf('create trigger device_health_status_since'), lessThan(check));
    expect(sql.indexOf("cron.schedule(\n  'fakkarni-device-silent'"), lessThan(check));
    // وبيختبر الأربع سكك: صاحب، جلسة تانية، غريب، ابن — والساكت والـview
    for (final probe in ["'set local role authenticated'", 'insufficient_privilege', 'mark_silent_devices()', 'private.admin_device_health', 'check_violation']) {
      expect(after, contains(probe));
    }
  });

  test('verify_migrations.sql فيها صفوف 0037 وبتعرف تفحص view', () {
    final verify = File('supabase/verify_migrations.sql').readAsStringSync();
    for (final ident in [
      "('0037_device_self_check', 'column',   'public.device_health.status')",
      "('0037_device_self_check', 'column',   'public.device_health.codes')",
      "('0037_device_self_check', 'column',   'public.device_health.user_id')",
      "('0037_device_self_check', 'column',   'public.device_health.status_since')",
      "('0037_device_self_check', 'constraintdef', 'public.device_health|device_health_status_check|silent')",
      "('0037_device_self_check', 'policy',   'public.device_health|device_health_select')",
      "('0037_device_self_check', 'function', 'private.mark_silent_devices')",
      "('0037_device_self_check', 'function', 'private.device_silent_after')",
      "('0037_device_self_check', 'trigger',  'public.device_health|device_health_status_since')",
      "('0037_device_self_check', 'view',     'private.admin_device_health')",
      "('0037_device_self_check', 'cron',     'fakkarni-device-silent')",
    ]) {
      expect(verify, contains(ident), reason: 'صف ناقص في verify: $ident');
    }
    expect(verify, contains("when 'view' then exists ("));
  });

  test('حدود الأكواد في SQL (٢٠ عنصر، ٤٠ حرف) واسعة لقايمة HealthCode كلها', () {
    final fn = RegExp(r"function private\.health_codes_ok[\s\S]*?\$\$;").firstMatch(sql)!.group(0)!;
    final maxItems = int.parse(RegExp(r'jsonb_array_length\(p_codes\) <= (\d+)').firstMatch(fn)!.group(1)!);
    final maxLen = int.parse(RegExp(r"char_length\(e\.v #>> '\{\}'\) > (\d+)").firstMatch(fn)!.group(1)!);
    expect(maxItems, 20);
    expect(maxLen, 40);
    expect(fn, contains("jsonb_typeof(e.v) <> 'string'"));
    // جهاز كل أكواده مكسورة لازم صفّه يعدّي القيد — وإلا النبضة بتقع بـ23514 في صمت
    expect(HealthCode.values.length, lessThanOrEqualTo(maxItems),
        reason: 'كود جديد عدّى حد ٢٠ — وسّع القيد في ترحيل جديد قبل ما تضيفه');
    for (final c in HealthCode.values) {
      expect(c.name.length, lessThanOrEqualTo(maxLen), reason: c.name);
    }
    // والفحص الذاتي بيجرّب الرفض والحد
    expect(sql, contains("codes = '[1]'::jsonb"));
    expect(sql, contains("repeat('y', 50)"));
    expect(sql, contains('generate_series(1, 21)'));
  });

  test('الفحص الذاتي بيجرّب: الابن ما يعدّلش صف أبوه، والساكت موبايل المريض وأحدث تنزيلة بس', () {
    final check = sql.substring(sql.indexOf('-- ================================================================ فحص ذاتي'));
    expect(check, contains("get diagnostics v_n = row_count"));
    expect(check, contains("'FAIL 0037: الابن عدّل صف موبايل أبوه"));
    expect(check, contains("'FAIL 0037: الابن خد صف موبايل أبوه بالـupsert'"));
    expect(check, contains("'FAIL 0037: الابن مقدرش يحدّث صفّه هو'"));
    expect(check, contains("'FAIL 0037: موبايل الابن اتعلّم ساكت'"));
    expect(check, contains("'install-old'"));
    expect(check, contains("'FAIL 0037: صاحب المريض مش شايف صفوف مريضه"));
    expect(check, contains("'FAIL 0037: الابن شايف صف غير صفّه"));
  });
}
