import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import '../medication/add_medication_screen.dart';
import '../medication/medication_draft.dart';
import 'command_flow.dart';

/// «🎤 كلّمني» — على «يومك» تحت التحية (أكبر في نمط كبار السن). دوسة →
/// ورقة فيها اللي بيحصل بالكلام الكبير: «اتكلم، أنا سامعك» ← «ثانية واحدة»
/// ← «فهمت: … صح كده؟» + «أيوه»/«لأ» (أو أزرار «أنهي واحد؟») ← الرد.
///
/// بيظهر لما فيه مايك في النسخة والإذن مش مرفوض — **حتى والصوت مقفول**:
/// ساعتها الجمل بتتكتب في الورقة بدل ما تتقال. مفيش `AppScope` = مفيش زرار.
class TalkButton extends StatefulWidget {
  const TalkButton({required this.routine, required this.routineDay, this.elder = false, this.now, this.gapAbove = 0, this.gapBelow = 0, super.key});

  final DayRoutine routine;
  final DateTime routineDay;
  final bool elder;
  final DateTime? now;

  /// مسافات بتظهر **مع** الزرار وبس — لو مش موجود الشاشة زي ما كانت بالبكسل.
  final double gapAbove;
  final double gapBelow;

  @override
  State<TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<TalkButton> with WidgetsBindingObserver {
  CommandFlow? _flow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.maybeOf(context);
    final voice = services?.voice;
    if (services == null || voice == null || _flow != null) return;
    _flow = CommandFlow(
      voice: voice,
      services: services,
      routineDay: widget.routineDay,
      reader: services.commandReader,
      cloudAllowed: services.cloudCommandBudget?.allowed,
      onCloudUsed: services.cloudCommandBudget?.used,
      clock: widget.now == null ? null : () => widget.now!,
      onOpenAdd: _openAdd,
    );
  }

  /// الفورم العادي متعبّي — الحفظ بزراره هو، ومفيش حاجة اتكتبت قبله.
  Future<bool> _openAdd(AddMedPrefill p) async {
    if (!mounted) return false;
    final result = await Navigator.of(context).push<MedicationDraft?>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(
          routine: widget.routine,
          today: widget.routineDay,
          initialName: p.name,
          initialPurpose: p.purpose,
          initialTimings: p.timings,
          initialOnce: p.once,
        ),
      ),
    );
    return result != null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عمرنا ما نسمع في الخلفية
    if (state != AppLifecycleState.resumed) unawaited(_flow?.cancel());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flow?.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    final flow = _flow!;
    final sheet = FSheet.show<void>(context, title: 'كلّمني', children: [_CommandBody(flow: flow)]);
    unawaited(flow.start());
    await sheet;
    if (flow.phase != CommandPhase.done) await flow.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    if (flow == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: flow.voice,
      builder: (context, _) {
        if (!flow.available) return const SizedBox.shrink();
        final height = widget.elder ? 80.0 : F.primaryButtonHeight;
        final size = widget.elder ? F.elderTextSize : F.minBodySize;
        return Padding(
          padding: EdgeInsets.only(top: widget.gapAbove, bottom: widget.gapBelow),
          child: SizedBox(
          height: height,
          child: FilledButton.icon(
            key: const ValueKey('talk-button'),
            onPressed: _tap,
            icon: Icon(Icons.mic, size: widget.elder ? 32 : 26),
            label: Text('كلّمني', style: TextStyle(fontSize: size, fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(
              backgroundColor: F.green,
              foregroundColor: F.onDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
            ),
          ),
          ),
        );
      },
    );
  }
}

class _CommandBody extends StatefulWidget {
  const _CommandBody({required this.flow});
  final CommandFlow flow;

  @override
  State<_CommandBody> createState() => _CommandBodyState();
}

class _CommandBodyState extends State<_CommandBody> {
  @override
  void initState() {
    super.initState();
    widget.flow.addListener(_onPhase);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPhase());
  }

  void _onPhase() {
    if (widget.flow.phase == CommandPhase.done && mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    widget.flow.removeListener(_onPhase);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final big = TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700, color: F.ink, height: 1.5);
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                switch (flow.phase) {
                  CommandPhase.listening => Icons.mic,
                  CommandPhase.thinking => Icons.hourglass_top,
                  _ => Icons.record_voice_over_outlined,
                },
                size: 32,
                color: flow.phase == CommandPhase.listening ? F.gold : F.mutedDark,
              ),
              const SizedBox(width: F.s10),
              Expanded(
                child: Text(flow.shown.isEmpty ? 'ثواني…' : flow.shown, key: const ValueKey('talk-shown'), style: big),
              ),
            ],
          ),
          const SizedBox(height: F.gap),
          switch (flow.phase) {
            CommandPhase.confirming => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FPrimaryButton(key: const ValueKey('talk-yes'), label: 'أيوه', onPressed: flow.confirmYes),
                  const SizedBox(height: F.s10),
                  FSecondaryButton(key: const ValueKey('talk-no'), label: 'لأ', onPressed: flow.confirmNo),
                ],
              ),
            CommandPhase.choosing => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, c) in flow.candidates.indexed) ...[
                    FPrimaryButton(key: ValueKey('talk-pick-$i'), label: c.label, onPressed: () => flow.choose(c)),
                    const SizedBox(height: F.s10),
                  ],
                  FSecondaryButton(key: const ValueKey('talk-no'), label: 'ولا واحد', onPressed: flow.confirmNo),
                ],
              ),
            CommandPhase.answering => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FPrimaryButton(key: const ValueKey('talk-again'), label: 'قول تاني', onPressed: flow.again),
                  const SizedBox(height: F.s10),
                  FSecondaryButton(key: const ValueKey('talk-close'), label: 'تمام', onPressed: () => Navigator.of(context).maybePop()),
                ],
              ),
            _ => FSecondaryButton(key: const ValueKey('talk-close'), label: 'اقفل', onPressed: () => Navigator.of(context).maybePop()),
          },
        ],
      ),
    );
  }
}
