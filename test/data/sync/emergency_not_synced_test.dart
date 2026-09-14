import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// بيانات الطوارئ على الموبايل ده بس (PHASE_D3): أرقام تليفونات وحساسية
// وأمراض. لو المزامنة بدأت تقراها، ده قرار لازم يتقال بصوت عالي — مش سطر
// يتضاف في صمت.
void main() {
  test('SyncService وريموت السحابة ما بيلمسوش emergency_profile', () {
    for (final path in ['lib/data/sync/sync_service.dart', 'lib/data/sync/supabase_sync_remote.dart']) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final source = file.readAsStringSync();
      expect(source.contains('emergency'), isFalse, reason: path);
    }
    expect(File('lib/data/sync/sync_service.dart').existsSync(), isTrue);
  });
}
