import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/adherence/adherence.dart';
import 'adherence_dots.dart';

/// تفاصيل «إنت ماشي إزاي»: الأسبوع، النسبة، أحسن مرة، و«فاتك كام جرعة
/// الأسبوع ده». الجرعة اللي فاتت ولسه في يوم الروتين النهارده بيبقى جنبها
/// «أخدتها متأخر» — **نفس سكّة التأكيد الموجودة** (المريض: `confirmGroup`؛
/// الممرض: التأكيد نيابةً) — الشاشة دي نفسها ما بتكتبش حاجة.
class AdherenceDetailScreen extends StatefulWidget {
  const AdherenceDetailScreen({
    required this.initial,
    required this.title,
    this.updates,
    this.onLateTake,
    this.missedTitle = 'فاتك كام جرعة الأسبوع ده',
    super.key,
  });

  final Adherence initial;
  final String title;

  /// نفس الحساب وهو بيتحدّث (بعد «أخدتها متأخر» مثلاً).
  final Stream<Adherence>? updates;

  /// null = مفيش «أخدتها متأخر» خالص (عيلة، أو ممرض من غير صلاحية).
  final Future<void> Function(MissedDose missed)? onLateTake;
  final String missedTitle;

  @override
  State<AdherenceDetailScreen> createState() => _AdherenceDetailScreenState();
}

class _AdherenceDetailScreenState extends State<AdherenceDetailScreen> {
  final _busy = <String>{};

  Future<void> _late(MissedDose m) async {
    final act = widget.onLateTake;
    if (act == null || _busy.contains(m.id)) return;
    setState(() => _busy.add(m.id));
    try {
      await act(m);
    } finally {
      if (mounted) setState(() => _busy.remove(m.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: F.pageGround,
        appBar: AppBar(
          backgroundColor: F.pageGround,
          title: Text(widget.title,
              style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, color: F.ink)),
        ),
        body: StreamBuilder<Adherence>(
          stream: widget.updates,
          initialData: widget.initial,
          builder: (context, snap) {
            final a = snap.data ?? widget.initial;
            final text = TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.4);
            return ListView(
              padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
              children: [
                Text(
                  streakLine(a.currentStreak, atLeast: a.currentAtLeast),
                  key: const ValueKey('adherence-detail-streak'),
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.screenTitleSize + 5,
                    fontWeight: FontWeight.w800,
                    color: a.currentStreak > 0 ? F.green : F.ink,
                  ),
                ),
                const SizedBox(height: F.s4),
                Text(streakCheer(a.currentStreak), style: text.copyWith(color: F.mutedDark)),
                const SizedBox(height: F.gap),
                const FSectionHead('الأسبوع ده'),
                const SizedBox(height: F.s8),
                AdherenceDots(week: a.week, today: a.today),
                const SizedBox(height: F.gap),
                Text(takenPercentLine(a.takenPercent), key: const ValueKey('adherence-percent'), style: text),
                const SizedBox(height: F.s8),
                Text(bestStreakLine(a.bestStreak, atLeast: a.bestAtLeast),
                    key: const ValueKey('adherence-best'), style: text),
                const SizedBox(height: F.gap),
                FSectionHead(widget.missedTitle),
                const SizedBox(height: F.s8),
                if (a.missed.isEmpty)
                  Text('مفيش ولا جرعة فاتت في آخر ٧ أيام.', key: const ValueKey('adherence-no-missed'), style: text)
                else
                  for (final m in a.missed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: F.s10),
                      child: Container(
                        key: ValueKey('adherence-missed-${m.id}'),
                        padding: const EdgeInsets.all(F.s14),
                        decoration: BoxDecoration(
                          color: F.cardGround,
                          borderRadius: BorderRadius.circular(F.radiusCard),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(m.medicationName,
                                style: text.copyWith(fontWeight: FontWeight.w700, fontFamily: F.monoFamily, fontFamilyFallback: F.monoFallback)),
                            Text(missedWhen(m, a.today), style: text.copyWith(color: F.mutedDark)),
                            if (widget.onLateTake != null && DateUtils.isSameDay(m.routineDay, a.today)) ...[
                              const SizedBox(height: F.s8),
                              FSecondaryButton(
                                key: ValueKey('adherence-late-${m.id}'),
                                label: _busy.contains(m.id) ? 'لحظة…' : 'أخدتها متأخر',
                                onPressed: _busy.contains(m.id) ? null : () => _late(m),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      );
}
