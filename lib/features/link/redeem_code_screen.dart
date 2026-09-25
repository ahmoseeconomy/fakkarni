import 'package:flutter/material.dart';


import '../../core/theme/tokens.dart';
import '../../core/widgets/code_boxes.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/care_circle_service.dart';
import '../../data/care/caregiver_remote.dart';
import '../care/caregiver_screen.dart';

/// شاشة الابن: يكتب الكود اللي والده قاله في التليفون (المخطط 15).
///
/// الحقل بيقبل الأرقام العربي والغربي — كيبورد الآيفون العربي بيكتب
/// ٠-٩، والسيرفر عايز 0-9 — فبنطبّع قبل الإرسال.
class RedeemCodeScreen extends StatefulWidget {
  const RedeemCodeScreen({required this.care, this.caregiver, this.onLinked, this.door, super.key});

  /// ٠٠٢٦: الباب اللي الكود اتكتب فيه. null = أي كود (الطريق القديم من
  /// شاشة الدخول). كود من النوع التاني بيترفض على السيرفر من غير ما يتحرق.
  final FollowerRole? door;

  final CareCircleService care;

  /// بعد الربط الناجح: «افتح المتابعة» بيوصّل للنافذة على طول.
  final CaregiverRemote? caregiver;

  /// D4 طريق الابن من شاشة البداية: بيتندَه بعد الربط (طلب إذن الإشعارات —
  /// من غيره تنبيه التصعيد ما بيظهرش على أندرويد ١٣+)، و«افتح المتابعة»
  /// بترجع `true` للجذر بدل ما تفتح شاشة فوق. null = الطريق القديم.
  final Future<void> Function()? onLinked;

  @override
  State<RedeemCodeScreen> createState() => _RedeemCodeScreenState();
}

class _RedeemCodeScreenState extends State<RedeemCodeScreen> {
  /// اللي اتكتب في الخانات — أرقام غربية دايماً.
  String _entered = '';
  String? _error;
  String? _linkedName;
  bool _busy = false;


  String get _digits => _entered;
  bool get _complete => _digits.length == 6;

  Future<void> _redeem() async {
    if (_busy || !_complete) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final care = widget.care;
      final door = widget.door;
      final name = door != null && care is RoleRedeem
          ? await (care as RoleRedeem).redeemInviteAt(_digits, door)
          : await care.redeemInvite(_digits);
      if (mounted) setState(() => _linkedName = name);
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نكمّل. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // برّه الـtry عن قصد: الربط نجح خلاص — طلب إذن فشل ما يقلبهوش لـ«مقدرناش».
    if (_linkedName != null) {
      try {
        await widget.onLinked?.call();
      } catch (error) {
        debugPrint('Care: طلب إذن الإشعارات بعد الربط فشل: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = _linkedName;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
          children: linked != null
              ? [
                  const SizedBox(height: F.gap),
                  Icon(Icons.check_circle_outline, size: 56, color: F.green),
                  const SizedBox(height: 12),
                  Text(
                    'اتربطت بـ$linked',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: F.questionSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.onLinked != null
                        ? 'هتقدر تشوف أدويته ومواعيده. عشان نبلّغك لو نسي جرعة، '
                            'الموبايل هيسألك تسمح بالإشعارات.'
                        : 'هتقدر تشوف أدويته ومواعيده — والتنبيهات جاية في الخطوة الجاية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: F.minBodySize, color: F.mutedDark, height: 1.6),
                  ),
                  const SizedBox(height: F.gap),
                  if (widget.onLinked != null)
                    FPrimaryButton(
                      label: 'افتح المتابعة',
                      onPressed: () => Navigator.of(context).pop(true),
                    )
                  else if (widget.caregiver != null) ...[
                    FPrimaryButton(
                      label: 'افتح المتابعة',
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => CaregiverScreen(remote: widget.caregiver!),
                        ),
                      ),
                    ),
                    const SizedBox(height: F.s4),
                  ],
                  if (widget.onLinked == null)
                  SizedBox(
                    height: widget.caregiver != null
                        ? F.minTapTarget
                        : F.primaryButtonHeight,
                    child: widget.caregiver != null
                        ? TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: Text(
                              'تمام',
                              style: TextStyle(
                                fontSize: F.minBodySize,
                                fontWeight: FontWeight.w600,
                                color: F.green,
                              ),
                            ),
                          )
                        : FPrimaryButton(
                            label: 'تمام',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                  ),
                ]
              : [
                  Text(
                    'عندي كود',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  const SizedBox(height: F.s6),
                  Text(
                    widget.door == FollowerRole.nurse
                        ? 'اكتب الكود اللي المريض أو أهله إدوهولك — ٦ أرقام. بعدها هتشوف يومه وأدويته.'
                        : 'اكتب الكود اللي والدك أو قريبك قالهولك — ٦ أرقام. بعدها هتشوف أدويته ومواعيده.',
                    style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.7),
                  ),
                  const SizedBox(height: F.gap),
                  // ست خانات — الإرسال لوحده مع الرقم السادس (والزرار فاضل لو
                  // حاجة وقفته: شبكة، أو كود غلط اتصلّح)
                  CodeBoxes(
                    key: const ValueKey('redeem-code'),
                    enabled: !_busy,
                    onChanged: (digits) => setState(() => _entered = digits),
                    onCompleted: (_) => _redeem(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    // ذهبي مش أحمر: محتاج انتباهك، مش غلطة تتلام عليها
                    // نص غامق جنب حافة ذهبي — الذهبي كنص على العاجي ≈ ١.٩:١، ما بيتقراش
                    GoldNote(_error!),
                  ],
                  const SizedBox(height: F.gap),
                  FPrimaryButton(
                    label: _busy ? 'ثواني…' : 'اربط',
                    onPressed: _busy || !_complete ? null : _redeem,
                  ),
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
