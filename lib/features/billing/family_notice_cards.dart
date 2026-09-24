import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/billing/subscription_service.dart';
import '../../domain/billing/family_plan.dart';
import 'family_plan_screen.dart';

/// بيفتح «اشتراك العيلة» — الباب الواحد لـ«جدّد» على الناحيتين.
Future<void> openFamilyPlan(
  BuildContext context,
  SubscriptionService service, {
  required String patientName,
  List<String> coveredNames = const [],
}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FamilyPlanScreen(service: service, patientName: patientName, coveredNames: coveredNames),
    ));

/// **عند المريض على «يومك»** — قبل النهاية: «تنبيهات محمد هتقف يوم …»،
/// وبعدها سطر واحد: «اللي بيتابعوك مش بيتبلّغوا دلوقتي». الاتنين معاهم
/// «جدّد». مفيش كلمة تقنية، ومفيش حاجة لو محدش بيتابعه أصلاً.
///
/// **التذكير نفسه مش بيقرا من هنا** — ده كلام عن تنبيهات المتابعين بس.
class PatientFamilyNotice extends StatelessWidget {
  const PatientFamilyNotice({
    required this.followerNames,
    required this.followersKnown,
    this.now,
    super.key,
  });

  final List<String> followerNames;

  /// عرفنا مين بيتابعه (حتى لو محدش)؟ فشل القراية ≠ «محدش بيتابعك».
  final bool followersKnown;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.maybeOf(context);
    final service = services?.subscription;
    if (services == null || service == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        // محدش بيتابعه → مفيش تنبيهات تقف
        if (followersKnown && followerNames.isEmpty) return const SizedBox.shrink();
        final notice = service.notice(now: now);
        final String text;
        switch (notice.kind) {
          case FamilyNoticeKind.none:
            return const SizedBox.shrink();
          case FamilyNoticeKind.endingSoon:
            text = familyEndingLine(notice: notice, date: arabicDate, followerNames: followerNames);
          case FamilyNoticeKind.ended:
            text = familyEndedPatientLine;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: F.gap),
          child: Container(
            key: ValueKey('family-notice-${notice.kind.name}'),
            padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
            decoration: BoxDecoration(
              color: F.cardGround,
              borderRadius: BorderRadius.circular(F.radiusCard),
              border: const BorderDirectional(start: BorderSide(color: F.gold, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  text,
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.45),
                ),
                const SizedBox(height: F.s8),
                FSecondaryButton(
                  key: const ValueKey('family-notice-renew'),
                  label: 'جدّد',
                  onPressed: () async {
                    final patient = await services.routines.getPatient(services.patientId);
                    if (!context.mounted) return;
                    await openFamilyPlan(
                      context,
                      service,
                      patientName: patient?.name.trim().isNotEmpty == true ? patient!.name : 'أنا',
                      coveredNames: followerNames,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
