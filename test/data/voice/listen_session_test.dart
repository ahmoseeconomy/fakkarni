// مين صاحب الحدث ده، ونعمل إيه — من غير الإضافة. التسلسل الأول هو اللي طلع
// في لوج الجهاز (آيفون، profile، صفحة الجنس، ٢٦ سبتمبر ٢٠٢٦).
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/voice/listen_session.dart';
import 'package:fakkarni/data/voice/speech_listener.dart';

void main() {
  const thrown = 'ListenFailedException message=null details=null stack=null';

  test('لوج الجهاز: listen() رمت ← إعادة بعد ٣٠٠ ملّي، وerror_listen_failed اللي بعدها نفس الوقعة', () {
    final s = ListenSession(onDevice: false);
    final first = s.startFailure(thrown);
    expect(first, isA<ListenRetry>());
    expect((first! as ListenRetry).onDevice, isFalse);
    expect(ListenSession.retryAfter, const Duration(milliseconds: 300));
    expect(s.error('error_listen_failed'), isNull, reason: 'التانية من نفس الوقعة — مش عطل جديد');
    expect(s.status('notListening'), isNull);

    // الإعادة نجحت: سامع، وسكت → سكوت (مش عطل)
    s.restart(onDevice: false);
    expect(s.status('listening'), isNull);
    final end = s.status('done');
    expect((end! as ListenFinish).result, isA<ListenSilence>());
  });

  test('وقعت تاني بعد الإعادة → «المايك ما اشتغلش» (started: false)', () {
    final s = ListenSession(onDevice: false);
    expect(s.startFailure(thrown), isA<ListenRetry>());
    s.restart(onDevice: false);
    final second = s.error('error_listen_failed');
    final r = (second! as ListenFinish).result as ListenFailed;
    expect(r.started, isFalse);
    expect(r.permission, isFalse);
  });

  test('رفض «على الجهاز» (أندرويد) ← إعادة عبر السيرفر مرة', () {
    final s = ListenSession(onDevice: true);
    final d = s.startFailure('ListenFailedException message=on device recognition is not supported on this device');
    expect((d! as ListenRetry).onDevice, isFalse);
    expect(s.serverRetried, isTrue);
  });

  test('بقايا مهمة قديمة قبل «listening» بتتساب — حالات وأعطال', () {
    final s = ListenSession(onDevice: false);
    expect(s.status('done'), isNull);
    expect(s.status('notListening'), isNull);
    expect(s.error('error_unknown (1101)'), isNull);
    expect(s.error('error_request_cancelled'), isNull);
    expect(s.error('error_no_match'), isNull);
  });

  test('بعد «listening»: مفيش كلام = سكوت؛ فيه كلام = اتقال', () {
    final s = ListenSession(onDevice: false)..status('listening');
    expect((s.error('error_no_match')! as ListenFinish).result, isA<ListenSilence>());
    final t = ListenSession(onDevice: false)
      ..status('listening')
      ..heard('راجل');
    final r = (t.status('done')! as ListenFinish).result;
    expect((r as ListenHeard).text, 'راجل');
  });

  test('عطل بعد ما بدأ = تعثّرة (started: true) — مش «المايك ما اشتغلش»', () {
    final s = ListenSession(onDevice: false)..status('listening');
    final r = (s.error('error_audio')! as ListenFinish).result as ListenFailed;
    expect(r.started, isTrue);
  });

  test('الإذن = الإذن في أي وقت', () {
    final s = ListenSession(onDevice: false);
    final r = (s.error('error_speech_recognizer_request_not_authorized')! as ListenFinish).result as ListenFailed;
    expect(r.permission, isTrue);
  });

  test('التوقيتات: ١٠ ثواني كلها، ٦ لأول كلمة، ٣ سكوت بعد الكلام', () {
    expect(ListenTimings.maxLength, const Duration(seconds: 10));
    expect(ListenTimings.firstWordWithin, const Duration(seconds: 6));
    expect(ListenTimings.silence, const Duration(seconds: 3));
  });
}
