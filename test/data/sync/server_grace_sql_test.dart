// مهلة السيرفر مكتوبة مرتين — مرة في دارت ومرة في SQL — لأن Postgres
// ما بيقدرش يقرا دارت ومفيش طريقة تخلّيها رقم واحد.
//
// الاختبار ده هو الحاجة الوحيدة اللي واقفة بين النسختين والانحراف. ولو
// انحرفوا، العطل **مش** بناء فاشل ولا استثناء: الكرون بيصعّد بدري أو
// بمتأخر، والنتيجة إنذار كاذب على موبايل ابن بيتقلق على أبوه، أو تنبيه
// بيتأخر عن جرعة اتنست فعلاً. عطل بيتشاف في بيت حد، مش في CI.
//
// بيقرا ملف الترحيل نفسه — مش تعليق عنه. تعليق بيقول «٦٠ دقيقة» بينحرف
// عن الـSQL اللي تحته بنفس سهولة ما الـSQL بينحرف عن دارت، وساعتها
// الاختبار بيحرس جملة مش رقم.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/escalation/escalation_ladder.dart';

/// الملف اللي فيه الرقم. المسار نسبي لجذر الحزمة — `flutter test` بيشتغل
/// من هناك.
const _migration = 'supabase/migrations/0006_push.sql';

/// الدالة اللي `due_escalations` مجبرة تعدّي عليها، وجسمها.
final _graceInSql = RegExp(
  r"function\s+private\.server_grace_window\s*\(\s*\)"
  r"[\s\S]*?interval\s*'(\d+)\s*minutes'",
);

/// أي مهلة بالدقايق في الملف كله — عشان نكشف نسخة تانية من الرقم.
final _anyMinutesInterval = RegExp(r"interval\s*'(\d+)\s*minutes'");

void main() {
  group('مهلة السيرفر: دارت و SQL لازم يقولوا نفس الرقم', () {
    late String sql;

    setUp(() {
      final file = File(_migration);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'مش لاقي $_migration. لو الترحيل اتنقل أو اتشال، الرقم في '
            'SQL بقى من غير حارس — اظبط المسار ده، ما تشلش الاختبار.',
      );
      sql = file.readAsStringSync();
    });

    test('الرقم اللي الفحص بيستعمله = serverGraceWindow', () {
      final match = _graceInSql.firstMatch(sql);

      // الحراسة الأهم: regex ما لقاش حاجة بيعدّي في صمت للأبد. لازم يقع.
      expect(
        match,
        isNotNull,
        reason: 'مش لاقي private.server_grace_window() وجواها '
            "interval '<رقم> minutes' في $_migration. "
            'اتغيّر اسم الدالة؟ الرقم لسه محتاج حارس — رجّعه أو عدّل '
            'الـregex، بس ما تسيبش الرقمين من غير رابط.',
      );

      expect(
        int.parse(match!.group(1)!),
        serverGraceWindow.inMinutes,
        reason: 'مهلة السيرفر في SQL = ${match.group(1)} دقيقة، وفي دارت = '
            '${serverGraceWindow.inMinutes} دقيقة. الاتنين لازم يتحركوا مع '
            'بعض: الفرق بيظهر كإنذار كاذب على موبايل الابن، مش كخطأ هنا.',
      );
    });

    test('الرقم مكتوب في مكان واحد بس في الـSQL', () {
      // نسخة تانية من المهلة في أي مكان تاني في الملف معناها إن الفحص
      // ممكن يمشي على رقم الاختبار ده ما بيبصّش له.
      final all = _anyMinutesInterval.allMatches(sql);
      expect(
        all.length,
        1,
        reason: 'لقينا ${all.length} مهلة بالدقايق في $_migration: '
            '${all.map((m) => m.group(0)).join('، ')}. '
            'المفروض واحدة بس — جوّه server_grace_window(). أي نسخة تانية '
            'بتفلت من الحارس ده.',
      );
    });

    test('الثابت الحاكم: مهلة السيرفر = مهلة الجهاز + هامش السلك بالظبط', () {
      // مش «أكبر من» — **بالظبط**. `syncSlack` معرَّف إنه المسافة بين
      // الاتنين، فالعلاقة دي هوية مش متراجحة: أي تلاتة أرقام تانية معناها
      // إن واحد منهم اتحرك لوحده. متكرر هنا عن قصد، لأن اللي هيعدّل ٦٠
      // هيفتح الملف ده.
      expect(serverGraceWindow, graceWindow + syncSlack);
    });
  });
}
