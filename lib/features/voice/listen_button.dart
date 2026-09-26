import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import 'listen_flow.dart';

/// «🎤 اتكلم» — جنب «ساعدني»، **بس فين الإجابة مقفولة**: أيوه/لأ، ساعة،
/// رقم، راجل/ست، الاسم، ورد التذكير. الدوسة بتفتح ورقة صغيرة فيها اللي
/// بيحصل بالكلام الكبير: «اتكلم، أنا سامعك» ← «فهمت: …» + «أيوه»/«لأ» ←
/// اتطبّق. المايك مفتوح وهو داوس بس، وبيقفل لوحده بعد سكوت قصير.
///
/// **بيظهر لما فيه مايك في النسخة، والصوت شغّال، والإذن مش مرفوض.** رفض
/// الإذن بيخفيه في الجلسة دي — كل حاجة شغّالة بالإيد زي ما هي. من غير
/// `AppScope` أو من غير خدمة صوت = مفيش زرار (زي «ساعدني»).
///
/// أول مرة يظهر (`listenIntroDone`): «دلوقتي تقدر تكلّمني…» بعد اللي
/// بيتقال — مش فوقه.
class ListenButton<T> extends StatefulWidget {
  const ListenButton({
    required this.tag,
    required this.parse,
    required this.describe,
    required this.onApply,
    this.force = false,
    this.elder = false,
    this.onDark = false,
    this.hint,
    super.key,
  });

  /// كلمة جنب الزرار بتقول إيه اللي يتقال («قول «أخدته» أو دوس») — بتظهر
  /// وتختفي مع الزرار نفسه، وأكبر في نمط كبار السن.
  final String? hint;

  /// بيدخل في مفتاح الزرار: `listen-<tag>`.
  final String tag;
  final T? Function(String heard) parse;
  final String Function(T value) describe;

  /// **نفس الدالة اللي الزرار العادي بيندهها.**
  final Future<void> Function(T value) onApply;

  /// المقدمة — الصوت لسه ما اتشغّلش.
  final bool force;
  final bool elder;
  final bool onDark;

  @override
  State<ListenButton<T>> createState() => _ListenButtonState<T>();
}

class _ListenButtonState<T> extends State<ListenButton<T>> with WidgetsBindingObserver {
  ListenFlow<T>? _flow;
  bool _introQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final voice = AppScope.maybeOf(context)?.voice;
    if (voice == null || _flow != null) return;
    _flow = ListenFlow<T>(
      voice: voice,
      parse: widget.parse,
      describe: widget.describe,
      onApply: widget.onApply,
      force: widget.force,
      autoApply: false,
    );
    voice.addListener(_maybeIntro);
    _maybeIntro();
  }

  /// «دلوقتي تقدر تكلّمني» — مرة واحدة في عمر التنزيلة، أول ما الزرار يبان.
  void _maybeIntro() {
    final flow = _flow;
    if (flow == null || _introQueued || !flow.available || flow.voice.listenIntroDone) return;
    _introQueued = true;
    unawaited(flow.voice.markListenIntroDone());
    unawaited(flow.voice.speakQueued(const ['lis_intro'], force: widget.force));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // **عمرنا ما نسمع في الخلفية**
    if (state != AppLifecycleState.resumed) unawaited(_flow?.cancel());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flow?.voice.removeListener(_maybeIntro);
    _flow?.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    final flow = _flow!;
    final sheet = showListenSheet(context, flow);
    unawaited(flow.start());
    await sheet;
    // اتقفلت بالسحب أو بـ«اقفل» — من غير تطبيق
    if (flow.phase != ListenPhase.done) {
      await flow.cancel();
      return;
    }
    // الورقة اتقفلت الأول، وبعدين التطبيق — بنفس سكّة الزرار
    await flow.applyConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    if (flow == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: flow.voice,
      builder: (context, _) {
        if (!flow.available) return const SizedBox.shrink();
        final size = widget.elder ? F.elderTextSize : F.minTextSize;
        final height = widget.elder ? F.primaryButtonHeight : F.minTapTarget;
        final ink = widget.onDark ? F.onDark : F.ink;
        final hint = widget.hint;
        final button = Semantics(
          button: true,
          label: 'اتكلم',
          child: Material(
            key: ValueKey('listen-${widget.tag}'),
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(F.radiusCard),
              side: BorderSide(color: widget.onDark ? F.onDarkMuted : F.line, width: 1.5),
            ),
            child: InkWell(
              onTap: _tap,
              borderRadius: BorderRadius.circular(F.radiusCard),
              child: Container(
                constraints: BoxConstraints(minHeight: height, minWidth: height),
                padding: EdgeInsets.symmetric(horizontal: widget.elder ? F.s14 : F.s10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_none_outlined, size: widget.elder ? 28 : 22, color: ink),
                    const SizedBox(width: F.s6),
                    Text('اتكلم', style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: ink)),
                  ],
                ),
              ),
            ),
          ),
        );
        if (hint == null) return button;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                hint,
                key: ValueKey('listen-hint-${widget.tag}'),
                style: TextStyle(fontSize: widget.elder ? F.elderTextSize : F.minBodySize, color: ink, height: 1.4),
              ),
            ),
            const SizedBox(width: F.s10),
            button,
          ],
        );
      },
    );
  }
}

