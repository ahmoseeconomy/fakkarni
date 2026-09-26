import 'dart:async';

import 'package:fakkarni/data/voice/speech_listener.dart';

/// متعرّف كلام مزيّف: بيرجّع الإجابات بالترتيب، وبيسجّل كل سماع.
class FakeListener implements SpeechListener {
  FakeListener({this.permission = true, this.prepareOk = true, List<String?> answers = const []}) : answers = [...answers];

  bool permission;
  bool prepareOk;
  final List<String?> answers;
  int listens = 0;
  int stops = 0;
  int prepares = 0;
  bool prepared = false;

  /// السماع «بيفضل مفتوح» لحد ما `stop()` تتنده — زي مايك حقيقي مستني.
  bool hold = false;
  Completer<String?>? _open;

  @override
  bool? lastOnDevice = true;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> prepare() async {
    prepares++;
    if (prepareOk) {
      permission = true;
      prepared = true;
    }
    return prepareOk;
  }

  @override
  Future<String?> listen({Duration silence = const Duration(seconds: 6), Duration maxLength = const Duration(seconds: 12)}) async {
    if (!prepared) throw StateError('listen قبل prepare');
    listens++;
    if (hold) {
      final c = _open = Completer<String?>();
      return c.future;
    }
    return answers.isEmpty ? null : answers.removeAt(0);
  }

  /// المايك مفتوح دلوقتي (سماع مستني).
  bool get listening => _open != null;

  /// بيستنّى لحد ما سماع يتفتح — الدورة فيها كلام قبل كل سماع.
  Future<void> untilListening() async {
    for (var i = 0; i < 200 && !listening; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    if (!listening) throw StateError('مفيش سماع اتفتح');
  }

  /// بيقفل السماع المفتوح بإجابة (أو null = سكوت).
  void hear(String? text) {
    final c = _open;
    _open = null;
    if (c != null && !c.isCompleted) c.complete(text);
  }

  @override
  Future<void> stop() async {
    stops++;
    hear(null);
  }
}
