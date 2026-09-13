// منطق التوكن كله، من غير ما نلمس Firebase ولا Supabase ولا مرة.
//
// ده مش تسهيل على الاختبار — ده الفرق بين «الكود مظبوط» و«جربناه على
// موبايل». الجزء اللي بيقرر إمتى نسجّل وإمتى نمسح دارت خالص، فبيتقاس
// هنا في أجزاء من الثانية.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/push/push_token_service.dart';
import 'package:fakkarni/data/push/push_tokens.dart';

class FakeSource implements DeviceTokenSource {
  FakeSource({this.current = 'token-1', this.granted = true});

  String? current;
  bool granted;
  int permissionAsks = 0;
  int tokenReads = 0;
  final _refreshes = StreamController<String>.broadcast();

  @override
  PushPlatform get platform => PushPlatform.android;

  @override
  Future<bool> ensurePermission() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<String?> token() async {
    tokenReads++;
    return current;
  }

  @override
  Stream<String> get refreshes => _refreshes.stream;

  void rotate(String token) {
    current = token;
    _refreshes.add(token);
  }

  Future<void> close() => _refreshes.close();
}

class FakeRemote implements PushTokenRemote {
  final List<String> claimed = [];
  final List<String> removed = [];
  bool throwOnClaim = false;

  @override
  Future<void> claim(String token, PushPlatform platform) async {
    if (throwOnClaim) throw StateError('الشبكة');
    claimed.add(token);
  }

  @override
  Future<void> remove(String token) async => removed.add(token);
}

void main() {
  late FakeSource source;
  late FakeRemote remote;
  late StreamController<bool> auth;
  late bool signedIn;
  late PushTokenService service;

  setUp(() {
    source = FakeSource();
    remote = FakeRemote();
    auth = StreamController<bool>.broadcast();
    signedIn = false;
    service = PushTokenService(
      source: source,
      remote: remote,
      signedIn: auth.stream,
      isSignedIn: () => signedIn,
    );
    service.start();
  });

  tearDown(() async {
    await service.dispose();
    await auth.close();
    await source.close();
  });

  Future<void> signIn() async {
    signedIn = true;
    auth.add(true);
    await pumpEventQueue();
  }

  test('الدخول بيسجّل التوكن', () async {
    await signIn();
    expect(remote.claimed, ['token-1']);
  });

  test('من غير دخول مفيش أي نداء — التطبيق شغّال بلا حساب', () async {
    await service.registerNow();
    expect(remote.claimed, isEmpty);
    expect(source.tokenReads, 0, reason: 'ولا حتى بنسأل الجهاز');
  });

  test('تدوير التوكن بيعيد التسجيل لوحده', () async {
    await signIn();
    source.rotate('token-2');
    await pumpEventQueue();
    expect(remote.claimed, ['token-1', 'token-2']);
  });

  test('تدوير وإحنا بره الحساب ما بيكلّمش السحابة', () async {
    source.rotate('token-2');
    await pumpEventQueue();
    expect(remote.claimed, isEmpty);
  });

  test('نفس التوكن مرتين = نداء واحد', () async {
    await signIn();
    await service.registerNow();
    expect(remote.claimed, ['token-1']);
  });

  test('رفض الإذن ما بيمنعش التسجيل — الابن ممكن يفتحها بعدين', () async {
    source.granted = false;
    await signIn();
    expect(remote.claimed, ['token-1']);
    expect(source.permissionAsks, 1);
  });

  test('مفيش توكن من الجهاز = مفيش نداء، ومفيش رمي', () async {
    source.current = null;
    await signIn();
    expect(remote.claimed, isEmpty);
  });

  test('فشل الحجز صامت، والمحاولة الجاية بتعيد الكرّة', () async {
    remote.throwOnClaim = true;
    await signIn();
    expect(remote.claimed, isEmpty);

    remote.throwOnClaim = false;
    await service.registerNow();
    expect(remote.claimed, ['token-1'],
        reason: 'الفشل ما اتسجّلش كأنه نجاح');
  });

  test('clear بيشيل الصف — وده لازم يحصل قبل الخروج', () async {
    await signIn();
    await service.clear();
    expect(remote.removed, ['token-1']);
  });

  test('دخول جديد بعد خروج بيحجز تاني حتى لو نفس التوكن', () async {
    // ده بالظبط سيناريو الخروج المحلي: مستخدم مجهول جديد، نفس النسخة،
    // نفس توكن FCM — والصف لازم يتنقل لصاحبه الجديد.
    await signIn();
    await service.clear();

    signedIn = false;
    auth.add(false);
    await pumpEventQueue();

    await signIn();
    expect(remote.claimed, ['token-1', 'token-1']);
  });

  test('الخروج لوحده ما بيمسحش من السحابة — مفيش صلاحية بعده', () async {
    await signIn();
    signedIn = false;
    auth.add(false);
    await pumpEventQueue();
    expect(remote.removed, isEmpty);
  });
}
