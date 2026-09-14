import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// الملف الصحي على الموبايل ده بس (PHASE_D3). مزامنته قرار يتقال بصوت عالي.
void main() {
  test('SyncService وريموت السحابة ما بيلمسوش records', () {
    for (final path in ['lib/data/sync/sync_service.dart', 'lib/data/sync/supabase_sync_remote.dart']) {
      final source = File(path).readAsStringSync();
      expect(RegExp(r'\brecords\b').hasMatch(source), isFalse, reason: path);
    }
  });
}
