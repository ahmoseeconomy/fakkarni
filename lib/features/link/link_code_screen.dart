import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/care_circle_service.dart';
import '../../data/sync/sync_service.dart';

/// شاشة الأب — «دائرة الرعاية» (المخطط 15): الكود اللي هيقوله لابنه.
///
/// الكود ضخم عن قصد — بيتقري عبر أوضة على مكالمة — وبأرقام عربي زي باقي
/// التطبيق. اللي بيتنسخ للحافظة أرقام غربية: دي اللي كيبورد الابن
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
    super.key,
  });

  final CareCircleService care;

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
      final invite = await widget.care.createInvite(widget.patientUuid);
      if (mounted) setState(() => _invite = invite);
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نكمّل. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «١٢٣ ٤٥٦» — مجموعتين تلاتة تلاتة، أسهل في القراية والكتابة.
  static String grouped(String code) =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  /// نص الرسالة اللي بتتبعت — الكود بأرقام غربية عشان يتكتب زي ما هو.
  static String message(InviteCode invite) =>
      'كود ربط فكّرني: ${invite.code} — اكتبه في التطبيق من «عندي كود». '
      'صالح لحد ${arabicTime(invite.expiresAt)}.';

  Future<void> _copy() async {
    final invite = _invite;
    if (invite == null) return;
    await Clipboard.setData(ClipboardData(text: invite.code));
    if (mounted) setState(() => _notice = 'اتنسخ — ابعته لابنك في واتساب أو رسالة.');
  }

  Future<void> _share() async {
    final invite = _invite;
    if (invite == null) return;
    final share = widget.share;
    if (share != null) {
      await share(message(invite));
      return;
    }
    // مفيش ورقة مشاركة — بننسخ الرسالة كاملة وبنقول كده، مش بنخلّي الزرار يعمل لا شيء
    await Clipboard.setData(ClipboardData(text: message(invite)));
    if (mounted) setState(() => _notice = 'الرسالة اتنسخت — الصقها لابنك في واتساب.');
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
            const Text(
              'دائرة الرعاية',
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.screenTitleSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
              ),
            ),
            const SizedBox(height: F.s6),
            const Text(
              'الكود ده بيربط موبايل ابنك بموبايلك: يشوف أدويتك ومواعيدك، '
              'ولو جرعة اتنست يوصله تنبيه. قوله في التليفون أو ابعته.',
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.7),
            ),
            const SizedBox(height: F.gap),
            if (_error != null) ...[
              FCard(
                tone: FCardTone.warm,
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
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
                    const SizedBox(
                      height: 72,
                      child: Center(child: CircularProgressIndicator(color: F.green)),
                    )
                  else if (invite == null)
                    // فشل الطلب — مكان الكود فاضي بهدوء، والرسالة فوق بتقول ليه
                    const Text(
                      '· · ·',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 56, fontWeight: FontWeight.w700, color: F.line, height: 1.2),
                    )
                  else
                    Text(
                      grouped(arabicDigits(invite.code)),
                      textAlign: TextAlign.center,
                      // المجموعتين بيتقروا من اليمين زي أي رقم عربي في جملة عربي:
                      // «٤٨٣» الأول (على اليمين) ثم «٩٢٠» — وده اللي الابن بيكتبه: 483920.
                      style: const TextStyle(
                        // أكبر خط في التطبيق كله — بيتقري من بعيد
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: F.greenDeep,
                        fontFamily: F.monoFamily,
                        fontFamilyFallback: F.monoFallback,
                        // أرقام — مش حروف متصلة، فالتباعد هنا مسموح
                        letterSpacing: 4,
                        height: 1.2,
                      ),
                    ),
                  const SizedBox(height: F.s8),
                  Text(
                    invite == null
                        ? 'الكود صالح ١٥ دقيقة'
                        : 'صالح ١٥ دقيقة — لحد ${arabicTime(invite.expiresAt)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
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
                        const Icon(Icons.check, size: 22, color: F.greenOk),
                        const SizedBox(width: F.s6),
                        Expanded(
                          child: Text(
                            _notice!,
                            style: const TextStyle(fontSize: F.minTextSize, color: F.greenOk, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: F.s12),
            const Text(
              'ابنك بيفتح التطبيق عنده ويدوس «عندي كود» ويكتبه. الكود بيشتغل مرة واحدة.',
              style: TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.6),
            ),
            const SizedBox(height: F.gap),
            FPrimaryButton(label: _busy ? 'ثواني…' : 'كود جديد', onPressed: _busy ? null : _refresh),
            const SizedBox(height: F.s4),
            SizedBox(
              height: F.minTapTarget,
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text(
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
            side: const BorderSide(color: F.line, width: 1.5),
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
