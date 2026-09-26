// الإضافة ما بتشتغلش في `flutter test` — فالإعدادات اللي عليها الإصلاح
// بتتقفل من المصدر.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/data/voice/speech_to_text_listener.dart').readAsStringSync();

  test('آيفون من غير شرط «على الجهاز»، وأندرويد على الجهاز الأول', () {
    expect(src, contains('static bool get _preferOnDevice => !Platform.isIOS;'));
    expect(src, contains('onDevice: _preferOnDevice && !_onDeviceRefused'));
  });

  test('الإضافة ما تلغيش السماع الشغّال على عطل قديم', () {
    expect(src, contains('cancelOnError: false'));
    expect(src, isNot(contains('cancelOnError: true')));
  });

  test('أول كلمة ليها ٦ ثواني، وبعد الكلام ٣، والسماع كله ١٠', () {
    expect(src, contains('pauseFor: firstWordWithin'));
    expect(src, contains('_stt.changePauseFor(_silence)'));
    expect(src, contains('listenFor: maxLength'));
  });

  test('الاستثناء بيتكتب بحقوله، مش «Instance of …»', () {
    expect(src, contains('message=\${e.message} details=\${e.details} stack=\${e.stackTrace}'));
    expect(src, contains('session.startFailure(why)'));
  });
}
