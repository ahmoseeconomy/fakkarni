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

  group('المريض ما يشوفش مشكلة تقنية — قرار المالك', () {
    // يا التطبيق بيصلّحها لوحده في صمت، يا بتروح للوحة الأدمن مع النبضة.
    // الاستثناء الوحيد: إذن التنبيهات مقفول — سطر واحد على «يومك» بزرار.
    final watcher = code('lib/data/health/health_watcher.dart');
    final settings = code('lib/features/settings/settings_screen.dart');

    test('المراقب ما بينبّهش ولا بيجدول — ولا إشعار سلامة خالص', () {
      expect(watcher, isNot(contains('showNow')));
      expect(watcher, isNot(contains('NotificationService')));
      expect(watcher, isNot(contains('zonedSchedule')));
      expect(watcher, isNot(contains('tapPayload')));
    });

    test('المراقب بيصلّح في صمت وبيسجّل بـdiag', () {
      expect(watcher, contains('class HealthAutoFix'));
      expect(watcher, contains("diag('Health: إصلاح آلي"));
    });

    test('شاشة الفحص مش موجودة في أي شاشة مريض — لا «يومك» ولا الجذر', () {
      final patientFiles = [
        ...Directory('lib/features/today').listSync(recursive: true),
        ...Directory('lib/features/elder').listSync(recursive: true),
        File('lib/app/root.dart'),
      ].whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in patientFiles) {
        final src = code(f.path);
        for (final name in ['HealthCheckScreen', 'health_check_screen', 'HealthBar', 'health_bar']) {
          expect(src, isNot(contains(name)), reason: '${f.path} بيفتح على شاشة الفحص');
        }
      }
      expect(File('lib/features/selfcheck/health_bar.dart').existsSync(), isFalse);
    });

    test('في الإعدادات: صف الفحص تحت «للمطوّر» وجوّه !kReleaseMode', () {
      // البوابة: مخفي في release إلا من باب المطوّر (٧ دوسات على سطر النسخة)
      expect(settings, contains('bool get developerVisible => !kReleaseMode || _devDoor;'));
      final gate = settings.indexOf('if (developerVisible)');
      final head = settings.indexOf("FSectionHead('للمطوّر')");
      final row = settings.indexOf("label: 'اطمن إن التذكير هيشتغل'");
      expect(gate, isNot(-1));
      expect(row, isNot(-1), reason: 'الشاشة لسه موجودة — للمطوّر');
      expect(row, greaterThan(head));
      expect(row, greaterThan(gate));
      // ومفيش صف تاني ليها قبل البوابة
      expect(settings.indexOf('HealthCheckScreen('), greaterThan(gate));
    });

    test('«يومك» بيعرض سطر الإذن وبس — بجملته المتفق عليها', () {
      final today = code('lib/features/today/today_screen.dart');
      expect(today, contains('NotificationsOffLine()'));
      final line = code('lib/features/today/notifications_off_line.dart');
      expect(line, contains("'التنبيهات مقفولة — افتحها عشان نفكّرك'"));
      expect(line, contains('HealthCode.notificationPermission'));
      // مفيش كود تاني بيتقرا هناك
      for (final other in HealthCodeNames.all.where((c) => c != 'notificationPermission')) {
        expect(line, isNot(contains('HealthCode.$other')), reason: 'كود $other وصل شاشة المريض');
      }
    });
  });
}

/// أسماء الأكواد — من الملف نفسه، عشان كود جديد يدخل الحارس لوحده.
class HealthCodeNames {
  static List<String> get all {
    final src = File('lib/domain/health/health_check.dart').readAsStringSync();
    final body = src.substring(src.indexOf('enum HealthCode {'), src.indexOf('\n}\n', src.indexOf('enum HealthCode {')));
    return [
      for (final m in RegExp(r'^\s+([a-zA-Z]+),', multiLine: true).allMatches(body)) m.group(1)!,
    ];
  }
}