/// ورقة السماع: اللي بيحصل بالكلام الكبير، وزرارين «أيوه»/«لأ» لما نفهم —
/// وبتتقفل لوحدها لما الإجابة تتطبّق.
Future<void> showListenSheet(BuildContext context, ListenFlow flow) => FSheet.show<void>(
      context,
      title: 'اتكلم',
      children: [_ListenBody(flow: flow)],
    );

class _ListenBody extends StatefulWidget {
  const _ListenBody({required this.flow});
  final ListenFlow flow;

  @override
  State<_ListenBody> createState() => _ListenBodyState();
}

class _ListenBodyState extends State<_ListenBody> {
  @override
  void initState() {
    super.initState();
    widget.flow.addListener(_onPhase);
    // خلص قبل ما الورقة تتبني (إجابة جاهزة فوراً) — تتقفل برضه
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPhase());
  }

  void _onPhase() {
    if (widget.flow.phase == ListenPhase.done && mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    widget.flow.removeListener(_onPhase);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final body = TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5);
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switch (flow.phase) {
            ListenPhase.listening => Row(
                key: const ValueKey('listen-listening'),
                children: [
                  Icon(Icons.mic, size: 32, color: F.gold),
                  const SizedBox(width: F.s10),
                  Expanded(child: Text('اتكلم، أنا سامعك.', style: body)),
                ],
              ),
            ListenPhase.confirming => Text(
                'فهمت: ${flow.heardText}\nصح كده؟',
                key: const ValueKey('listen-heard'),
                style: TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700, color: F.ink, height: 1.5),
              ),
            ListenPhase.notUnderstood => Text(
                'معلش، مافهمتش. ممكن تقولها تاني، أو تدوس بإيدك.',
                key: const ValueKey('listen-not-understood'),
                style: body,
              ),
            ListenPhase.idle || ListenPhase.done => Text('ثواني…', style: body),
          },
          const SizedBox(height: F.gap),
          if (flow.phase == ListenPhase.confirming) ...[
            FPrimaryButton(key: const ValueKey('listen-yes'), label: 'أيوه', onPressed: flow.confirmYes),
            const SizedBox(height: F.s10),
            FSecondaryButton(key: const ValueKey('listen-no'), label: 'لأ، قول تاني', onPressed: flow.confirmNo),
          ] else if (flow.phase == ListenPhase.notUnderstood) ...[
            FPrimaryButton(key: const ValueKey('listen-again'), label: 'قول تاني', onPressed: flow.start),
            const SizedBox(height: F.s10),
            FSecondaryButton(label: 'اقفل', onPressed: () => Navigator.of(context).maybePop()),
          ] else
            FSecondaryButton(key: const ValueKey('listen-close'), label: 'اقفل', onPressed: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }
}
