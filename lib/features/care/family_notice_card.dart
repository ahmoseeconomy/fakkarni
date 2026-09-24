import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/billing/family_plan.dart';
import '../billing/family_notice_cards.dart';
import 'caregiver_ui.dart';

/// **عند المتابع والممرض** — فوق كل حاجة على «متابعة» و«مرآة».
///
/// قبل النهاية: «تنبيهاتك عن الحاج أحمد هتقف يوم …». بعدها كارت **دايم**
/// (مالوش «تمام»): «التنبيهات واقفة — مش هتتبلّغ لو الحاج أحمد فوّت جرعة».
/// ده بالظبط اللي السيرفر بطّله، فالكارت لازم يفضل لحد ما يرجع. الاتنين
/// معاهم «جدّد». الذهبي على الحد والعلامة، والنص بلون المتن — ولا أحمر:
/// مش طوارئ ومش خطأ.
class CareFamilyNotice extends StatelessWidget {
  const CareFamilyNotice({required this.patientName, this.now, super.key});

  final String patientName;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final service = AppScope.maybeOf(context)?.subscription;
    if (service == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final notice = service.notice(now: now);
        final String text;
        switch (notice.kind) {
          case FamilyNoticeKind.none:
            return const SizedBox.shrink();
          case FamilyNoticeKind.endingSoon:
            text = familyEndingLine(notice: notice, date: arabicDate, patientName: patientName, forFollower: true);
          case FamilyNoticeKind.ended:
            text = familyEndedFollowerLine(patientName);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: F.careRowGap),
          child: CareCard(
            key: ValueKey('care-family-notice-${notice.kind.name}'),
            border: F.gold,
            edge: F.gold,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_paused_outlined, size: 20, color: F.gold),
                    const SizedBox(width: F.s8),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.45),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: CareTextAction(
                    key: const ValueKey('care-family-notice-renew'),
                    label: 'جدّد',
                    icon: Icons.family_restroom_outlined,
                    onPressed: () => openFamilyPlan(context, service, patientName: patientName),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
