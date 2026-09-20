import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **التطبيق ما بيقراش دفتر العناوين — بيفتح شاشة النظام وبياخد اللي اتختار.**
///
/// الفرق مش تفصيلة: قراية الدفتر بتحتاج إذن، وبتدّي التطبيق كل الأسماء
/// والأرقام اللي على الموبايل. اللي إحنا بنعمله بياخد **جهة واحدة** —
/// اللي الشخص دوس عليها — ومفيش إذن أصلاً. والوعد المكتوب على الشاشة
/// («الأرقام دي على الموبايل ده بس») مبني على ده.
///
/// الحارس ده بيقفل تلات أبواب:
///   ١) استيراد الحزمة في ملف واحد بس ([_pluginFile]) — زي قاعدة
///      `supabase_*` / `firebase_*`.
///   ٢) `pickOne()` بتتندَه من مكان واحد في التطبيق: زرار «من جهات الاتصال».
///   ٣) ولا حاجة في `lib/` بتنده API بيعدّد جهات الاتصال.
const _pluginFile = 'lib/data/contacts/native_contact_picker.dart';
const _theOneCaller = 'lib/features/emergency/emergency_edit_screen.dart';

List<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  final files = _dartFiles('lib');

  test('فيه ملفات تتقرا أصلاً', () => expect(files, isNotEmpty));

  test('حزمة جهات الاتصال متستوردة في ملف واحد بس', () {
    final importers = [
      for (final f in files)
        if (f.readAsStringSync().contains('package:flutter_native_contact_picker'))
          f.path.replaceAll(r'\', '/'),
    ];
    expect(importers, [_pluginFile]);
  });

  test('pickOne بتتندَه من زرار واحد — مش من أي مكان تاني', () {
    final callers = <String>[];
    for (final f in files) {
      final path = f.path.replaceAll(r'\', '/');
      // التعريف نفسه والتنفيذ مش نداءات
      if (path.startsWith('lib/data/contacts/')) continue;
      for (final raw in f.readAsLinesSync()) {
        final line = raw.trimLeft();
        if (line.startsWith('//') || line.startsWith('///')) continue;
        if (line.contains('pickOne(')) callers.add(path);
      }
    }
    expect(callers, [_theOneCaller],
        reason: 'جهات الاتصال بتتفتح من زرار «من جهات الاتصال» وبس');
  });

  test('ولا API بيعدّد دفتر العناوين في أي مكان', () {
    // `selectContacts` (جمع) بترجّع أكتر من واحدة، و`getContacts`/`FlutterContacts`
    // بيقروا الدفتر كله. ولا واحدة فيهم مستعملة — ولا المفروض تبقى.
    const forbidden = ['selectContacts', 'getContacts', 'FlutterContacts.', 'READ_CONTACTS'];
    final offenders = <String>[];
    for (final f in files) {
      final source = f.readAsStringSync();
      for (final name in forbidden) {
        if (source.contains(name)) offenders.add('${f.path} → $name');
      }
    }
    expect(offenders, isEmpty);
  });

  test('ومفيش إذن جهات اتصال متطلوب على الجهازين', () {
    // شاشة النظام بتشتغل **من غير إذن**: CNContactPickerViewController
    // بره عملية التطبيق، وACTION_PICK بيدّي صلاحية مؤقتة للصف المختار بس.
    // لو حد اضطر يضيف إذن، يبقى اختار طريق تاني — وده اللي الحارس ده ضده.
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('READ_CONTACTS'), isFalse);
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist.contains('NSContactsUsageDescription'), isFalse);
  });
}
