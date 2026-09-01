import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../data/care/care_circle_service.dart';

/// شاشة الابن: يكتب الكود اللي والده قاله في التليفون.
class RedeemCodeScreen extends StatefulWidget {
  const RedeemCodeScreen({required this.care, super.key});

  final CareCircleService care;

  @override
  State<RedeemCodeScreen> createState() => _RedeemCodeScreenState();
}

class _RedeemCodeScreenState extends State<RedeemCodeScreen> {
  final _code = TextEditingController();
  String? _error;
  String? _linkedName;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.trim().length == 6;

  Future<void> _redeem() async {
    if (_busy || !_complete) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = await widget.care.redeemInvite(_code.text.trim());
      if (mounted) setState(() => _linkedName = name);
    } on CareCircleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'مقدرناش نكمّل. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = _linkedName;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'عندي كود',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(F.gap),
          children: linked != null
              ? [
                  const SizedBox(height: F.gap),
                  const Icon(Icons.check_circle_outline, size: 56, color: F.green),
                  const SizedBox(height: 12),
                  Text(
                    'اتربطت بـ$linked',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: F.questionSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'هتقدر تشوف أدويته ومواعيده — والتنبيهات جاية في الخطوة الجاية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: F.minBodySize, color: F.muted, height: 1.6),
                  ),
                  const SizedBox(height: F.gap),
                  SizedBox(
                    height: F.primaryButtonHeight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('تمام'),
                    ),
                  ),
                ]
              : [
                  const Text(
                    'اكتب الكود اللي والدك قالهولك — ٦ أرقام.',
                    style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.7),
                  ),
                  const SizedBox(height: F.gap),
                  TextField(
                    controller: _code,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: F.bigTimeSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      fontFamily: F.monoFamily,
                      fontFamilyFallback: F.monoFallback,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      hintStyle: TextStyle(
                        fontSize: F.bigTimeSize,
                        letterSpacing: 8,
                        color: F.line,
                        fontFamily: F.monoFamily,
                        fontFamilyFallback: F.monoFallback,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(F.radius),
                        borderSide: const BorderSide(color: F.line),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    // ذهبي مش أحمر: محتاج انتباهك، مش غلطة تتلام عليها
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w600,
                        color: F.gold,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: F.gap),
                  SizedBox(
                    height: F.primaryButtonHeight,
                    child: FilledButton(
                      onPressed: _busy || !_complete ? null : _redeem,
                      child: Text(_busy ? 'ثواني…' : 'اربط'),
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
