import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **باب واحد للمنصتين.**
///
/// الطريقين مختلفين ومش باختيارنا: iOS بيفتح التطبيق ويسيب الرد في
/// `getNotificationAppLaunchDetails` (اتثبت على آيفون حقيقي، cb0096d)،
/// وأندرويد بيصحّي isolate لوحده. اللي في إيدنا إن الاختلاف يفضل محبوس
/// في محوّلين رفيعين والشغل يفضل في دالة واحدة.
///
/// سكّة أندرويد **عمرها ما اشتغلت ولا مرة، على أي جهاز**. فكل سطر فيها
/// مش مشترك هو سطر مش متجرّب — والحارس ده بيمنع إن الطريقين يتفرّقوا
/// تاني من غير ما حد ياخد باله.
void main() {
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join('\n');

  final boot = code('lib/app/bootstrap.dart');
  final main = code('lib/main.dart');

  test('الدالة المشتركة موجودة وبتنده المعالج', () {
    expect(boot, contains('Future<void> handleNotificationAction('));
    expect(boot, contains('actionHandlerFor('));
    expect(boot, contains('.handle(actionId, payload)'));
  });

  test('باب أندرويد (الـisolate) بينده الدالة المشتركة', () {
    final entry = boot.indexOf('Future<void> onBackgroundNotificationAction(');
    expect(entry, isNot(-1));
    final body = boot.substring(entry);
    expect(body, contains('await handleNotificationAction('),
        reason: 'الـisolate لازم يعدّي من نفس الباب');
    expect(body, isNot(contains('actionHandlerFor(')),
        reason: 'لو بنى المعالج لوحده، الطريقين اتفرّقوا تاني');
  });

  test('باب iOS (رد الإطلاق) بينده نفس الدالة', () {
    expect(main, contains('handleNotificationAction('));
    expect(main, contains('door(launched.actionId'));
    expect(main, isNot(contains('actionHandlerFor(await buildServices')),
        reason: 'المقدمة كانت بتبني معالجها لوحدها قبل توحيد الباب');
  });

  test('الدوسة والتطبيق مفتوح بتعدّي من نفس الباب كمان', () {
    // شبكة الأمان دي كانت ثالث نسخة من نفس الشغل
    expect(main, contains('NotificationService.onAction = door'));
  });

  group('مساحة أندرويد وحدها', () {
    // الرقم ده هو اللي بنحاول نصغّره: كل سطر هنا سطر عمره ما اتنفّذ.
    int androidOnlyLines() {
      final lines = File('lib/app/bootstrap.dart').readAsLinesSync();
      final start = lines.indexWhere(
          (l) => l.contains('Future<void> onBackgroundNotificationAction('));
      expect(start, isNot(-1));
      var depth = 0;
      var counted = 0;
      for (var i = start; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        final isComment = trimmed.startsWith('//');
        if (!isComment && trimmed.isNotEmpty) counted++;
        depth += '{'.allMatches(line).length - '}'.allMatches(line).length;
        if (i > start && depth == 0) break;
      }
      return counted;
    }

    test('محوّل أندرويد فضل رفيع — أقل من ٣٥ سطر كود', () {
      // لو الرقم ده كبر، يبقى فيه منطق رجع يتكتب في الطريق اللي مفيش
      // جهاز بيجربه. حطّه في الدالة المشتركة.
      expect(androidOnlyLines(), lessThan(35),
          reason: 'كل سطر هنا مش متجرّب على أي جهاز');
    });
  });
}
