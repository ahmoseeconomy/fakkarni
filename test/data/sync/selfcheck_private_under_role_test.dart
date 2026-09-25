import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **درس 3f74e5c**: `authenticated` مالوش USAGE على سكيما `private` (وده
/// صح — السياسات بتتحلّل وقت إنشائها). فأي فحص ذاتي بينده `private.*`
/// مباشرة بعد `set local role authenticated` بيقع على المشروع الحقيقي بـ
/// «permission denied for schema private»، والهجرة كلها بترجع. الاختبار
/// بيدوّر على النداء ده بين `set local role authenticated` وأول `reset role`
/// بعده. الفحص لازم يمشي من خلال الجداول وRLS.
void main() {
  test('ولا فحص ذاتي بينده private.* تحت دور authenticated', () {
    final offenders = <String>[];
    final files = Directory('supabase/migrations').listSync().whereType<File>().where((f) => f.path.endsWith('.sql'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      var underRole = false;
      for (final (i, raw) in lines.indexed) {
        final line = raw.split('--').first;
        if (line.contains("set local role authenticated")) underRole = true;
        if (line.contains("reset role")) underRole = false;
        if (underRole && line.contains('private.') && !line.contains('set local role')) {
          offenders.add('${file.path}:${i + 1}: ${raw.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
