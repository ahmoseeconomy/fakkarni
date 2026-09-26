import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `debugPrint` مالهاش بوابة — بتطبع في release كمان (توثيقها بيقول كده
/// بالنص). فكل سطر تشخيص في التطبيق كان بيشحن جوّه الـIPA والـAPK.
///
/// والبوابة الغلط هي `kDebugMode`: نسخة profile هي الوحيدة اللي تقدر ترد
/// على سؤال صحوة شاشة القفل على iOS، وتشخيص متقفل على debug بيسكت فيها
/// بالظبط. فالقاعدة: **بيطبع بس → `diag` (`!kReleaseMode`)؛ بيظهر على
/// الشاشة → `kDebugMode`.**
void main() {
  /// سكّة صحوة شاشة القفل كلها — دي السطور اللي بتتقرا في Console.app
  /// في نسخة profile، ومحدش غيرها بيشوف الطريق ده.
  const wakeUpPath = [
    'lib/app/bootstrap.dart',
    'lib/core/notifications/background_task.dart',
    'lib/core/notifications/notification_service.dart',
    'lib/data/services/notification_actions.dart',
    'lib/data/sync/sync_service.dart',
  ];

  test('مفيش debugPrint عريانة على سكّة الصحوة — كلها من خلال diag', () {
    final offenders = <String>[];
    for (final path in wakeUpPath) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('///')) continue;
        if (line.contains('debugPrint(')) offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'debugPrint بتشحن في release. استعمل diag من '
            'lib/core/diagnostics.dart — بتطبع في debug وprofile وبس.');
  });

  test('diag بوابتها kReleaseMode، مش kDebugMode', () {
    final code = File('lib/core/diagnostics.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('///'))
        .join('\n');
    // release: ساكتة إلا لو باب المطوّر مفتوح — وساعتها ملف بس، من غير طباعة
    expect(code, contains('if (kReleaseMode && !_releaseOptIn()) return;'));
    expect(code, contains('if (!kReleaseMode) debugPrint(line);'),
        reason: 'debugPrint عمرها ما تطلع في release حتى والباب مفتوح');
    expect(code, isNot(contains('kDebugMode')),
        reason: 'على kDebugMode التشخيص بيسكت في نسخة profile — وهي '
            'الوحيدة اللي تقدر تشغّل صحوة شاشة القفل على iOS');
  });
}
