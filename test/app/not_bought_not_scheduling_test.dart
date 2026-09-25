import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «لسه ماتشترتش» تذكرة شرا — **التذكير والتصعيد عمرهم ما بيقروها**.
void main() {
  test('الجدولة والسلّم وخطة الإشعارات ما فيهمش not_bought / notBought', () {
    final files = [
      ...Directory('lib/domain/scheduling').listSync(recursive: true),
      ...Directory('lib/domain/escalation').listSync(recursive: true),
      File('lib/data/services/reminder_plan.dart'),
      File('lib/data/services/reminder_scheduler.dart'),
      File('lib/data/services/notification_actions.dart'),
      File('lib/core/notifications/notification_service.dart'),
    ].whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(src.contains('notBought') || src.contains('not_bought'), isFalse, reason: f.path);
    }
  });

  test('ولا تعريف due_escalations في أي هجرة بيقرا not_bought_at', () {
    for (final f in Directory('supabase/migrations').listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      final i = src.indexOf('function private.due_escalations');
      if (i < 0) continue;
      final end = src.indexOf(r'$$;', src.indexOf(r'$$', i) + 2);
      expect(src.substring(i, end < 0 ? src.length : end).contains('not_bought'), isFalse, reason: f.path);
    }
  });
}
