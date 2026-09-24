import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **كل خدمة سحابة لازم توصل الشاشات.**
///
/// جولات ٢٣–٢٥ زوّدت `careAdmin` و`proxy` و`medChanges` و`subscriptions`
/// لـ`CloudServices`، وما مرّرتهمش من `main` لـ`buildServices` — فعلى
/// الجهاز كانوا null: التأكيد نيابةً ما بيوصلش موبايل المريض، والاشتراك
/// ما اتبناش. واختبارات الشاشات كانت خضرا لأنها بتبني خدماتها بنفسها.
/// الحارس ده بيقرا الحقول من الـtypedef ويتأكد إن `main` بيقرا كل واحد.
void main() {
  test('كل حقل في CloudServices متقري في main.dart', () {
    final init = File('lib/data/auth/supabase_init.dart').readAsStringSync();
    final start = init.indexOf('typedef CloudServices');
    final body = init.substring(start, init.indexOf('});', start));
    final fields = RegExp(r'\b\w+\s+(\w+),').allMatches(body).map((m) => m.group(1)!).toList();
    expect(fields, containsAll(['careAdmin', 'proxy', 'medChanges', 'subscriptions', 'papers']),
        reason: 'الحارس نفسه لازم يشوف الحقول');

    final main = File('lib/main.dart').readAsStringSync();
    final missing = [
      for (final f in fields)
        if (!main.contains('cloud?.$f') && !main.contains('cloud.$f')) f,
    ];
    expect(missing, isEmpty, reason: 'خدمات سحابة مش متمرّرة من main: $missing');
  });

  test('والمرّرة في main بتوصل AppServices من buildServices', () {
    final boot = File('lib/app/bootstrap.dart').readAsStringSync();
    final ret = boot.substring(boot.indexOf('return AppServices('));
    for (final f in ['careAdmin', 'proxy', 'medChanges', 'subscription', 'papers']) {
      expect(ret.contains('$f:'), isTrue, reason: '$f مش واصل AppServices');
    }
  });
}
