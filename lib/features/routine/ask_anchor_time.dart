import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';
import '../onboarding/routine_presets.dart';
import '../onboarding/routine_question_page.dart' show PresetRow;

/// **«بتفطر الساعة كام؟» — مرة واحدة، وقت ما دوا يحتاجها.**
///
/// الروتين اختياري؛ لما المستخدم يختار «قبل الفطار» لدوا والفطار لسه
/// مش متحدد، الشيت ده بيسأل عن الفطار وبس: نفس السؤال ونفس الاقتراحات
/// ونفس البكرة بتوع أول مرة. اللي بيرجع بيتحفظ في الروتين **متحدد**، وكل
/// دوا بعده على الفطار بيتربط بيه من غير ما يتسأل تاني.
///
/// بيرجّع null لو قفل من غير ما يختار — ولا حاجة بتتكتب ساعتها.
Future<MinuteOfDay?> askAnchorTime(
  BuildContext context, {
  required DayAnchor anchor,
  required Say say,
}) {
  final question = routineQuestions.firstWhere((q) => q.anchor == anchor);
  return FSheet.show<MinuteOfDay>(
    context,
    title: questionTextFor(question, say),
    children: [_AskAnchorBody(question: question, say: say)],
  );
}

class _AskAnchorBody extends StatefulWidget {
  const _AskAnchorBody({required this.question, required this.say});

  final RoutineQuestion question;
  final Say say;

  @override
  State<_AskAnchorBody> createState() => _AskAnchorBodyState();
}

class _AskAnchorBodyState extends State<_AskAnchorBody> {
  /// null لحد ما يدوس اقتراح أو يحرّك البكرة — «تمام» مقفولة قبلها.
  MinuteOfDay? _picked;

  MinuteOfDay get _shown => _picked ?? widget.question.fallback;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            questionHintFor(widget.question, widget.say),
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.s12),
          // ولا اقتراح ذهبي قبل ما يختار — الذهبي معناه «ده اللي اخترته»
          PresetRow(
            presets: widget.question.presets,
            value: _picked,
            onChanged: (v) => setState(() => _picked = v),
          ),
          const SizedBox(height: F.s12),
          Text(
            _picked == null ? 'اختار اقتراح أو حرّك البكرة' : arabicTime(DateTime(2026, 1, 1, _shown.hour, _shown.minute)),
            key: const ValueKey('anchor-picked'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _picked == null ? F.minTextSize : F.subtitleSize,
              fontWeight: FontWeight.w700,
              color: _picked == null ? F.mutedDark : F.ink,
            ),
          ),
          const SizedBox(height: F.s8),
          FTimeWheel(value: _shown, onChanged: (v) => setState(() => _picked = v)),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('anchor-confirm'),
            label: 'تمام',
            onPressed: _picked == null ? null : () => Navigator.of(context).pop(_picked),
          ),
        ],
      );
}
