import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/health/lab_range.dart';
import 'package:fakkarni/features/health/lab_flag.dart';

/// الأحمر للطوارئ بس (CLAUDE.md، PHASE_D3): الشاشتين في `features/emergency/`.
/// الاختبار بيقرا الكود نفسه — لون أحمر في أي شاشة تانية غلط، حتى لو مفيش
/// اختبار واجهة بيعدّي عليها.
///
/// **استثناء واحد، بقرار صاحب المنتج**: قيمة تحليل برّه النطاق المطبوع على
/// ورقة المعمل بتاخد أحمر **نص وإطار**. والاستثناء متحدّد من ناحيتين:
/// ملف واحد بس ([_labFlagFile])، و**من غير حشو** — الحبّاية الحمرا
/// المليانة فاضلة للطوارئ لوحدها، وده اللي بيخلي معناها محفوظ. الشرط
/// التاني ده مش بيتقاس بقراية كود؛ بيتقاس بضغط الودجت نفسه تحت.
const _labFlagFile = 'lib/features/health/lab_flag.dart';

void main() {
  test('F.red / F.redDeep / F.redPanel / F.onRed وقيمهم ما بيظهروش برّه شاشات الطوارئ', () {
    final forbidden = RegExp(
      r'F\.(red|redDeep|redPanel|onRed|onRedMuted|outOfRangeInk)\b'
      r'|0xFFC0202F|0xFFA81E26|0xFF8C1820|0xFFE8747B|Colors\.red',
      caseSensitive: false,
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/features/emergency/')) continue;
      if (path == 'lib/core/theme/tokens.dart') continue; // التعريف نفسه
      if (path == _labFlagFile) continue; // الاستثناء الوحيد — وبشروطه تحت
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') || line.startsWith('///')) continue;
        if (forbidden.hasMatch(line)) offenders.add('$path:${i + 1}: $line');
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('علامة «برّه النطاق»: أحمر نص وإطار — ومن غير أي حشو', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: LabFlagBadge(AboveRange()))),
    ));

    final box = tester.widget<Container>(find.byType(Container));
    final decoration = box.decoration! as BoxDecoration;

    // الإطار أحمر…
    expect((decoration.border! as Border).top.color, F.outOfRangeInk);
    // …والجوّه فاضي. الحشو هو اللي بيخلي الحاجة «حبّاية طوارئ».
    expect(decoration.color, isNull,
        reason: 'علامة التحليل اتملت بالأحمر — دي بقت حبّاية الطوارئ');
    expect(tester.widget<Text>(find.text('فوق المعدل')).style!.color, F.outOfRangeInk);
  });

  testWidgets('«تحت المعدل» نفس الشكل، و«قريب من الحد» ذهبي بنص حبر', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: LabFlagBadge(BelowRange()))),
    ));
    var decoration = tester.widget<Container>(find.byType(Container)).decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, F.outOfRangeInk);
    expect(decoration.color, isNull);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: LabFlagBadge(NearBoundary()))),
    ));
    decoration = tester.widget<Container>(find.byType(Container)).decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, F.gold);
    expect(decoration.color, isNull);
    // الذهبي كنص ٢:١ على الأبيض (الدين ٥) — الكلمة حبر، والذهبي إطار.
    expect(tester.widget<Text>(find.text('قريب من الحد')).style!.color, F.ink);
  });

  testWidgets('جوّه النطاق: ولا لون ولا كلمة', (tester) async {
    for (final flag in [const InsideRange(), const NoPrintedRange(), const RangeNotNumeric()]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: LabFlagBadge(flag)))));
      expect(find.byType(Container), findsNothing);
      expect(LabFlagBadge.tint(flag), isNull);
    }
  });
}
