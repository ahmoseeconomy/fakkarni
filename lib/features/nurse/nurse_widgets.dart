import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/billing/family_plan.dart';
import '../billing/family_notice_cards.dart';
import '../care/caregiver_words.dart' show timeAhead;

/// التأكيد نيابةً مسموح على الجرعة دي؟ **نفس شرط السيرفر**
/// (`private.dose_confirmable`): لسه مفتوحة، ووقتها جه (أو فاضل ٥ دقايق).
bool nurseCanConfirmEvent(CaregiverDoseEvent e, DateTime now) =>
    (e.state == 'pending' || e.state == 'missed') &&
    !e.scheduledAt.isAfter(now.add(const Duration(minutes: 5)));

/// الحالة بكلام البيت — نفس روح «يومك» عند المريض: «لسه ما اتأكدتش»، مش
/// «فاتت» ولا أحمر.
String nurseStateLine(CaregiverDoseEvent e, DateTime now, {required bool proxied}) {
  if (proxied) return 'أكّدتها ✓ — مستنية موبايله يوصلها';
  return switch (e.state) {
    'taken' => e.actedAt == null ? 'اتاخدت ✓' : 'اتاخدت ${arabicTime(e.actedAt!)} ✓',
    'skipped' => 'قال مش هياخدها',
    _ when e.scheduledAt.isAfter(now) => timeAhead(now, e.scheduledAt),
    _ => 'لسه ما اتأكدتش',
  };
}

/// صف جرعة بمقاسات تطبيق المريض — الوقت، الاسم والجرعة، والحالة. الزرار
/// بيظهر بس لو التأكيد مسموح فعلاً.
class NurseDoseRow extends StatelessWidget {
  const NurseDoseRow({
    required this.event,
    required this.now,
    required this.proxied,
    this.onConfirm,
    this.busy = false,
    this.big = false,
    super.key,
  });

  final CaregiverDoseEvent event;
  final DateTime now;
  final bool proxied;
  final VoidCallback? onConfirm;
  final bool busy;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final open = !proxied && nurseCanConfirmEvent(event, now);
    final needsYou = open; // «دي لسه عايزاك» — الذهبي بمعناه الواحد
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s10),
      child: Container(
        key: ValueKey('nurse-dose-${event.uuid}'),
        padding: const EdgeInsets.all(F.s14),
        decoration: BoxDecoration(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
          border: BorderDirectional(
            start: BorderSide(color: needsYou ? F.gold : F.line, width: needsYou ? 4 : 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  arabicTime(event.scheduledAt),
                  style: TextStyle(fontSize: big ? F.subtitleSize : F.minBodySize, fontWeight: FontWeight.w800, color: F.ink),
                ),
                const SizedBox(width: F.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.medicationName,
                        style: TextStyle(
                          fontSize: F.minBodySize,
                          fontWeight: FontWeight.w700,
                          color: F.ink,
                          fontFamily: F.monoFamily,
                          fontFamilyFallback: F.monoFallback,
                        ),
                      ),
                      if (event.amountLabel case final amount?)
                        Text(amount, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                      Text(
                        nurseStateLine(event, now, proxied: proxied),
                        style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (open && onConfirm != null) ...[
              const SizedBox(height: F.s10),
              (big ? FPrimaryButton.new : FSecondaryButton.new)(
                key: ValueKey('nurse-confirm-${event.uuid}'),
                label: busy ? 'ثواني…' : nurseConfirmLabel,
                onPressed: busy ? null : onConfirm,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const String nurseConfirmLabel = 'أكّد إنه أخدها';

/// «التنبيهات هتقف / واقفة» بمقاسات المريض — نفس القرار (`familyNotice`)
/// ونفس كلام المتابع، و«جدّد».
class NurseFamilyNotice extends StatelessWidget {
  const NurseFamilyNotice({required this.patientName, this.now, super.key});

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
            // الممرض بيشوف بس لحد ما يتجدد — ده بيتقال هنا مرة واحدة
            text = '${familyEndedFollowerLine(patientName)}. ومن غير الاشتراك مش هتقدر تأكّد ولا تعدّل.';
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: F.gap),
          child: Container(
            key: ValueKey('nurse-family-notice-${notice.kind.name}'),
            padding: const EdgeInsets.all(F.s14),
            decoration: BoxDecoration(
              color: F.cardGround,
              borderRadius: BorderRadius.circular(F.radiusCard),
              border: const BorderDirectional(start: BorderSide(color: F.gold, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(text, style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.45)),
                const SizedBox(height: F.s8),
                FSecondaryButton(
                  key: const ValueKey('nurse-family-renew'),
                  label: 'جدّد',
                  onPressed: () => openFamilyPlan(context, service, patientName: patientName),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// سطر رمادي هادي — «مفيش …» وما يشبهه.
class NurseQuietLine extends StatelessWidget {
  const NurseQuietLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s10),
        child: Text(text, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
      );
}
