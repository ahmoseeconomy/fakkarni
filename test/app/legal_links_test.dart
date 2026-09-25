// سياسة الخصوصية والشروط: رابطين من ملف إعداد واحد، ظاهرين قبل أي حساب،
// والمسودّات موجودة ومتعلّمة «مسودّة».
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/legal/legal_links.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/legal_links_row.dart';
import 'package:fakkarni/features/entry/entry_screen.dart';

import '../features/scan/scan_test_support.dart';

void main() {
  test('الرابطين في ملف إعداد واحد — ومحدش تاني بيكتبهم', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('core/legal/legal_links.dart')) continue;
      final src = f.readAsStringSync();
      for (final name in ['PRIVACY_URL', 'TERMS_URL']) {
        expect(src.contains(name), isFalse, reason: '${f.path} فيه $name — المكان الوحيد legal_links.dart');
      }
    }
    // علامة المكان ما بتتفتحش كرابط
    expect(legalUrlReady('[PRIVACY_URL]'), isFalse);
    expect(legalUrlReady('https://example.com/privacy'), isTrue);
  });

  screenTest('أول شاشة — قبل أي حساب — فيها الرابطين، والدوسة بتفتح الرابط الصح', (tester) async {
    final opened = <String>[];
    final original = LegalLinksRow.open;
    LegalLinksRow.open = (url) async => opened.add(url);
    addTearDown(() => LegalLinksRow.open = original);

    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: EntryScreen(onSelf: () {}, onHaveCode: () {}, onNurse: () {}),
    ));
    await settle(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('legal-privacy')));
    await tester.tap(find.byKey(const ValueKey('legal-privacy')));
    await tester.tap(find.byKey(const ValueKey('legal-terms')));
    expect(opened, [privacyUrl, termsUrl]);
    for (final key in ['legal-privacy', 'legal-terms']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height, greaterThanOrEqualTo(F.minTapTarget));
    }
    expectNoRedAndMinSize(tester);
  });

  test('الإعدادات عند المريض وعند الابن فيها الرابطين', () {
    for (final path in [
      'lib/features/settings/settings_screen.dart',
      'lib/features/care/caregiver_settings_screen.dart',
      'lib/features/entry/entry_screen.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('LegalLinksRow('), reason: path);
    }
  });

  test('المسودّات الأربعة موجودة، متعلّمة «مسودّة»، وفيها أماكن الشركة', () {
    for (final name in ['privacy_ar', 'privacy_en', 'terms_ar', 'terms_en']) {
      final doc = File('docs/legal/$name.md').readAsStringSync();
      expect(doc.contains('DRAFT') || doc.contains('مسودّة'), isTrue, reason: name);
      expect(doc, contains('[COMPANY_NAME]'), reason: name);
      expect(doc, contains('[COMPANY_EMAIL]'), reason: name);
    }
    expect(File('docs/legal/store_forms.md').existsSync(), isTrue);
  });
}
