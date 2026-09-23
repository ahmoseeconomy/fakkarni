import 'package:flutter/material.dart';

import '../data/admin_models.dart';
import '../format/arabic_time.dart';
import '../format/grouped.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'widgets/accounts_table.dart';
import 'widgets/admin_ui.dart';
import 'widgets/counts_strip.dart';
import 'widgets/motion_widgets.dart';
import 'widgets/status_cues.dart';
import 'widgets/tone_filter_chips.dart';

/// ترتيب نسخ زي `1.6.0+42`: بالأرقام جزء جزء، مش بالحروف.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final p in v.split(RegExp(r'[.+]')))
          int.tryParse(p) ?? 0,
      ];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// النسخ اللي في الأسطول مرتّبة من الأحدث، بعدد كل واحدة.
List<(String, int)> versionShares(List<AdminAccount> accounts) {
  final counts = <String, int>{};
  for (final a in accounts) {
    final v = a.appVersion;
    if (v != null) counts[v] = (counts[v] ?? 0) + 1;
  }
  final out = counts.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => compareVersions(b.$1, a.$1));
  return out;
}

/// «قديمة» = مش من أحدث تلات نسخ **موجودة في الأسطول**. ده تقريب من الأسطول
/// نفسه، مش قايمة إصدارات — قايمة الإصدارات بتيجي من السيرفر يوم ما تتعمل.
const int latestVersionsKept = 3;

Set<String> oldVersions(List<AdminAccount> accounts) {
  final ordered = versionShares(accounts).map((e) => e.$1).toList();
  return ordered.skip(latestVersionsKept).toSet();
}

/// المشكلة اللي بتحط الجهاز في «محتاجين تدخّل».
String deviceProblem(AdminAccount a) {
  final battery = a.batteryRestricted;
  final horizon = a.seenAt != null && !a.reminderHorizonOk;
  if (battery && horizon) return 'البطارية مقيّدة والمدى خلص';
  if (battery) return 'البطارية مقيّدة';
  return 'مدى التذكير خلص';
}

