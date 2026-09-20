import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **تأكيد بيحطّ مريض لازم يعمل مالكه في `auth.users` الأول.**
///
/// `public.patients.owner_id` مفتاح أجنبي على `auth.users`، و`gen_random_uuid()`
/// مش مستخدم حقيقي. من غير السطر ده أول `insert into public.patients` بيقع
/// على المفتاح، والاستثناء بيطلع برّه الـsub-transaction فالسكريبت كله
/// بيترجع — يعني الترحيل نفسه **ما اتطبّقش**، والرسالة اللي بتطلع بتتكلم
/// عن المفتاح مش عن الأعمدة اللي إنت بتضيفها. ده اللي حصل في 0016 بالظبط.
///
/// الاختبار بيقرا ملفات SQL نفسها لأن Postgres مش بيتشغّل هنا — `flutter
/// test` عمره ما هيمسك ده، والمشروع الحقيقي هو اللي هيمسكه، وقتها يكون
/// الوقت اتضيّع.
void main() {
  final files = [
    ...Directory('supabase/migrations').listSync(),
    ...Directory('supabase/tests').listSync(),
  ].whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('فيه ملفات SQL تتقرا أصلاً', () {
    expect(files, isNotEmpty, reason: 'لو المسار اتغيّر، الاختبار ده بيبقى بيمرّ على فاضي');
  });

  for (final file in files) {
    final name = file.path.split(Platform.pathSeparator).last;
    final source = file.readAsStringSync().toLowerCase();
    final patients = source.indexOf('insert into public.patients');
    if (patients < 0) continue;

    test('$name: المالك بيتعمل في auth.users قبل أي مريض', () {
      final owner = source.indexOf('insert into auth.users');
      expect(
        owner,
        isNonNegative,
        reason: '$name بيحطّ مريض من غير ما يعمل مالكه — '
            'patients.owner_id هيقع على المفتاح الأجنبي والسكريبت كله هيترجع',
      );
      expect(
        owner,
        lessThan(patients),
        reason: '$name بيعمل المالك **بعد** المريض — نفس الوقوع بالظبط',
      );
    });
  }
}
