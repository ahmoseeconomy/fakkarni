import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// شيت «ضيف دوا» معرّف **مرة واحدة** — في `add_sheet.dart` — والدوك وكارت
/// «ضيف دوا» بينادوا نفس الدالة. نسخة تانية كانت هتتفرّق مع أول مدخل جديد.
void main() {
  final files = [
    for (final e in Directory('lib').listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart') && !e.path.startsWith('lib/macos')) e,
  ];
  String code(File f) => f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('FSheet بعنوان «ضيف دوا» بيتبني في add_sheet.dart وبس', () {
    final where = <String>[];
    for (final f in files) {
      final text = code(f);
      if (text.contains('title: addSheetTitle') || text.contains("title: 'ضيف دوا'")) where.add(f.path);
    }
    expect(where, ['lib/features/medication/add_sheet.dart']);
  });

  test('المكانين بينادوا showAddSheet — الدوك وجدول الأدوية', () {
    final callers = [
      for (final f in files)
        if (code(f).contains('showAddSheet(context') ) f.path,
    ];
    expect(callers, unorderedEquals(['lib/app/shell.dart', 'lib/features/medication/medications_screen.dart']));
  });
}
