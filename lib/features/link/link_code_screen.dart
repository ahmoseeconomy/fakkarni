import '../voice/help_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/code_boxes.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/care_circle_service.dart';
import '../../domain/billing/family_plan.dart';
import '../../domain/care/follower_role.dart';
import '../billing/feature_gate.dart';
import '../../data/sync/sync_service.dart';

/// شاشة الأب — «دائرة الرعاية» (المخطط 15): الكود اللي هيقوله لابنه.
///
/// الكود ضخم عن قصد — بيتقري عبر أوضة على مكالمة — ستة أرقام في سطر واحد
/// وبأرقام عربي زي باقي التطبيق. اللي بيتنسخ للحافظة أرقام غربية: دي اللي كيبورد الابن
/// هيكتبها، وشاشته بتقبل الاتنين. أول ما الشاشة تفتح بنرفع صف المريض
/// (uuid + الاسم — أول وآخر مزامنة في الجولة دي) وبعدها بنطلب الكود.
///
/// التصميم بيستعمل لينك دعوة (`fakrny.app/join/…`) — مش مبني: الكود
/// الستة أرقام شغّال ومتحقق على السحابة، واللينك محتاج دومين وdeep link
/// مش موجودين. بلوك الدعوة نفسه هو اللي اتاخد، والكود جوّاه.
class LinkCodeScreen extends StatefulWidget {
  const LinkCodeScreen({
    required this.care,
    required this.patientUuid,
    required this.patientName,
    this.sync,
    this.share,
    this.roles,
    super.key,
  });

  final CareCircleService care;

  /// الكود بدور (٠٠٢٣). null = كود «متابع» زي ما كان.
  final CareCircleAdmin? roles;

  /// بعد نجاح رفع صف المريض بنعلّم «اتربطنا» — من اللحظة دي المزامنة
  /// الصامتة مسموحة، وأول دفعة بترفع التاريخ كله.
  final SyncService? sync;
  final String patientUuid;
  final String patientName;

  /// «ابعته»: بيتنده بنص الرسالة. null = مفيش ورقة مشاركة (مفيش share_plus
  /// عن قصد قبل الديمو) — الزرار بينسخ وبيقول كده بالكلام.
  final Future<void> Function(String text)? share;

  @override
  State<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

class _LinkCodeScreenState extends State<LinkCodeScreen> {
  InviteCode? _invite;

  /// «متابع» افتراضياً — الأكواد والعلاقات القديمة كلها كده.
  FollowerRole _role = FollowerRole.follower;

