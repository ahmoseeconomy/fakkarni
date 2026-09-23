import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../data/admin_service.dart';
import '../../format/arabic_time.dart';
import '../../format/relative_time.dart';
import '../../model/follower_profile.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'status_cues.dart';

String deliveryWord(String? status) => switch (status) {
      'sent' => 'اتبعت',
      'no_token' => 'مفيش توكن للجهاز',
      'failed' => 'ما وصلش',
      'claimed' => 'في الطريق',
      _ => status ?? 'مش معروف',
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
    return Container(
      color: F.pageGround,
      padding: const EdgeInsets.all(F.s16),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: AdminHead(
                  account.patientName.isEmpty ? 'من غير اسم' : account.patientName,
                ),
              ),
              AdminTextAction(label: 'اقفل', onPressed: onClose),
            ],
          ),
          const SizedBox(height: F.s4),
          Row(
            children: [
              ToneBadge(rowTone(account, now)),
              const SizedBox(width: F.s8),
              Expanded(
                child: Text(
                  account.seenAt == null
                      ? 'الموبايل عمره ما بعت نبضة'
                      : 'آخر نبضة ${timeSince(now, account.seenAt!)}',
                  style: _muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s16),
          const AdminHead('مين بيتابعه'),
          const SizedBox(height: F.careRowGap),
          if (loading && followers.isEmpty && failure == null)
            const AdminPanel(text: 'بنجيب البيانات…')
          else if (failure != null)
            AdminPanel(text: failure.message, action: 'حاول تاني', onAction: onRetry)
          else if (followers.isEmpty)
            const AdminPanel(text: 'مفيش حد مربوط بيه.')
          else
            for (final follower in followers)
              Padding(
                padding: const EdgeInsets.only(bottom: F.careRowGap),
                child: AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        follower.displayName?.isNotEmpty == true
                            ? follower.displayName!
                            : 'من غير اسم',
                        style: _body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: F.s4),
                      Text(
                        '${relationWord(follower.relation)} — '
                        '${follower.status == 'accepted' ? 'مربوط' : 'لسه ما قبلش'}'
                        '${follower.linkedAt == null ? '' : ' — ${arabicDate(follower.linkedAt!)}'}',
                        style: _muted,
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: F.s16),
          const AdminHead('آخر التنبيهات'),
          const SizedBox(height: F.careRowGap),
          if (failure == null && escalations.isEmpty && !loading)
            const AdminPanel(text: 'مفيش تنبيهات اتبعتت.')
          else
            for (final alert in escalations)
              Padding(
                padding: const EdgeInsets.only(bottom: F.careRowGap),
                child: AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deliveryWord(alert.deliveryStatus),
                          style: _body.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: F.s4),
                      Text(
                        alert.scheduledAt == null
                            ? 'من غير ميعاد'
                            : 'الجرعة ${arabicDate(alert.scheduledAt!)} '
                                '${arabicTime(alert.scheduledAt!)}',
                        style: _muted,
                      ),
                      if (alert.createdAt != null)
                        Text(timeSince(now, alert.createdAt!), style: _muted),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
