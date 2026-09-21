import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **مكوّن ناقص في الـmanifest بيقع في صمت — فلازم يقع بصوت هنا.**
///
/// `flutter_local_notifications` ما بيعلنش ولا مستقبِل واحد في الـmanifest
/// بتاعه (اتأكدنا من مصدر النسخة المثبّتة: فيه إذنين وبس). التطبيق هو
/// اللي بيعلنهم، وأي واحد ناقص مالوش أي أثر وقت البناء ولا وقت التشغيل:
/// أندرويد بيبعت الـbroadcast لمكوّن مش موجود وبيرميه.
///
/// ده اللي حصل فعلاً: `ActionBroadcastReceiver` مكانش معلن، فدوسة على
/// «أخدته» أو «فكّرني بعدين» عمرها ما وصلت دارت على أي جهاز أندرويد —
/// الإشعار بيختفي (النظام بيشيله)، مفيش صف جرعة بيتكتب، ومفيش خطأ في أي
/// لوج. المريض فاكر إنه أكّد، والسلّم بيفضل بيرن لابنه.
///
/// التلاتة مطلوبين من README بتاع الإضافة:
///   - `ScheduledNotificationReceiver`      — الإشعار المجدول يرن أصلاً
///   - `ScheduledNotificationBootReceiver`  — يرجع بعد الريستارت
///   - `ActionBroadcastReceiver`            — أزرار الإشعار توصل دارت
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  const package = 'com.dexterous.flutterlocalnotifications';

  /// بيدوّر على إعلان `<receiver>` حقيقي بالاسم ده — مش على ذكر الاسم في
  /// تعليق. أي مسافات/أسطر بين السمات عادية، فالمقارنة على وجود السمة
  /// جوّه أقرب وسم `<receiver … />` أو `<receiver …>`.
  bool declares(String name) {
    for (final match
        in RegExp(r'<receiver\b[^>]*>', dotAll: true).allMatches(manifest)) {
      final tag = match.group(0)!;
      if (tag.contains('android:name="$package.$name"')) return true;
    }
    return false;
  }

  test('الإشعار المجدول ليه مستقبِل', () {
    expect(declares('ScheduledNotificationReceiver'), isTrue);
  });

  test('التذكيرات بترجع بعد الريستارت', () {
    expect(declares('ScheduledNotificationBootReceiver'), isTrue);
  });

  test('أزرار الإشعار ليها مستقبِل — من غيره الدوسة بتضيع في صمت', () {
    expect(
      declares('ActionBroadcastReceiver'),
      isTrue,
      reason: 'من غيره «أخدته» و«فكّرني بعدين» عمرهم ما هيوصلوا دارت، '
          'والإشعار بيختفي كإن الجرعة اتأكّدت',
    );
  });

  test('كل المستقبِلات مقفولة على التطبيق', () {
    for (final match
        in RegExp(r'<receiver\b[^>]*>', dotAll: true).allMatches(manifest)) {
      final tag = match.group(0)!;
      if (!tag.contains(package)) continue;
      expect(tag, contains('android:exported="false"'),
          reason: 'مستقبِل الإضافة مالوش أي داعي يكون مفتوح لبرّه: $tag');
    }
  });
}