  /// ٠٠٢٦: للممرض بس — اتسأل مرة لما اختار «ممرض / مرافق»، وبيتغيّر
  /// بعدين من «اللي بيتابعوك».
  bool _nurseCanEdit = false;
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    // ربط متابعين ميزة عائلية — البوابة قبل ما الكود يتعمل
    if (!await ensureFamilyFeature(context, AppFeature.circle) || !mounted) {
      if (mounted) setState(() => _error = 'اشتراك العيلة خلص — الربط محتاجه. تذكيرك شغّال زي ما هو.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      // صف المريض الأول — البوابة على السيرفر بتتأكد إن الكود لمريض يملكه
      await widget.care
          .upsertPatient(uuid: widget.patientUuid, name: widget.patientName);
      await widget.sync?.confirmLinked();
      // أول دفعة — الروتين والأدوية والتاريخ كله بيطلع دلوقتي في الخلفية
      unawaited(widget.sync?.push());
      final roles = widget.roles;
      final invite = roles == null
          ? await widget.care.createInvite(widget.patientUuid)
          : await roles.createRoleInvite(widget.patientUuid, _role,
              canEditMeds: _role == FollowerRole.nurse && _nurseCanEdit);
      if (mounted) setState(() => _invite = invite);
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نكمّل. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  /// اختيار الدور. «ممرض / مرافق» بيسأل **مرة**: يقدر يعدّل الأدوية
  /// والمواعيد؟ — والإجابة بتروح مع الكود للعلاقة. قفل الورقة من غير
  /// إجابة = الدور ما اتغيّرش.
  Future<void> _pickRole(FollowerRole role) async {
    if (_busy || _role == role) return;
    if (role == FollowerRole.nurse) {
      final canEdit = await FSheet.show<bool>(
        context,
        title: 'يقدر يعدّل الأدوية والمواعيد؟',
        children: [
          Text(
            'الممرض بيشوف يومك وأدويتك وبيأكّد الجرعة بدالك. لو قلت أيوه، يقدر كمان يضيف دوا أو يوقّفه أو يحط ميعاد — وكل ده بيوصل موبايلك.',
            style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
          ),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('nurse-edit-yes'),
            label: 'أيوه، يقدر',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: F.s8),
          FSecondaryButton(
            key: const ValueKey('nurse-edit-no'),
            label: 'لأ، يشوف ويأكّد بس',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      );
      if (canEdit == null || !mounted) return;
      _nurseCanEdit = canEdit;
    }
    setState(() => _role = role);
    await _refresh();
  }

  /// نص الرسالة اللي بتتبعت — الكود بأرقام غربية عشان يتكتب زي ما هو.
  static String message(InviteCode invite, [FollowerRole role = FollowerRole.follower]) =>
      'كود ربط فكّرني: ${invite.code} — اكتبه في التطبيق من «${role.door}». '
      'صالح لحد ${arabicTime(invite.expiresAt)}.';

  Future<void> _copy() async {
    final invite = _invite;
    if (invite == null) return;
    await Clipboard.setData(ClipboardData(text: invite.code));
    if (mounted) setState(() => _notice = 'اتنسخ — ابعته ${_role == FollowerRole.nurse ? 'للممرض' : 'لابنك أو بنتك'} في واتساب أو رسالة.');
  }

  Future<void> _share() async {
    final invite = _invite;
    if (invite == null) return;
    final share = widget.share;
    if (share != null) {
      await share(message(invite, _role));
      return;
    }
    // مفيش ورقة مشاركة — بننسخ الرسالة كاملة وبنقول كده، مش بنخلّي الزرار يعمل لا شيء
    await Clipboard.setData(ClipboardData(text: message(invite, _role)));
    if (mounted) setState(() => _notice = 'الرسالة اتنسخت — الصقها ${_role == FollowerRole.nurse ? 'للممرض' : 'لابنك أو بنتك'} في واتساب.');
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
          children: [
            HelpRow(
              id: 'help_invite_code',
              child: Text(
                'دائرة الرعاية',
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
            ),
            const SizedBox(height: F.s6),
            Text(
              'الكود ده بيربط موبايل حد من عيلتك أو ممرضك بموبايلك: يشوف أدويتك ومواعيدك، '
              'ولو جرعة اتنست يوصله تنبيه. قوله في التليفون أو ابعته.',
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.7),
            ),
            const SizedBox(height: F.gap),
            // ---------------------------------- الدور: متابع ولا ممرض؟
            // شريحتين كبار. تغيير الدور بيعمل كود جديد بدوره — الكود
            // بيشيل دوره معاه على السيرفر.
            if (widget.roles != null) ...[
              Text(
                'الكود ده لمين؟',
                style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
              ),
              const SizedBox(height: F.s8),
              Row(
                children: [
                  for (final role in FollowerRole.values) ...[
                    Expanded(
                      child: AnchorChip(
                        key: ValueKey('invite-role-${role.name}'),
                        label: role.inviteLabel,
                        selected: _role == role,
                        onTap: () => _pickRole(role),
                      ),
                    ),
                    if (role != FollowerRole.values.last) const SizedBox(width: F.s8),
                  ],
                ],
              ),
              const SizedBox(height: F.s6),
              Text(
                _role.explain,
                key: const ValueKey('invite-role-explain'),
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
              if (_role == FollowerRole.nurse) ...[
                const SizedBox(height: F.s4),
                const Align(alignment: AlignmentDirectional.centerEnd, child: HelpButton('help_nurse')),
                Text(
                  _nurseCanEdit
                      ? 'يقدر يعدّل الأدوية والمواعيد — كل تعديل بيوصل موبايلك ويتطبّق عليه.'
                      : 'مش هيعدّل الأدوية ولا المواعيد — بيشوف ويأكّد بس.',
                  key: const ValueKey('invite-nurse-edit-line'),
                  style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5),
                ),
                Text(
                  'تقدر تغيّر ده بعدين من «عيلتك أو ممرضك».',
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                ),
              ],
              const SizedBox(height: F.gap),
            ],
            if (_error != null) ...[
              FCard(
                tone: FCardTone.warm,
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
                ),
              ),
              const SizedBox(height: F.gap),
            ],
            // بلوك الدعوة — من التصميم، والكود مكان اللينك
            FCard(
              radius: F.radiusLarge,
              padding: const EdgeInsets.fromLTRB(F.gap, F.s22, F.gap, F.gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Kicker('كود الربط'),
                  const SizedBox(height: F.s8),
                  if (invite == null && _busy)
                    SizedBox(
                      height: 72,
                      child: Center(child: CircularProgressIndicator(color: F.green)),
                    )
                  else if (invite == null)
                    // فشل الطلب — مكان الكود فاضي بهدوء، والرسالة فوق بتقول ليه
                    Text(
                      '— — —',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 56, fontWeight: FontWeight.w700, color: F.line, height: 1.2),
                    )
                  else
                    // **نفس الست خانات اللي الابن أو الممرض بيكتب فيها** —
                    // اللي بيتقري هنا هو اللي بيتكتب هناك، رقم رقم ومن الشمال.
                    CodeBoxes(key: const ValueKey('invite-code'), value: invite.code, readOnly: true),
                  const SizedBox(height: F.s8),
                  Text(
                    invite == null
                        ? 'الكود صالح ١٥ دقيقة'
                        : 'صالح ١٥ دقيقة — لحد ${arabicTime(invite.expiresAt)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  ),
                  const SizedBox(height: F.gap),
                  Row(
                    children: [
                      Expanded(
                        child: _WordButton(
                          icon: Icons.copy_outlined,
                          label: 'انسخ الكود',
                          onPressed: invite == null ? null : _copy,
                        ),
                      ),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: _WordButton(
                          icon: Icons.send_outlined,
                          label: 'ابعته',
                          onPressed: invite == null ? null : _share,
                        ),
                      ),
                    ],
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: F.s10),
                    Row(
                      children: [
                        Icon(Icons.check, size: 22, color: F.greenOk),
                        const SizedBox(width: F.s6),
                        Expanded(
                          child: Text(
                            _notice!,
                            style: TextStyle(fontSize: F.minTextSize, color: F.greenOk, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: F.s12),
            Text(
              '${_role.holder} بيفتح التطبيق عنده ويختار «${_role.door}» ويكتبه. الكود بيشتغل مرة واحدة.',
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
            ),
            const SizedBox(height: F.gap),
            FPrimaryButton(label: _busy ? 'ثواني…' : 'كود جديد', onPressed: _busy ? null : _refresh),
            const SizedBox(height: F.s4),
            SizedBox(
              height: F.minTapTarget,
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(
                  'رجوع',
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.green),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// أيقونة **وكلمة** — ٥٦.
class _WordButton extends StatelessWidget {
  const _WordButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: F.ink,
            side: BorderSide(color: F.line, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: F.s8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
          ),
          icon: Icon(icon, size: 22),
          label: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
          ),
        ),
      );
}
