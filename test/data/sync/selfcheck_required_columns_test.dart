// 0035 وقعت على المشروع الحقيقي بـ`23502 null value in column "repeat"`:
// الفحص الذاتي كتب صف جدول من غير الأعمدة اللي `not null` من غير default.
// Postgres مش بيجري في `flutter test`، فالاختبار ده بيستخرج الأعمدة دي من
// ملفات الترحيل نفسها (create table + add column، 0001–0034) وبيقارنها بكل
// `insert into public.…` في الفحص الذاتي لكل ترحيل من 0035 وطالع (الأعمدة
// المطلوبة من كل اللي قبله ومنه هو) — وبيوقع على العمود الناقص بالاسم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الأعمدة اللي لازم تتكتب لكل جدول — من الملفات، مش من الذاكرة.
Map<String, Set<String>> requiredColumns(List<File> migrations) {
  final columns = <String, Map<String, ({bool notNull, bool hasDefault})>>{};
  for (final f in migrations) {
    final sql = f.readAsStringSync().replaceAll(RegExp(r'--[^\n]*'), '');
    for (final m in RegExp(r'create table if not exists\s+([\w.]+)\s*\(([\s\S]*?)\n\);').allMatches(sql)) {
      final cols = columns.putIfAbsent(m.group(1)!, () => {});
      for (final part in _splitTopLevel(m.group(2)!)) {
        final p = part.trim();
        if (p.isEmpty || RegExp(r'^(constraint|unique|primary key|check|foreign key)\b', caseSensitive: false).hasMatch(p)) continue;
        final name = p.split(RegExp(r'\s+')).first;
        final low = p.toLowerCase();
        cols[name] = (
          notNull: low.contains('not null') || low.contains('primary key'),
          hasDefault: low.contains('default') || low.contains('generated'),
        );
      }
    }
    for (final m in RegExp(r'alter table\s+([\w.]+)\s+((?:add column[^;]*?)(?:,\s*add column[^;]*?)*);', caseSensitive: false, dotAll: true).allMatches(sql)) {
      final cols = columns.putIfAbsent(m.group(1)!, () => {});
      for (final a in RegExp(r'add column(?: if not exists)?\s+(\w+)([^,;]*)', caseSensitive: false).allMatches(m.group(2)!)) {
        final low = a.group(2)!.toLowerCase();
        cols[a.group(1)!] = (notNull: low.contains('not null'), hasDefault: low.contains('default'));
      }
    }
  }
  return {
    for (final e in columns.entries) e.key: {for (final c in e.value.entries) if (c.value.notNull && !c.value.hasDefault) c.key},
  };
}

List<String> _splitTopLevel(String body) {
  final parts = <String>[];
  var depth = 0;
  final cur = StringBuffer();
  for (final ch in body.split('')) {
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (ch == ',' && depth == 0) {
      parts.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  parts.add(cur.toString());
  return parts;
}

/// كل `insert into public.<table> (cols)` في ملف — بأعمدته.
List<({String table, Set<String> columns, int line})> insertsIn(String sql) => [
      for (final m in RegExp(r'insert into\s+(public\.\w+)\s*\(([^)]*)\)', caseSensitive: false).allMatches(sql))
        (
          table: m.group(1)!.toLowerCase(),
          columns: {for (final c in m.group(2)!.split(',')) c.trim().toLowerCase()},
          line: '\n'.allMatches(sql.substring(0, m.start)).length + 1,
        ),
    ];

void main() {
  final dir = Directory('supabase/migrations');
  final all = (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList())
    ..sort((a, b) => a.path.compareTo(b.path));
  int numberOf(File f) => int.parse(RegExp(r'(\d{4})_').firstMatch(f.uri.pathSegments.last)!.group(1)!);
  // كل ملف من 0035 وطالع — الأعمدة المطلوبة من **كل** اللي قبله
  final guarded = all.where((f) => numberOf(f) >= 35).toList();

  test('الاستخراج شغّال فعلاً — الأعمدة اللي وقّعت 0035 موجودة فيه', () {
    final required = requiredColumns(all.where((f) => numberOf(f) < 35).toList());
    expect(required['public.dose_schedules'], containsAll(['repeat', 'start_date']));
    expect(required['public.dose_events'], containsAll(['routine_day', 'scheduled_at', 'state']));
    expect(required['public.patients'], containsAll(['owner_id', 'name']));
  });

  test('فيه ملفات محروسة، و0035 منهم', () {
    expect(guarded.map((f) => numberOf(f)), contains(35));
  });

  for (final file in guarded) {
    final n = numberOf(file);
    test('$n: كل insert في الفحص الذاتي بيكتب كل عمود not null من غير default (من الترحيلات اللي قبله)', () {
      // الملف نفسه داخل: جدول بيعمله وبيكتب فيه في فحصه لازم يتحرس برضه
      final required = requiredColumns(all.where((f) => numberOf(f) <= n).toList());
      final inserts = insertsIn(file.readAsStringSync());
      expect(inserts, isNotEmpty, reason: '${file.path}: مفيش ولا insert — فحص ذاتي من غير كتابة مش فحص');
      final missing = <String>[];
      for (final ins in inserts) {
        final need = required[ins.table];
        if (need == null) continue; // مش من ترحيلاتنا (auth.users)
        final gap = need.difference(ins.columns);
        if (gap.isNotEmpty) missing.add('${ins.table} (سطر ${ins.line}): ${gap.join('، ')}');
      }
      expect(missing, isEmpty, reason: '${file.path}: أعمدة not null ناقصة — 23502 على المشروع الحقيقي:\n${missing.join('\n')}');
    });
  }
}
