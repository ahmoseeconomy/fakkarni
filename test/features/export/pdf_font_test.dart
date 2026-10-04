// خط الـPDF: نسخة Cairo بالأشكال المنفردة (tool/make_pdf_cairo.py).
//
// مكتبة pdf بتشكّل العربي لوحدها وبتطلب أشكال العرض (U+FE70–FEFF). Cairo
// الأصلي مفيهوش الشكل المنفرد لأغلب الحروف، فـ«دي» و«ده» و«و» لوحدها كانوا
// بيترسموا غلط في الملف (اتشاف على ملف حقيقي، ٤ أكتوبر ٢٠٢٦). الاختبار ده
// بيقرا جدول cmap من الملف نفسه ويوقع لو شكل منفرد لحرف عربي ناقص.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// أكواد اليونيكود اللي ليها رسمة — من جداول cmap بصيغة ٤ (BMP).
Set<int> _cmapCodepoints(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  final numTables = d.getUint16(4);
  int? cmapOffset;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(rec, rec + 4)) == 'cmap') cmapOffset = d.getUint32(rec + 8);
  }
  final base = cmapOffset!;
  final out = <int>{};
  final n = d.getUint16(base + 2);
  for (var i = 0; i < n; i++) {
    final sub = base + d.getUint32(base + 4 + i * 8 + 4);
    if (d.getUint16(sub) != 4) continue;
    final segX2 = d.getUint16(sub + 6);
    final ends = sub + 14;
    final starts = ends + segX2 + 2;
    final deltas = starts + segX2;
    final ranges = deltas + segX2;
    for (var s = 0; s < segX2 ~/ 2; s++) {
      final end = d.getUint16(ends + s * 2);
      final start = d.getUint16(starts + s * 2);
      final delta = d.getInt16(deltas + s * 2);
      final rangeOffset = d.getUint16(ranges + s * 2);
      for (var c = start; c <= end && c != 0xFFFF; c++) {
        final glyph = rangeOffset == 0
            ? (c + delta) & 0xFFFF
            : d.getUint16(ranges + s * 2 + rangeOffset + (c - start) * 2);
        if (glyph != 0) out.add(c);
      }
    }
  }
  return out;
}

/// الأشكال المنفردة للحروف الأساسية (U+FE80–FEF4، الأرقام الفردية تقريباً) —
/// اللي مكتبة pdf بتطلبها لحرف واقف لوحده.
const _isolated = <int>[
  0xFE80, 0xFE81, 0xFE83, 0xFE85, 0xFE87, 0xFE89, 0xFE8D, 0xFE8F, 0xFE93, 0xFE95,
  0xFE99, 0xFE9D, 0xFEA1, 0xFEA5, 0xFEA9, 0xFEAB, 0xFEAD, 0xFEAF, 0xFEB1, 0xFEB5,
  0xFEB9, 0xFEBD, 0xFEC1, 0xFEC5, 0xFEC9, 0xFECD, 0xFED1, 0xFED5, 0xFED9, 0xFEDD,
  0xFEE1, 0xFEE5, 0xFEE9, 0xFEED, 0xFEEF, 0xFEF1,
];

void main() {
  for (final w in ['Regular', 'Bold']) {
    test('CairoPdf-$w فيه الشكل المنفرد لكل حرف — «دي» و«ده» و«و» ما يتكسروش', () {
      final cps = _cmapCodepoints(File('assets/fonts/pdf/CairoPdf-$w.ttf').readAsBytesSync());
      final missing = [for (final c in _isolated) if (!cps.contains(c)) c.toRadixString(16)];
      expect(missing, isEmpty);
    });
  }

  test('الأصل فعلاً ناقصه — يعني النسخة المعدّلة لازمة (لو Cairo اتحدّث وبقى فيه، الملف ده يتشال)', () {
    final cps = _cmapCodepoints(File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync());
    expect(cps.contains(0xFEF1), isFalse, reason: 'ي منفردة');
    expect(cps.contains(0xFEED), isFalse, reason: 'و منفردة');
  });

  test('الـPDF بيحمّل النسخة المعدّلة، والنسخة متحزّمة', () {
    final code = File('lib/features/export/export_pdf.dart').readAsStringSync();
    expect(code, contains('assets/fonts/pdf/CairoPdf-Regular.ttf'));
    expect(code, contains('assets/fonts/pdf/CairoPdf-Bold.ttf'));
    expect(code, isNot(contains("'assets/fonts/Cairo-")));
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/fonts/pdf/'));
  });
}
