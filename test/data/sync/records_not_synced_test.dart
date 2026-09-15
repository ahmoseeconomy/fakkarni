import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// الملف الصحي على الموبايل ده بس (PHASE_D3). مزامنته قرار يتقال بصوت عالي.
void main() {
  test('SyncService وريموت السحابة ما بيلمسوش records ولا readings ولا lab_results', () {
    for (final path in ['lib/data/sync/sync_service.dart', 'lib/data/sync/supabase_sync_remote.dart']) {
      final source = File(path).readAsStringSync();
      for (final table in ['records', 'readings', 'labResults', 'lab_results', 'visitQuestions', 'visit_questions']) {
        expect(RegExp('\\b$table\\b').hasMatch(source), isFalse, reason: '$path → $table');
      }
    }
  });
}
