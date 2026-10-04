// APNs على iOS (الدين ٣ — اتدفع ٤ أكتوبر ٢٠٢٦): الإعداد كله مرايا بين
// أربع ملفات، وأي واحد يتحرّك لوحده بيوقّع هنا بدل ما يبان على الجهاز
// كـ«مفيش توكن» من غير سبب.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _plistValue(String plist, String key) {
  final m = RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(plist);
  expect(m, isNotNull, reason: '$key مش في GoogleService-Info.plist');
  return m!.group(1)!;
}

String _dartValue(String src, String field) {
  final m = RegExp("$field: '([^']*)'").firstMatch(src);
  expect(m, isNotNull, reason: '$field مش في firebase_ios_options.dart');
  return m!.group(1)!;
}

void main() {
  final plist = File('ios/Runner/GoogleService-Info.plist').readAsStringSync();
  final options = File('lib/data/push/firebase_ios_options.dart').readAsStringSync();

  test('الـplist متكوميت زي أندرويد، وللتطبيق والمشروع الصح', () {
    expect(_plistValue(plist, 'BUNDLE_ID'), 'com.fakrny.app');
    expect(_plistValue(plist, 'PROJECT_ID'), 'fakkarni-5704c');
    // أندرويد المتكوميت من نفس المشروع — sender واحد
    final android = File('android/app/google-services.json').readAsStringSync();
    expect(android, contains('"project_id": "fakkarni-5704c"'));
  });

  test('قيم دارت = الـplist حرف بحرف — التهيئة على iOS بتقرا من دارت', () {
    const map = {
      'apiKey': 'API_KEY',
      'appId': 'GOOGLE_APP_ID',
      'messagingSenderId': 'GCM_SENDER_ID',
      'projectId': 'PROJECT_ID',
      'storageBucket': 'STORAGE_BUCKET',
      'iosBundleId': 'BUNDLE_ID',
    };
    for (final e in map.entries) {
      expect(_dartValue(options, e.key), _plistValue(plist, e.value), reason: e.key);
    }
  });

  test('البوابة اتفتحت: iOS بياخد القيم الصريحة، والمنصة مش ثابتة أندرويد', () {
    final src = File('lib/data/push/firebase_token_source.dart').readAsStringSync();
    expect(src, isNot(contains('أندرويد بس دلوقتي')));
    expect(src, contains('options: ios ? firebaseIosOptions : null'));
    expect(src, contains('TargetPlatform.iOS ? PushPlatform.ios : PushPlatform.android'));
    // iOS بيستنى توكن APNs قبل getToken — من غيره «has not been set»
    expect(src, contains('getAPNSToken'));
  });

  test('aps-environment في الـentitlements (development — Xcode بيقلبها للمتجر)، وTime Sensitive فاضل', () {
    final ent = File('ios/Runner/Runner.entitlements').readAsStringSync().replaceAll(RegExp(r'\s'), '');
    expect(ent, contains('<key>aps-environment</key><string>development</string>'));
    expect(ent, contains('time-sensitive</key><true/>'));
  });

  test('remote-notification في UIBackgroundModes — إشارة «اتأكّدت» الصامتة', () {
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    expect(info, contains('<string>remote-notification</string>'));
    expect(info, contains('<string>fetch</string>'), reason: 'الفحص اليومي زي ما هو');
  });
}
