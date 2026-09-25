// حراس مسح الحساب اللي `flutter test` ما يقدرش يشغّلهم: الدالة (Deno) والـSQL
// (Postgres). بنقرا الملفات — الترتيب والصلاحيات والمرايات.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/account/account_deletion.dart';

String _read(String path) => File(path).readAsStringSync();

/// الملف من غير سطور التعليقات — عشان كلمة في شرح ما تعدّيش حارس.
String _code(String src, String comment) =>
    src.split('\n').where((l) => !l.trimLeft().startsWith(comment)).join('\n');

void main() {
  final fn = _code(_read('supabase/functions/delete-account/index.ts'), '//');
  final sql = _code(_read('supabase/migrations/0033_delete_account.sql'), '--');

  test('الدالة: الصور ← الصفوف ← المستخدم — المستخدم آخر حاجة', () {
    final handler = fn.substring(fn.indexOf('Deno.serve'));
    final storage = handler.indexOf('await deleteObjects(');
    final rows = handler.indexOf("'delete_account_for_service'");
    final auth = handler.indexOf('await deleteAuthUser(');
    expect([storage, rows, auth].every((i) => i > 0), isTrue, reason: 'الخطوات التلاتة لازم تكون في المعالج');
    expect(storage < rows && rows < auth, isTrue,
        reason: 'مستخدم اتمسح قبل صفوفه = بيانات يتيمة مالهاش صاحب يمسحها');
  });

  test('الدالة: المستخدم من جلسته — ومفتاح الخدمة من الأسرار بس، ومش مقبول كجلسة', () {
    expect(fn, contains("Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')"));
    expect(fn, contains('/auth/v1/user'), reason: 'المستخدم من GoTrue، مش من body');
    expect(fn, contains('jwt === SERVICE_KEY'), reason: 'مفتاح الخدمة مش جلسة مستخدم');
    expect(RegExp(r'eyJ[A-Za-z0-9_-]{20,}').hasMatch(fn), isFalse, reason: 'مفتاح مكتوب في الملف');
  });

  test('كلمة التأكيد مرآة بين دارت والدالة', () {
    expect(fn, contains("const CONFIRM = '$deleteAccountConfirm'"));
  });

  test('التطبيق عمره ما بيشيل مفتاح الخدمة', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      expect(f.readAsStringSync().contains('SERVICE_ROLE'), isFalse, reason: f.path);
    }
  });

  test('SQL: دالتين للخدمة بس — مسحوبين من authenticated ومتدّيين لـservice_role', () {
    for (final name in ['account_deletion_objects_for_service', 'delete_account_for_service']) {
      expect(sql, contains('revoke all on function public.$name(uuid)'), reason: name);
      expect(RegExp('revoke all on function public\\.$name\\(uuid\\)\\s+from anon, authenticated, public')
          .hasMatch(sql), isTrue, reason: name);
      expect(RegExp('grant execute on function public\\.$name\\(uuid\\)\\s+to service_role;').hasMatch(sql),
          isTrue, reason: name);
      expect(RegExp('grant execute on function public\\.$name\\(uuid\\)\\s+to authenticated').hasMatch(sql),
          isFalse, reason: name);
    }
  });

  test('SQL: سطر «خرج من الدايرة» بيتكتب قبل ما العلاقة تتشال', () {
    final body = sql.substring(sql.indexOf('function public.delete_account_for_service'));
    final departure = body.indexOf('insert into public.circle_departures');
    final unlink = body.indexOf('delete from public.care_relationships');
    expect(departure, greaterThan(0));
    expect(departure < unlink, isTrue, reason: 'بعد المسح مفيش علاقة نقرا منها الاسم');
  });

  test('SQL: التأكيد نيابةً بيفضل (من غير اسم) — والتصعيد ما اتلمسش', () {
    expect(sql, contains('update public.proxy_confirmations set actor_id = null, actor_name = null'));
    expect(sql, isNot(contains('delete from public.proxy_confirmations')),
        reason: 'التأكيد لو اتمسح، due_escalations ينبّه الابن عن حباية اتاخدت');
    expect(sql.contains('due_escalations'), isFalse, reason: '0033 ما بتعيدش تعريف التصعيد');
  });

  test('SQL: العدّاد مجهول — يوم ونوع وبس', () {
    final table = sql.substring(sql.indexOf('create table if not exists private.account_deletions'));
    final body = table.substring(table.indexOf('(') + 1, table.indexOf(');'));
    // اسم كل عمود = أول كلمة في سطره
    final cols = [
      for (final line in body.split('\n'))
        if (line.trim().isNotEmpty) line.trim().split(RegExp(r'\s+')).first,
    ];
    expect(cols, ['id', 'deleted_on', 'kind'], reason: 'عمود زيادة في العدّاد المجهول');
  });
}
