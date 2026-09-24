import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../data/admin_service.dart';
import '../../data/device_codes.dart';
import '../../format/arabic_time.dart';
import '../../format/relative_time.dart';
import '../../model/follower_profile.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'accounts_table.dart';
import 'admin_ui.dart';
import 'device_problems.dart';
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

/// كلام مدى التذكير في كارت الجهاز.
String horizonWord(AdminAccount a) {
  if (a.seenAt == null) return 'مفيش خبر';
  return a.reminderHorizonOk ? 'مظبوط' : 'خلص — محتاج يفتح التطبيق';
}

/// اللوحة الجانبية: رأس غامق بالاسم والحالة والمعرّف، وأرقام الحساب،
/// وكارت الجهاز، ومين بيتابعه، وآخر التنبيهات. **مفيش أي اسم دوا هنا** —
/// الدوال في السحابة ما بترجّعوش أصلاً. ومفيش أفعال: اللوحة قراية.
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
    this.devices = const [],
    super.key,
  });

  final AdminAccount account;

  /// أجهزة المريض ده بأكوادها (0022) — كل تنزيلة صف.
  final List<AdminDevice> devices;
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
        Material(
          color: brandGround,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(F.s16, F.s16, F.s8, F.s14),
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
                const SizedBox(height: F.s8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: F.s8,
                  runSpacing: F.s6,
                  children: [
                    ToneBadge(tone, onWhite: true),
                    Text(
                      account.seenAt == null
                          ? 'الموبايل عمره ما بعت نبضة'
                          : 'آخر نبضة ${timeSince(now, account.seenAt!)}',
                      style: const TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careMicroSize,
                        color: F.onDarkMuted,
                      ),
                    ),
                    SelectableText(
                      account.patientUuid,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontFamily: F.monoFamily,
                        fontFamilyFallback: F.monoFallback,
                        fontSize: 11.5,
                        color: F.onDarkMuted,
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
              // أرقام الحساب — الحد بيتلوّن لما الرقم يستاهل نظرة.
              Row(
                children: [
                  _NumberCell('ما اتأكدتش ٢٤ س', account.missedDoses24h,
                      edge: account.missedDoses24h > 0 ? F.gold : null),
                  const SizedBox(width: F.s8),
                  _NumberCell('تنبيهات مفتوحة', account.pendingEscalations,
                      edge: account.pendingEscalations > 0 ? F.outOfRangeInk : null),
                  const SizedBox(width: F.s8),
                  _NumberCell('تنبيهات ٧ أيام', account.escalations7d),
                ],
              ),
              const SizedBox(height: F.s20),
              const AdminHead('الجهاز'),
              const SizedBox(height: F.careRowGap),
              _Facts([
                ('الجهاز', deviceWord(account), null),
                ('البطارية', batteryWord(account.batteryState),
                    account.batteryRestricted ? F.outOfRangeInk : null),
                ('مدى التذكير', horizonWord(account),
                    account.seenAt != null && !account.reminderHorizonOk ? F.outOfRangeInk : null),
                ('آخر مزامنة',
                    account.lastSyncAt == null ? 'مفيش' : timeSince(now, account.lastSyncAt!), null),
                ('اتسجّل', account.createdAt == null ? 'مش معروف' : arabicDate(account.createdAt!), null),
              ]),
              const SizedBox(height: F.s20),
              const AdminHead('مشاكل الجهاز'),
              const SizedBox(height: F.careRowGap),
              if (devices.isEmpty)
                const AdminPanel(text: 'ماوصلش من موبايله ولا نبضة.')
              else if (devices.every((d) => !deviceHasProblem(d, now)))
                const AdminPanel(text: 'مفيش مشكلة — النبضة وصلت من غير أكواد.')
              else
                Container(
                  key: const ValueKey('panel-device-problems'),
                  decoration: BoxDecoration(
                    color: F.cardGround,
                    border: Border.all(color: F.line),
                    borderRadius: BorderRadius.circular(F.careRadius),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, d) in DeviceProblemsList.problems(devices, now).indexed)
                        DeviceProblemRow(
                          device: d,
                          now: now,
                          showName: false,
                          last: i == DeviceProblemsList.problems(devices, now).length - 1,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: F.s20),
              const AdminHead('مين بيتابعه'),
              const SizedBox(height: F.careRowGap),
              if (loading && followers.isEmpty && failure == null)
                const _PanelSkeleton()
              else if (failure != null)
                AdminPanel(text: failure.message, action: 'حاول تاني', onAction: onRetry)
              else if (followers.isEmpty)
                const AdminPanel(text: 'مفيش حد مربوط بيه.')
              else
                for (final (i, follower) in followers.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: F.s8),
                    child: FadeSlideIn(
                      delay: staggerDelay(context, i),
                      child: _FollowerChip(follower: follower, body: _body, muted: _muted),
                    ),
                  ),
              const SizedBox(height: F.s12),
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

class _NumberCell extends StatelessWidget {
  const _NumberCell(this.label, this.value, {this.edge});

  final String label;
  final int value;
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s10),
        decoration: BoxDecoration(
          color: F.cardGround,
          border: Border.all(color: edge ?? Colors.transparent, width: 1.5),
          borderRadius: BorderRadius.circular(F.careRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              arabicNumber(value),
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: F.ink,
                height: 1.1,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.mutedDark),
            ),
          ],
        ),
      ),
    );
  }
}

/// كارت مفتاح/قيمة — المفتاح باهت والقيمة في النهاية.
class _Facts extends StatelessWidget {
  const _Facts(this.rows);

  final List<(String, String, Color?)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(color: F.line),
        borderRadius: BorderRadius.circular(F.careRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, (key, value, colour)) in rows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
              decoration: BoxDecoration(
                border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: F.lineSoft)),
              ),
              child: Row(
                children: [
                  Text(key,
                      style: TextStyle(
                          fontFamily: F.bodyFamily, fontSize: F.careTextSize, color: F.mutedDark)),
                  const Spacer(),
                  Text(value,
                      style: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careTextSize,
                        fontWeight: FontWeight.w600,
                        color: colour ?? F.ink,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// متابع: دايرة بأول حرف من اسمه، وجنبها الاسم والصلة والحالة — صف كامل.
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
      padding: const EdgeInsetsDirectional.fromSTEB(F.s8, F.s8, F.s14, F.s8),
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(color: F.line),
        borderRadius: BorderRadius.circular(F.careRadius),
      ),
      child: Row(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                if (!last) Expanded(child: Container(width: 2, color: F.line)),
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
                  Text(deliveryWord(alert.deliveryStatus), style: body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    alert.scheduledAt == null
                        ? 'من غير ميعاد'
                        : 'الجرعة ${arabicDate(alert.scheduledAt!)} ${arabicTime(alert.scheduledAt!)}',
                    style: muted,
                  ),
                  if (alert.createdAt != null) Text(timeSince(now, alert.createdAt!), style: muted),
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
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Shimmer(width: double.infinity, height: 52),
          SizedBox(height: F.s8),
          Shimmer(width: double.infinity, height: 52),
        ],
      );
}
