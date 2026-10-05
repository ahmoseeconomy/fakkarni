/// صوت فورم «ضيف دوا» (مراجعة المالك، ٥ أكتوبر ٢٠٢٦) — طريقين:
///
/// («قولها بصوتك» الكبير اتشال ٥ أكتوبر مساءً — الدوا كله بالصوت مكانه
/// «كلّمني» على «يومك».)
///
/// **«قولها» الصغير** جنب الاسم وبكرتَي «لإيه؟» و«نوعه؟» — بيملا
/// الحقل ده وبس، والبكرة بتتحرّك قدّامه فالمراجعة بالعين.
///
/// القواعد: دوسة = سماع واحد (`MicListener` نفسه بيضمنها)، الأسئلة
/// والحالات **مكتوبة** (مفيش TTS)، عمرنا ما نسمع في الخلفية، وفشل السماع
/// عمره ما يتقال «مافهمتش». **على موبايل الممرض مفيش صوت خالص**
/// (`voiceInput: false` من شاشاته — `voice_placement_test` بيقفل عليها).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/diagnostics.dart';
import '../../core/theme/tokens.dart';
import '../../data/voice/speech_listener.dart';
import '../../data/voice/voice_service.dart';

/// جلسة صوت الفورم — سماع واحد في المرة، وحالتها كلام مكتوب.
class MedVoiceSession extends ChangeNotifier {
  MedVoiceSession(this.voice);

  final VoiceService voice;

  /// الصوت موجود على الموبايل ده أصلاً؟ (المحرّك السحابي كعب = مفيش مايك.)
  bool get available => voice.listener != null && !_hidden;

  /// بنسمع لمين دلوقتي — اسم الحقل، والزرار بيكتبه.
  String? listeningFor;

  /// سطر مكتوب تحت الزرار — «ما سمعتش حاجة …» وأخواتها.
  String? note;

  bool _hidden = false;
  bool get busy => listeningFor != null;

  /// سماع واحد: بيسلّم الجلسة، بيسمع، وبيرجّع الكلام أو null — والسبب
  /// بيتكتب في [note].
  Future<String?> hear(String forWhat) async {
    final listener = voice.listener;
    if (listener == null || _hidden || busy) return null;
    listeningFor = forWhat;
    note = null;
    notifyListeners();
    try {
      await voice.yieldToMic();
      if (await listener.prepare() case final failed?) {
        _fail(failed);
        return null;
      }
      final result = await listener.listen();
      switch (result) {
        case ListenHeard(:final text) when text.trim().isNotEmpty:
          return text.trim();
        case ListenHeard() || ListenSilence():
          // مفيش كلام مش عطل — راحة وسطر، والزرار فاضل (قاعدة MicOrb)
          note = 'ما سمعتش حاجة — دوس تاني واتكلم.';
          return null;
        case final ListenFailed failed:
          _fail(failed);
          return null;
      }
    } finally {
      listeningFor = null;
      notifyListeners();
    }
  }

  void _fail(ListenFailed failed) {
    diag('MedVoice: السماع وقع — $failed');
    if (failed.permission) {
      // الإذن اترفض — مفيش طلب تاني ورا بعض: الصوت بيختفي من الشاشة دي
      _hidden = true;
      note = 'الإذن بتاع المايك مقفول — كمّل بإيدك.';
    } else if (!failed.started) {
      _hidden = true;
      note = 'معلش، الصوت مش متاح دلوقتي — كمّل بإيدك.';
    } else {
      note = 'معلش، اتقطع — جرّب تاني.';
    }
  }

  /// التطبيق راح للخلفية — عمرنا ما نسمع فيها.
  Future<void> cancel() async {
    if (!busy) return;
    await voice.listener?.stop();
  }
}

/// (ب) «قولها» جنب حقل واحد — بيملاه هو وبس.
class FieldMicButton extends StatelessWidget {
  const FieldMicButton({
    required this.session,
    required this.forWhat,
    required this.onHeard,
    super.key,
  });

  final MedVoiceSession session;

  /// اسم الحقل — للسماع وللقارئ («قولها — اسم الدوا»).
  final String forWhat;
  final ValueChanged<String> onHeard;

  Future<void> _tap(BuildContext context) async {
    final text = await session.hear(forWhat);
    if (text != null) onHeard(text);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      if (!session.available) return const SizedBox.shrink();
      final listeningHere = session.listeningFor == forWhat;
      return Semantics(
        label: 'قولها — $forWhat',
        button: true,
        excludeSemantics: true,
        // الزرار جوّه Row من غير Expanded — من غير IntrinsicWidth عرضه
        // بيوصله لانهاية وبيقع وقت التخطيط (نفس درس زرار «تأكيد» القديم)
        child: IntrinsicWidth(
          child: SizedBox(
            height: F.minTapTarget,
            child: OutlinedButton.icon(
              key: ValueKey('field-mic-$forWhat'),
              onPressed: session.busy ? null : () => _tap(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: F.green,
                side: BorderSide(color: F.green, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: F.s10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(F.radiusCard),
                ),
                textStyle: const TextStyle(
                  fontSize: F.minTextSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: Icon(
                listeningHere ? Icons.graphic_eq : Icons.mic,
                size: 22,
              ),
              label: Text(listeningHere ? 'سامعك…' : 'قولها'),
            ),
          ),
        ),
      );
    },
  );
}

