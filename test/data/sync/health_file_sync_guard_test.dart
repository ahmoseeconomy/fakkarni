import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// D5.1 رفع الملف الصحي للسحابة — بصوت عالي، مكان الحارسين اللي كانوا بيمنعوا
// المزامنة دي خالص (records_not_synced / emergency_not_synced). اللي فضل
// ممنوع بالاسم:
//
// * **أرقام تليفونات الطوارئ** (`contacts_json`) — السيرفر ما بيشيلش ولا رقم
//   تليفون. رفعها قرار خصوصية لوحده، مش سطر يتضاف في صمت.
// * **مسار الصورة المحلي** (`attachment_path`) — مالوش معنى برّه الموبايل؛
//   الصور في D5.3 بمفتاح تخزين.
void main() {
  /// كل ملف بيبني حمولة سحابة — الرفع **وقراية الابن**. الاتنين بيسمّوا
  /// أعمدتهم بالاسم، فالاسم هو الحارس: لو ظهر هنا يبقى خرج من الموبايل.
  final cloudFiles = [
    ...Directory('lib/data/sync').listSync(),
    ...Directory('lib/data/care').listSync(),
  ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('فيه ملفات سحابة تتقرا أصلاً', () {
    expect(cloudFiles, isNotEmpty);
  });

  test('ولا حمولة سحابة فيها أرقام تليفونات الطوارئ ولا مسار الصورة المحلي', () {
    for (final file in cloudFiles) {
      final source = file.readAsStringSync();
      // `follow_source_id` انضم للقايمة في جولة ٢٤: ده `id` داخلي بتاع صف
      // على الموبايل ده، ومالوش أي معنى في السحابة — نفس سبب مسار الصورة.
      for (final name in [
        'contactsJson',
        'contacts_json',
        'attachmentPath',
        'attachment_path',
        'followSourceId',
        'follow_source_id',
      ]) {
        expect(source.contains(name), isFalse, reason: '${file.path} → $name');
      }
    }
  });

  test('والسحابة مالهاش عمود ليهم أصلاً', () {
    final sql = File('supabase/migrations/0012_health_file.sql').readAsStringSync();
    final tables = RegExp(r'create table if not exists[\s\S]*?\n\);').allMatches(sql).map((m) => m.group(0)!).join('\n');
    expect(tables, isNot(contains('contacts')));
    expect(tables, isNot(contains('attachment')));
    final follow = File('supabase/migrations/0017_follow_kind.sql').readAsStringSync();
    expect(follow.contains('add column if not exists follow_source_id'), isFalse);
  });
}
