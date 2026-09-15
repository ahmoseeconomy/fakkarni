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
  test('المزامنة ما بتلمسش أرقام تليفونات الطوارئ ولا مسار الصورة المحلي', () {
    for (final path in ['lib/data/sync/sync_service.dart', 'lib/data/sync/supabase_sync_remote.dart']) {
      final source = File(path).readAsStringSync();
      for (final name in ['contactsJson', 'contacts_json', 'attachmentPath', 'attachment_path']) {
        expect(source.contains(name), isFalse, reason: '$path → $name');
      }
    }
  });

  test('والسحابة مالهاش عمود ليهم أصلاً', () {
    final sql = File('supabase/migrations/0012_health_file.sql').readAsStringSync();
    final tables = RegExp(r'create table if not exists[\s\S]*?\n\);').allMatches(sql).map((m) => m.group(0)!).join('\n');
    expect(tables, isNot(contains('contacts')));
    expect(tables, isNot(contains('attachment')));
  });
}