/// صحة الأجهزة — كلها محسوبة من صفوف الحسابات نفسها. **مفيش «ابعت نبضة»**:
/// ده فعل كتابة على السيرفر مش موجود (`0022` المقترحة).
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({
    required this.accounts,
    required this.now,
    required this.onOpen,
    required this.onNavigate,
    super.key,
  });

  final List<AdminAccount> accounts;
  final DateTime now;
  final void Function(AdminAccount account) onOpen;
  final void Function(AdminScreen screen, {ToneFilter? tone}) onNavigate;

  static const needyLimit = 10;

  @override
  Widget build(BuildContext context) {
    final withHeartbeat = accounts.where((a) => a.seenAt != null).length;
    final restricted = accounts.where((a) => a.batteryRestricted).length;
    final horizonExpired = accounts.where((a) => a.seenAt != null && !a.reminderHorizonOk).length;
    final old = oldVersions(accounts);
    final onOld = accounts.where((a) => a.appVersion != null && old.contains(a.appVersion)).length;
    final needy = [
      for (final a in accounts)
        if (rowTone(a, now) == RowTone.warn) a,
    ];
    final shares = versionShares(accounts);
    final largest = shares.isEmpty ? 1 : shares.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
    final android = accounts.where((a) => a.platform == 'android').length;
    final ios = accounts.where((a) => a.platform == 'ios').length;
    final known = android + ios;

    final needyCard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminHead('محتاجين تدخّل'),
        const SizedBox(height: F.s10),
        if (needy.isEmpty)
          const AdminPanel(text: 'مفيش جهاز محتاج تدخّل دلوقتي.')
        else
          Container(
            decoration: BoxDecoration(
              color: F.cardGround,
              border: Border.all(color: F.line),
              borderRadius: BorderRadius.circular(F.careRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, a) in needy.take(needyLimit).indexed)
                  FadeSlideIn(
                    delay: staggerDelay(context, i),
                    child: InkWell(
                      onTap: () => onOpen(a),
                      hoverColor: F.greenTint,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: F.lineSoft)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: a.patientName.isEmpty ? 'من غير اسم' : a.patientName,
                                    style: TextStyle(
                                      fontFamily: F.bodyFamily,
                                      fontSize: F.careTextSize,
                                      fontWeight: FontWeight.w600,
                                      color: F.ink,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' — ${deviceWord(a)}',
                                    style: TextStyle(
                                      fontFamily: F.bodyFamily,
                                      fontSize: F.careMicroSize,
                                      color: F.mutedDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.error_rounded, size: 14, color: F.gold),
                                const SizedBox(width: F.s6),
                                Text(
                                  deviceProblem(a),
                                  style: TextStyle(
                                    fontFamily: F.bodyFamily,
                                    fontSize: F.careMicroSize,
                                    color: F.mutedDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
                  child: Text(
                    needy.length > needyLimit
                        ? 'وكمان ${arabicNumber(needy.length - needyLimit)} جهاز — افتحهم من الحسابات بفلتر «ملاحظة».'
                        : 'دول كل اللي محتاجين تدخّل.',
                    style: TextStyle(
                        fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.mutedDark),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final versionsCard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminHead('نسخ التطبيق'),
        const SizedBox(height: F.s10),
        AdminCard(
          padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shares.isEmpty)
                Text('لسه مفيش نبضة فيها نسخة.',
                    style: TextStyle(
                        fontFamily: F.bodyFamily, fontSize: F.careTextSize, color: F.mutedDark)),
              for (final (i, (version, n)) in shares.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: F.s6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                version,
                                textDirection: TextDirection.ltr,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: F.monoFamily,
                                  fontFamilyFallback: F.monoFallback,
                                  fontSize: 13,
                                  color: F.ink,
                                ),
                              ),
                            ),
                            if (i == 0) ...[
                              const SizedBox(width: F.s6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: F.greenTint,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('الأحدث',
                                    style: TextStyle(
                                        fontFamily: F.bodyFamily,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: F.green)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) => Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: F.railGround,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              width: c.maxWidth * n / largest,
                              decoration: BoxDecoration(
                                color: old.contains(version) ? F.gold : F.green,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: F.s10),
                      SizedBox(
                        width: 56,
                        child: Text(
                          arabicGrouped(n),
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontFamily: F.bodyFamily, fontSize: 13, color: F.mutedDark),
                        ),
                      ),
                    ],
                  ),
                ),
              Divider(color: F.lineSoft, height: F.s16),
              Wrap(
                spacing: F.s16,
                runSpacing: F.s6,
                children: [
                  _Platform(Icons.android_rounded, 'أندرويد', android, known),
                  _Platform(Icons.phone_iphone_rounded, 'آيفون', ios, known),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatCards([
          StatSpec(Icons.smartphone_rounded, 'موبايلات بتبعت نبضة', withHeartbeat),
          StatSpec(Icons.battery_alert_rounded, 'بطارية مقيّدة', restricted, attention: restricted > 0),
          StatSpec(Icons.schedule_rounded, 'مدى التذكير خلص', horizonExpired, attention: horizonExpired > 0),
          StatSpec(Icons.system_update_rounded, 'على نسخة قديمة', onOld, attention: onOld > 0),
        ]),
        const SizedBox(height: F.s16),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 860) {
              return Column(children: [needyCard, const SizedBox(height: F.s16), versionsCard]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: needyCard),
                const SizedBox(width: F.s16),
                Expanded(child: versionsCard),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Platform extends StatelessWidget {
  const _Platform(this.icon, this.word, this.n, this.total);

  final IconData icon;
  final String word;
  final int n;
  final int total;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontFamily: F.bodyFamily, fontSize: 13, color: F.mutedDark);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: F.mutedDark),
        const SizedBox(width: F.s6),
        Text(word, style: muted),
        const SizedBox(width: F.s4),
        Text(arabicGrouped(n),
            style: TextStyle(
                fontFamily: F.bodyFamily, fontSize: 13, fontWeight: FontWeight.w700, color: F.ink)),
        const SizedBox(width: F.s4),
        Text('(${total == 0 ? '٠٫٠٪' : arabicPercent(n / total)})', style: muted),
      ],
    );
  }
}
