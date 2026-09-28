// مهلة الممرض (0035) مكتوبة مرتين — دارت وSQL — ونفس قاعدة مهلة الابن:
// Postgres ما بيقدرش يقرا دارت، والانحراف بينهم بيبان كتنبيه بدري أو
// متأخر على موبايل ممرض، مش كبناء فاشل. الاختبار هو الحارس الوحيد.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/escalation/escalation_ladder.dart';

const _migration = 'supabase/migrations/0035_nurse_full_edit.sql';

final _graceInSql = RegExp(
  r"function\s+private\.nurse_grace_window\s*\(\s*\)"
  r"[\s\S]*?interval\s*'(\d+)\s*minutes'",
);

void main() {
  late String sql;

  setUp(() {
    final file = File(_migration);
    expect(file.existsSync(), isTrue, reason: 'مش لاقي $_migration');
    sql = file.readAsStringSync();
  });

  test('nurse_grace_window في SQL = nurseGraceWindow في دارت', () {
    final match = _graceInSql.firstMatch(sql);
    expect(match, isNotNull, reason: 'مش لاقي private.nurse_grace_window() في الملف');
    expect(int.parse(match!.group(1)!), nurseGraceWindow.inMinutes);
  });

  test('الممرض قبل الابن — والابن زي ما هو', () {
    expect(nurseGraceWindow < serverGraceWindow, isTrue);
    expect(serverGraceWindow.inMinutes, 60, reason: 'مهلة الابن ما اتلمستش');
  });

  test('due_nurse_escalations بتعدّي على nurse_grace_window ومفتاح الممرض، والدرجة nurse', () {
    final body = RegExp(r"function\s+private\.due_nurse_escalations[\s\S]*?\$\$;").firstMatch(sql)?.group(0);
    expect(body, isNotNull);
    expect(body, contains('private.nurse_grace_window()'));
    expect(body, contains('private.nurse_unconfirmed_alert_on('));
    expect(body, contains("e.rung            = 'nurse'"));
    expect(body, contains("cr.role   = 'nurse'"));
    expect(body, contains('proxy_confirmations'), reason: 'التأكيد نيابةً بيسكّت الممرض التاني كمان');
  });

  test('due_escalations بتاعة الابن ما اتلمستش في 0035', () {
    expect(sql, isNot(contains('function private.due_escalations(')));
  });

  test('إشارة «اتأكّدت» للجرعات اللي معادها في آخر ٢٤ ساعة بس — التريجرين بيعدّوا على النافذة', () {
    expect(RegExp(r"function\s+private\.confirm_signal_window\s*\(\s*\)[\s\S]*?interval\s*'24\s*hours'").hasMatch(sql), isTrue);
    final taken = RegExp(r"function\s+private\.on_dose_taken[\s\S]*?\$\$;").firstMatch(sql)!.group(0)!;
    final proxy = RegExp(r"function\s+private\.on_proxy_confirmed[\s\S]*?\$\$;").firstMatch(sql)!.group(0)!;
    expect(taken, contains('private.confirm_signal_window()'));
    expect(proxy, contains('private.confirm_signal_window()'));
    expect(proxy, contains('public.dose_events'), reason: 'التأكيد نيابةً بيشوف معاد جرعته');
    // والفحص الذاتي بيثبتها بعدّاد
    expect(sql, contains("now() - interval '3 days', 'taken'"));
    expect(sql, contains('pg_temp.confirm_signal_calls'));
  });
}
