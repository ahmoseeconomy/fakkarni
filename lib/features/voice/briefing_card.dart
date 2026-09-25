import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/db/app_database.dart';
import '../../data/dose_state.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/services/appointment_card.dart';
import '../../data/voice/voice_service.dart';
import '../../domain/adherence/adherence.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../../domain/voice/briefing.dart';
import '../../domain/wording/rule_wording.dart';
import '../adherence/adherence_sources.dart';

/// مدخلات ملخص اليوم من بيانات «يومك» **المحلية** — الصفوف اللي المحرّك
/// نزّلها، والجداول، والمتابعات المفتوحة، وأسبوع الجرعات اللي فات. مفيش
/// حساب جدولة هنا: الأوقات من `dose_events` زي ما هي.
BriefingInput briefingInputFor({
  required DateTime now,
  required DateTime routineDay,
  required List<DoseEventView> today,
  required List<DoseSchedule> schedules,
  required List<RecordRow> openFollowUps,
  required List<DoseEventView> lastWeek,
}) {
  final live = [for (final e in today) if (e.state != DoseState.superseded) e]
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  final minutes = {for (final e in live) e.scheduledAt.millisecondsSinceEpoch ~/ 60000};

  String? wording;
  DateTime? firstAt;
  if (live.isNotEmpty) {
    final first = live.first;
    firstAt = first.scheduledAt;
    for (final s in schedules) {
      if (s.id != first.doseScheduleId.toString()) continue;
      if (s.timing case AnchorTiming(:final anchor, :final offsetMinutes)) {
        wording = spokenTimingWording(anchorWords[anchor.name]!, offsetMinutes);
      }
    }
  }

  final appointments = [
    for (final a in upcomingAppointments(openFollowUps, now: now))
      if (a.at.year == now.year && a.at.month == now.month && a.at.day == now.day)
        BriefingAppointment(kind: a.kind == FollowKind.visit ? 'دكتور' : 'تحليل', at: a.at),
  ];

  final adherence = computeAdherence(dosesFromViews(lastWeek), today: routineDay, now: now);
  final yesterday = DateTime(routineDay.year, routineDay.month, routineDay.day - 1);
  var outcome = YesterdayOutcome.nothing;
  for (final d in adherence.week) {
    if (d.day.year == yesterday.year && d.day.month == yesterday.month && d.day.day == yesterday.day) {
      outcome = switch (d.mark) {
        DayMark.complete => YesterdayOutcome.complete,
        DayMark.missed => YesterdayOutcome.missed,
        _ => YesterdayOutcome.nothing,
      };
    }
  }

  return BriefingInput(
    now: now,
    dosesToday: minutes.length,
    firstDoseAt: firstAt,
    firstDoseWording: wording,
    appointments: appointments,
    yesterday: outcome,
    streak: adherence.currentStreak,
  );
}

String briefingDayKey(DateTime routineDay) =>
    '${routineDay.year}-${routineDay.month.toString().padLeft(2, '0')}-${routineDay.day.toString().padLeft(2, '0')}';

/// كارت ملخص اليوم: نفس الكلام مكتوب، و«اسمع تاني». بيتقال **مرة واحدة أول
/// فتحة في يوم الروتين**، ولما الصوت شغّال، ولما فيه حاجة تتقال.
/// [ready] = كل مصادر البيانات وصلت — قبلها ما بنقولش ملخص ناقص.
class BriefingCard extends StatefulWidget {
  const BriefingCard({
    required this.voice,
    required this.input,
    required this.dayKey,
    required this.ready,
    super.key,
  });

  final VoiceService voice;
  final BriefingInput input;
  final String dayKey;
  final bool ready;

  @override
  State<BriefingCard> createState() => _BriefingCardState();
}

class _BriefingCardState extends State<BriefingCard> {
  bool _spoken = false;

  @override
  void didUpdateWidget(BriefingCard old) {
    super.didUpdateWidget(old);
    _maybeSpeak();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSpeak());
  }

  void _maybeSpeak() {
    if (_spoken || !widget.ready || !mounted) return;
    final text = briefingText(widget.input);
    if (text == null || !widget.voice.shouldBrief(widget.dayKey)) return;
    _spoken = true;
    unawaited(widget.voice.markBriefed(widget.dayKey));
    unawaited(widget.voice.speakText(text));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.voice,
        builder: (context, _) {
          final text = widget.ready ? briefingText(widget.input) : null;
          if (!widget.voice.enabled || text == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: F.gap),
            child: Container(
              key: const ValueKey('briefing-card'),
              padding: const EdgeInsets.all(F.s14),
              decoration: BoxDecoration(
                color: F.cardGround,
                borderRadius: BorderRadius.circular(F.radiusCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.record_voice_over_outlined, size: 24, color: F.green),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: Text(
                          text,
                          key: const ValueKey('briefing-text'),
                          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: F.s8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      key: const ValueKey('briefing-replay'),
                      onPressed: () => widget.voice.speakText(text),
                      icon: Icon(Icons.replay, size: 22, color: F.ink),
                      label: const Text('اسمع تاني'),
                      style: TextButton.styleFrom(
                        foregroundColor: F.ink,
                        minimumSize: const Size(F.minTapTarget, F.minTapTarget),
                        textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
