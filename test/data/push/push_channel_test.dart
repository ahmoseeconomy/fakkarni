// قناة الابن اسمها مكتوب مرتين: مرة في دارت ومرة في TypeScript. ولا
// واحدة فيهم بتعرف التانية.
//
// ولو اتفرقوا، **مفيش خطأ بيبان في أي مكان**: أندرويد بيستلم إشعار
// بقناة مش موجودة فيرميه على القناة الافتراضية، فيوصل بأولوية عادية —
// أو ما يوصلش لو المستخدم سكّتها. تنبيه آخر درجة في السلّم بيبوظ في
// صمت. نفس منطق `server_grace_sql_test.dart` بالظبط.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/notifications/notification_service.dart';

const _function = 'supabase/functions/escalate/index.ts';

void main() {
  test('اسم قناة الابن واحد في دارت وفي الدالة السحابية', () {
    final file = File(_function);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'مش لاقي $_function — لو اتنقل، ظبّط المسار ده مش امسح '
          'الاختبار؛ الاسمين لسه محتاجين رابط.',
    );

    final match = RegExp(r"CAREGIVER_CHANNEL\s*=\s*'([^']+)'")
        .firstMatch(file.readAsStringSync());

    expect(
      match,
      isNotNull,
      reason: 'مش لاقي CAREGIVER_CHANNEL في $_function. اتغيّر اسمه؟ '
          'الاسمين لازم يفضلوا مربوطين.',
    );
    expect(
      match!.group(1),
      NotificationService.caregiverChannelId,
      reason: 'القناة في الدالة السحابية «${match.group(1)}» وفي دارت '
          '«${NotificationService.caregiverChannelId}». أندرويد هيرمي '
          'التنبيه على القناة الافتراضية من غير ما يشتكي.',
    );
  });
}
