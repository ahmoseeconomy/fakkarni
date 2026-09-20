import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **الترتيب اختبار، مش تعليق.**
///
/// كسرنا الترتيب ده مرتين في يوم واحد: مرة في الـisolate (تهيئة سحابة
/// قبل صف الجرعة) ومرة في `main` (تهيئة سحابة وتوكن دفع قبل رد الإطلاق).
/// فحص السلامة مجاملة زيهم بالظبط — ولو اتحط قبل الوعد بقى هو العيب.
void main() {
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('فحص السلامة بعد الوعد، مش قبله', () {
    test('في main: بعد معالجة رد الإطلاق وبعد إعادة الجدولة', () {
      final main = code('lib/main.dart');
      final handled = main.indexOf('door(launched.actionId');
      final rescheduled = main.indexOf('services.scheduler.rescheduleAll()');
      final health = main.indexOf('HealthWatcher(');

      expect(handled, isNot(-1));
      expect(health, isNot(-1), reason: 'الفحص مش متوصّل أصلاً');
      expect(health, greaterThan(handled),
          reason: 'الجرعة بتتكتب الأول — الفحص مجاملة');
      expect(health, greaterThan(rescheduled),
          reason: 'المدى بيتقرا من pending() بعد ما الجدولة تخلص');
    });

    test('في main: الفحص مش متستنى قبل runApp', () {
      final main = code('lib/main.dart');
      expect(main, contains('unawaited(HealthWatcher('),
          reason: 'شاشة المريض ما تستناش فحص');
    });

    test('في bootstrap: صحوة شاشة القفل مفيهاش فحص خالص', () {
      // الصحوة دي عمرها ثواني وإطلاقها في الخلفية ممكن ما يعيشش —
      // أي قراية زيادة فيها بتتصرف من وقت تسجيل الجرعة نفسه.
      final boot = code('lib/app/bootstrap.dart');
      for (final name in ['HealthWatcher', 'HealthCollector', 'runHealthChecks']) {
        expect(boot, isNot(contains(name)),
            reason: 'الفحص مالوش مكان في سكّة الصحوة');
      }
    });
  });

  group('تنبيه السلامة معروض، مش متجدول', () {
    // سقف iOS ٦٤ إشعار **معلّق** والأربعة وستين متوزّعين خلاص. إشعار
    // متجدول من هنا بياخد خانة من جرعة حقيقية — يعني التنبيه اللي بيقول
    // «التذكير ممكن ما يشتغلش» هو نفسه اللي بيعطّله.
    final service = code('lib/core/notifications/notification_service.dart');
    final watcher = code('lib/data/health/health_watcher.dart');

    test('showNow بتستعمل show، ومفيش zonedSchedule جواها', () {
      final start = service.indexOf('static Future<void> showNow(');
      expect(start, isNot(-1));
      final body = service.substring(start, service.indexOf('\n  }\n', start));
      expect(body, contains('_plugin.show('));
      expect(body, isNot(contains('zonedSchedule')));
    });

    test('المراقب بينده showNow وبس — مفيش جدولة من ناحيته', () {
      expect(watcher, contains('NotificationService.showNow('));
      expect(watcher, isNot(contains('zonedSchedule')));
      expect(watcher, isNot(contains('scheduleReminder')));
    });

    test('رقم التنبيه برّه كل النطاقات المحجوزة', () {
      // أي رقم جوّه نطاق بتاع جرعة أو سلّم كان هيلغي تذكير حقيقي
      expect(watcher, contains('alertNotificationId = 60000001'));
    });
  });
}
