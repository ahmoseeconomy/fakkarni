import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../data/care/care_circle_service.dart';
import '../../data/sync/sync_service.dart';

/// شاشة الأب: الكود اللي هيقوله لابنه في التليفون.
///
/// الكود ضخم عن قصد — بيتقري عبر أوضة على مكالمة. وأرقام غربية عن قصد:
/// دي اللي كيبورد الابن هيكتبها. أول ما الشاشة تفتح بنرفع صف المريض
/// (uuid + الاسم — أول وآخر مزامنة في الجولة دي) وبعدها بنطلب الكود.
class LinkCodeScreen extends StatefulWidget {
  const LinkCodeScreen({
    required this.care,
    required this.patientUuid,
    required this.patientName,
    this.sync,
    super.key,
  });

  final CareCircleService care;

  /// بعد نجاح رفع صف المريض بنعلّم «اتربطنا» — من اللحظة دي المزامنة
  /// الصامتة مسموحة، وأول دفعة بترفع التاريخ كله.
  final SyncService? sync;
  final String patientUuid;
  final String patientName;

  @override
  State<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

class _LinkCodeScreenState extends State<LinkCodeScreen> {
  InviteCode? _invite;
  String? _error;
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

  /// «123 456» — مجموعتين تلاتة تلاتة، أسهل في القراية والكتابة.
  static String grouped(String code) =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  @override
  Widget build(BuildContext context) {
    final invite = _invite;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'كود الربط',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(F.gap),
          children: [
            const Text(
              'قول الكود ده لابنك في التليفون، وهو يكتبه عنده في التطبيق.',
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.7),
            ),
            const SizedBox(height: F.gap),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: F.ivory,
                  borderRadius: BorderRadius.circular(F.radius),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
                ),
              ),
              const SizedBox(height: F.gap),
            ],
            Container(
              padding: const EdgeInsets.symmetric(vertical: F.gap + 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(F.radius + 4),
                border: Border.all(color: F.line),
              ),
              child: Column(
                children: [
                  if (invite == null && _busy)
                    const SizedBox(
                      height: 64,
                      child: Center(
                        child: CircularProgressIndicator(color: F.green),
                      ),
                    )
                  else if (invite == null)
                    // فشل الطلب — مكان الكود فاضي بهدوء، والرسالة فوق بتقول ليه
                    const Text(
                      '· · ·',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: F.line,
                        height: 1.2,
                      ),
                    )
                  else
                    Text(
                      grouped(invite.code),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        // أكبر خط في التطبيق كله — بيتقري من بعيد
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: F.greenDeep,
                        fontFamily: F.monoFamily,
                        fontFamilyFallback: F.monoFallback,
                        letterSpacing: 4,
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'الكود صالح ١٥ دقيقة',
                    style: TextStyle(fontSize: F.minTextSize, color: F.muted),
                  ),
                  if (invite != null)
                    Text(
                      'لحد ${arabicTime(invite.expiresAt)}',
                      style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: F.gap),
            SizedBox(
              height: F.primaryButtonHeight,
              child: FilledButton(
                onPressed: _busy ? null : _refresh,
                child: Text(_busy ? 'ثواني…' : 'كود جديد'),
              ),
            ),
            const SizedBox(height: 4),
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
