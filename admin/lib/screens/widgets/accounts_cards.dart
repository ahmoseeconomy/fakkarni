import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../format/arabic_time.dart';
import '../../format/relative_time.dart';
import '../../theme/tokens.dart';
import 'accounts_table.dart';
import 'admin_ui.dart';
import 'status_cues.dart';

/// **نفس الصفوف، بس ككروت** — للشاشة الضيّقة (موبايل المدير).
///
/// جدول بعشرة أعمدة على شاشة ٣٩٠ بكسل بيبقى تمرير أفقي، والمدير بيفتح
/// اللوحة وهو ماشي عشان يبص بصة. الكارت بيحط اللي بيتقري الأول فوق —
/// الاسم والحالة — والأرقام تحته كأزواج «كلمة: رقم».
///
/// **مفيش عمود بيتشال**: نفس بيانات [AccountsTable] بالحرف، متلمّة تاني.
class AccountsCards extends StatelessWidget {
  const AccountsCards({
    required this.accounts,
    required this.now,
    required this.onOpen,
    this.selected,
    super.key,
  });

  final List<AdminAccount> accounts;
  final DateTime now;
  final void Function(AdminAccount account) onOpen;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final account in accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: F.careRowGap),
            child: _AccountCard(
              account: account,
              now: now,
              onOpen: () => onOpen(account),
              isSelected: account.patientUuid == selected,
            ),
          ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.now,
    required this.onOpen,
    required this.isSelected,
  });

  final AdminAccount account;
  final DateTime now;
  final VoidCallback onOpen;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final tone = rowTone(account, now);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(F.careRadius),
        child: AdminCard(
          edge: isSelected ? toneColour(tone) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      account.patientName.isEmpty ? 'من غير اسم' : account.patientName,
                      style: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careBodySize,
                        fontWeight: FontWeight.w700,
                        color: F.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: F.s8),
                  ToneBadge(tone),
                ],
              ),
              const SizedBox(height: F.s4),
              Text(
                '${deviceWord(account)} — بطارية ${batteryWord(account.batteryState)}',
                style: TextStyle(
                  fontFamily: F.bodyFamily,
                  fontSize: F.careMicroSize,
                  color: F.mutedDark,
                ),
              ),
              Text(
                account.lastSyncAt == null
                    ? 'مفيش مزامنة'
                    : 'آخر مزامنة ${timeSince(now, account.lastSyncAt!)}',
                style: TextStyle(
                  fontFamily: F.bodyFamily,
                  fontSize: F.careMicroSize,
                  color: F.mutedDark,
                ),
              ),
              const SizedBox(height: F.careRowGap),
              // الأرقام كأزواج بتلفّ — نفس أعمدة الجدول بالحرف.
              Wrap(
                spacing: F.s12,
                runSpacing: F.s4,
                children: [
                  _stat('ما اتأكدتش ٢٤ س', account.missedDoses24h),
                  _stat('تنبيهات مفتوحة', account.pendingEscalations),
                  _stat('تنبيهات ٧ أيام', account.escalations7d),
                  _stat('متابعين', account.followersCount),
                  _stat('أكواد مستنية', account.pendingInvites),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int value) => RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontFamily: F.bodyFamily,
                fontSize: F.careMicroSize,
                color: F.mutedDark,
              ),
            ),
            TextSpan(
              text: arabicNumber(value),
              style: TextStyle(
                fontFamily: F.bodyFamily,
                fontSize: F.careTextSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
              ),
            ),
          ],
        ),
      );
}
