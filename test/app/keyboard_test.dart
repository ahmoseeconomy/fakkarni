import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/widgets/keyboard_dismiss.dart';

/// **الكيبورد بيتقفل من الجذر — والاختبار ده هو اللي بيمنع رجوع العطل.**
///
/// على آيفون حقيقي: «بيانات الطوارئ» حفظت وعملت `pop` وهي سايبة التركيز،
/// فالكيبورد فضل مفتوح على «يومك» من غير حقل يقفله بيه — والدوك المرفوع
/// حط «ضيف» فوق «تأكيد الجرعة» بالظبط.
void main() {
  group('الحارس: مفيش حقل من غير باب خروج', () {
    /// كل (بداية، نهاية) لاستدعاء `TextField(` / `TextFormField(` بموازنة
    /// الأقواس — عدّ الكلمات لوحده كان هيعدّي على حقل ناقص في وسط ملف.
    List<(int, int)> fieldSpans(String src) {
      final out = <(int, int)>[];
      for (final m in RegExp(r'\bText(?:Form)?Field\(').allMatches(src)) {
        var i = m.end - 1;
        var depth = 0;
        while (i < src.length) {
          final c = src[i];
          if (c == '(') {
            depth++;
          } else if (c == ')') {
            depth--;
            if (depth == 0) break;
          } else if (c == "'" || c == '"') {
            final q = c;
            i++;
            while (i < src.length && src[i] != q) {
              if (src[i] == r'\') i++;
              i++;
            }
          }
          i++;
        }
        out.add((m.start, i + 1));
      }
      return out;
    }

    test('كل TextField في lib/ له textInputAction', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final src = entity.readAsStringSync();
        for (final (a, b) in fieldSpans(src)) {
          if (src.substring(a, b).contains('textInputAction:')) continue;
          final line = '\n'.allMatches(src.substring(0, a)).length + 1;
          offenders.add('$path:$line');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'حقل من غير `textInputAction` معناه كيبورد من غير زرار يقفله:\n'
            '${offenders.join('\n')}',
      );
    });

    test('الحارس نفسه بيشوف الحقول — مش بيعدّي فاضي', () {
      var found = 0;
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        found += fieldSpans(entity.readAsStringSync()).length;
      }
      expect(found, greaterThan(15), reason: 'الماسح ما لقاش الحقول أصلاً');
    });
  });

  group('الجذر بيسلّم التركيز', () {
    testWidgets('كل push وكل pop بيقفلوا الكيبورد', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        navigatorObservers: [FakkarniNavigatorObserver()],
        home: Scaffold(
          body: TextField(
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'الأول'),
          ),
        ),
      ));
      await tester.pump();
      // **`testTextInput.isVisible` هو الكيبورد نفسه**، مش التركيز.
      // `primaryFocus` بعد `unfocus` بيبقى الـscope اللي فوق، وهو عنده
      // تركيز أساسي فعلاً — فالسؤال «هل فيه تركيز» بيجاوب «أيوه» وهو
      // مش الإجابة. السؤال الصح: الكيبورد طالع ولا لأ.
      expect(tester.testTextInput.isVisible, isTrue);

      // شاشة بتفتح شاشة وهي كاتبة — الكيبورد ما بيعدّيش معاها
      unawaited(key.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('التانية')),
      )));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse, reason: 'الكيبورد عدّى مع الـpush');

      // والرجوع برضه — ده الطريق اللي «بيانات الطوارئ» بتعدّي منه
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse, reason: 'الكيبورد رجع مع الـpop');
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
        reason: 'التركيز رجع لحقل مشالت شاشته',
      );
    });

    testWidgets('دوسة برّه الحقل بتقفل الكيبورد', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: KeyboardDismiss(
          child: Scaffold(
            body: Column(
              children: [
                TextField(
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'اكتب'),
                ),
                const SizedBox(height: 200, width: 400, child: Text('فراغ')),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tapAt(tester.getCenter(find.text('فراغ')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('ودوسة على زرار شغّال بتوصله — الحارس ما بياكلش الدوسات', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: KeyboardDismiss(
          child: Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () => tapped++, child: const Text('دوس')),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('دوس'));
      await tester.pump();
      expect(tapped, 1);
    });
  });

  test('الجذر موصّل — الاتنين في main.dart', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('FakkarniNavigatorObserver()'));
    expect(main, contains('KeyboardDismiss('));
  });
}

void unawaited(Future<void> f) {}
