import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../data/admin_service.dart';
import '../../format/arabic_time.dart';
import '../../format/relative_time.dart';
import '../../model/follower_profile.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'motion_widgets.dart';
import 'status_cues.dart';

String deliveryWord(String? status) => switch (status) {
      'sent' => 'اتبعت',
      'no_token' => 'مفيش توكن للجهاز',
      'failed' => 'ما وصلش',
      'claimed' => 'في الطريق',
      _ => status ?? 'مش معروف',
    };

/// لون نقطة الخط الزمني — والكلمة جنبها دايماً.
Color deliveryColour(String? status) => switch (status) {
      'sent' => F.green,
      'no_token' => F.gold,
      'failed' => F.outOfRangeInk,
      _ => F.mutedDark,
    };

/// صلة المتابع بالكلمة اللي هو اختارها — نفس `FollowerRelation` بتاعة
/// التطبيق، فالكلمة واحدة في الناحيتين.
String relationWord(String? stored) {
  final known = FollowerRelation.fromStored(stored);
  if (known != null && known != FollowerRelation.other) return known.label;
  final text = stored?.trim() ?? '';
  if (text.isEmpty || text == 'other') return FollowerRelation.other.label;
  return text;
}

/// أول حرف من الاسم — للدايرة اللي جنب المتابع. من غير اسم: نقطة.
String initialOf(String? name) {
  final n = name?.trim() ?? '';
  return n.isEmpty ? '•' : n.characters.first;
}

/// لوحة جانبية: مين بيتابعه، وآخر تنبيهات. **مفيش أي اسم دوا هنا** —
/// الدوال في السحابة ما بترجّعوش أصلاً.
class AccountPanel extends StatelessWidget {
  const AccountPanel({
    required this.account,
    required this.now,
    required this.followers,
    required this.escalations,
    required this.loading,
    required this.onClose,
    this.error,
    this.onRetry,
    super.key,
  });

  final AdminAccount account;
  final DateTime now;
  final List<AdminFollower> followers;
  final List<AdminEscalation> escalations;
  final bool loading;
  final VoidCallback onClose;
  final AdminException? error;
  final VoidCallback? onRetry;

  TextStyle get _body =>
      TextStyle(fontFamily: F.bodyFamily, fontSize: F.careTextSize, color: F.ink);

  TextStyle get _muted => TextStyle(
      fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.mutedDark);

  @override
  Widget build(BuildContext context) {
    final failure = error;
    final tone = rowTone(account, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // رأس اللوحة على أرضية العلامة — نفس لون الشريط العلوي.
        Material(
          color: brandGround,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(F.s16, F.s16, F.s8, F.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.patientName.isEmpty ? 'من غير اسم' : account.patientName,
                        style: TextStyle(
                          fontFamily: F.displayFamily,
                          fontSize: F.screenTitleSize,
                          fontWeight: FontWeight.w700,
                          color: F.onDark,
                        ),
                      ),
                    ),
                    AdminTextAction(label: 'اقفل', onDark: true, onPressed: onClose),
                  ],
                ),
                const SizedBox(height: F.s6),
                Row(
                  children: [
                    ToneBadge(tone),
                    const SizedBox(width: F.s8),
                    Expanded(
                      child: Text(
                        account.seenAt == null
                            ? 'الموبايل عمره ما بعت نبضة'
                            : 'آخر نبضة ${timeSince(now, account.seenAt!)}',
                        style: const TextStyle(
                          fontFamily: F.bodyFamily,
                          fontSize: F.careMicroSize,
                          color: F.onDarkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(F.s16),
            children: [
              const AdminHead('مين بيتابعه'),
              const SizedBox(height: F.careRowGap),
              if (loading && followers.isEmpty && failure == null)
                const _PanelSkeleton()
              else if (failure != null)
                AdminPanel(text: failure.message, action: 'حاول تاني', onAction: onRetry)
              else if (followers.isEmpty)
                const AdminPanel(text: 'مفيش حد مربوط بيه.')
              else
                Wrap(
                  spacing: F.s8,
                  runSpacing: F.s8,
                  children: [
                    for (final (i, follower) in followers.indexed)
                      FadeSlideIn(
                        delay: staggerDelay(context, i),
                        child: _FollowerChip(follower: follower, body: _body, muted: _muted),
                      ),
                  ],
                ),
              const SizedBox(height: F.s20),
              const AdminHead('آخر التنبيهات'),
              const SizedBox(height: F.careRowGap),
              if (failure == null && escalations.isEmpty && !loading)
                const AdminPanel(text: 'مفيش تنبيهات اتبعتت.')
              else
                for (final (i, alert) in escalations.indexed)
                  FadeSlideIn(
                    delay: staggerDelay(context, i),
                    child: _TimelineItem(
                      alert: alert,
                      now: now,
                      last: i == escalations.length - 1,
                      body: _body,
                      muted: _muted,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// متابع: دايرة بأول حرف من اسمه، وجنبها الاسم والصلة والحالة.
class _FollowerChip extends StatelessWidget {
  const _FollowerChip({required this.follower, required this.body, required this.muted});

  final AdminFollower follower;
  final TextStyle body;
  final TextStyle muted;

  @override
  Widget build(BuildContext context) {
    final name = follower.displayName?.isNotEmpty == true ? follower.displayName! : 'من غير اسم';
    final accepted = follower.status == 'accepted';
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(F.s6, F.s6, F.s14, F.s6),
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(color: F.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accepted ? F.green : F.mutedDark,
            child: Text(
              initialOf(follower.displayName),
              style: const TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.careBodySize,
                fontWeight: FontWeight.w700,
                color: F.onDark,
              ),
            ),
          ),
          const SizedBox(width: F.s10),
          // الاسم والصلة بيلفّوا جوّه الحبّة — صلة طويلة كانت بتطلع برّه الكارت.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: body.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '${relationWord(follower.relation)} — '
                  '${accepted ? 'مربوط' : 'لسه ما قبلش'}'
                  '${follower.linkedAt == null ? '' : ' — ${arabicDate(follower.linkedAt!)}'}',
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// عنصر في الخط الزمني: نقطة بلون حالة التسليم، وخط لتحت، والكلام جنبه.
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.alert,
    required this.now,
    required this.last,
    required this.body,
    required this.muted,
  });

  final AdminEscalation alert;
  final DateTime now;
  final bool last;
  final TextStyle body;
  final TextStyle muted;

  @override
  Widget build(BuildContext context) {
    final colour = deliveryColour(alert.deliveryStatus);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: F.s4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colour,
                    border: Border.all(color: F.pageGround, width: 2),
                  ),
                ),
                if (!last)
                  Expanded(child: Container(width: 2, color: F.line)),
              ],
            ),
          ),
          const SizedBox(width: F.s8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: F.s14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deliveryWord(alert.deliveryStatus),
                      style: body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    alert.scheduledAt == null
                        ? 'من غير ميعاد'
                        : 'الجرعة ${arabicDate(alert.scheduledAt!)} '
                            '${arabicTime(alert.scheduledAt!)}',
                    style: muted,
                  ),
                  if (alert.createdAt != null)
                    Text(timeSince(now, alert.createdAt!), style: muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSkeleton extends StatelessWidget {
  const _PanelSkeleton();

  @override
  Widget build(BuildContext context) => const Wrap(
        spacing: F.s8,
        runSpacing: F.s8,
        children: [
          Shimmer(width: 160, height: 48, radius: 24),
          Shimmer(width: 140, height: 48, radius: 24),
        ],
      );
}
