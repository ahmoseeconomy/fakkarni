import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/lab_reader.dart';
import '../../app/app_scope.dart';
import '../../ai/lab_reading.dart';
import '../../ai/prescription_reader.dart' show PrescriptionReadException;
import '../../core/theme/tokens.dart';
import '../../data/db/tables.dart';
import '../records/manual_entry_screen.dart';
import '../scan/debug_panel.dart';
import '../scan/review_prescription_screen.dart' show ReviewResult;
import '../scan/scan_prescription_screen.dart' show PickImage, pickWithSystemCamera;
import '../scan/ai_read_gate.dart';
import '../scan/scan_stage.dart';
import 'lab_report_screen.dart';
import 'usual_words.dart';

/// «تصوير تقرير تحليل» (المخطط ٧) — نفس مسار الروشتة ببرومبت تاني.
///
/// **نفس قاعدة الأمانة بتاعة D2.3 بالحرف:** وإحنا مستنيين Gemini مفيش ولا
/// سطر متعلّم — «بيقرا التقرير…» بس. بعد ما الرد يوصل، الكشف بيمشي على
/// السطور اللي رجعت فعلاً. صفحة واحدة لكل تصوير (المتعدد في المؤجَّل).
class ScanLabScreen extends StatefulWidget {
  const ScanLabScreen({required this.reader, this.pickImage = pickWithSystemCamera, this.today, super.key});

  final LabReportReader? reader;
  final PickImage pickImage;
  final DateTime? today;

  static const Duration revealPerLine = Duration(milliseconds: 450);
  static const Duration revealHold = Duration(milliseconds: 350);

  @override
  State<ScanLabScreen> createState() => _ScanLabScreenState();
}

enum _Phase { idle, reading, revealing, failed, retake }

class _ScanLabScreenState extends State<ScanLabScreen> {
  _Phase _phase = _Phase.idle;
  Uint8List? _image;
  List<String>? _labels;
  int _revealed = 0;
  String? _error;

  /// القارئ ما لقاش جلسة، أو السحابة ردّت ٤٠١ — [AiReadGate] بيقفل الكاميرا.
  bool _needsSignIn = false;
  String? _cause;

  bool get _busy => _phase == _Phase.reading || _phase == _Phase.revealing;

  static String _labelFor(LabLine l) {
    final name = l.test.value ?? 'سطر مش واضح';
    final v = l.value.value;
    return v == null ? name : '$name — ${arabicDecimal(v)}${l.unit.value == null ? '' : ' ${l.unit.value}'}';
  }

  Future<void> _capture(ImageSource source) async {
    final reader = widget.reader;
    if (reader == null || _busy) return;
    final image = await widget.pickImage(source);
    if (image == null || !mounted) return;

    setState(() {
      _phase = _Phase.reading;
      _image = image;
      _labels = null;
      _revealed = 0;
      _error = null;
      _cause = null;
    });

    try {
      final reading = await reader.read(image);
      if (!mounted) return;
      // الرد وصل — دلوقتي بس فيه سطور حقيقية نعلّمها.
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (reading.lines.isNotEmpty && !reduceMotion) {
        setState(() {
          _phase = _Phase.revealing;
          _labels = [for (final l in reading.lines) _labelFor(l)];
        });
        for (var i = 0; i < reading.lines.length; i++) {
          await Future<void>.delayed(ScanLabScreen.revealPerLine);
          if (!mounted) return;
          setState(() => _revealed = i + 1);
        }
        await Future<void>.delayed(ScanLabScreen.revealHold);
        if (!mounted) return;
      }
      setState(() => _phase = _Phase.idle);
      final result = await Navigator.of(context).push<ReviewResult>(
        MaterialPageRoute(builder: (_) => LabReportScreen(reading: reading, image: image, today: widget.today)),
      );
      if (!mounted) return;
      switch (result) {
        case ReviewResult.retake:
          setState(() {
            _phase = _Phase.retake;
            _image = null;
            _labels = null;
          });
        case ReviewResult.confirmed:
          Navigator.of(context).pop(true);
        case null:
          setState(() {
            _image = null;
            _labels = null;
          });
      }
    } on PrescriptionReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _needsSignIn = e.needsSignIn;
        _error = e.message;
        _cause = e.cause?.toString();
        _labels = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'حصلت مشكلة وإحنا بنقرا التقرير — صوّر تاني.';
        _cause = e.toString();
        _labels = null;
      });
    }
  }

  void _byHand() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ManualEntryScreen(kind: RecordKind.lab, today: widget.today)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: F.inkDeep,
      appBar: AppBar(
        backgroundColor: F.inkDeep,
        foregroundColor: F.onDark,
        title: const Text(
          'تقرير تحليل',
          style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, fontWeight: FontWeight.w700, color: F.onDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap),
          children: [
            AiReadGate(
              hasReader: widget.reader != null,
              auth: AppScope.maybeOf(context)?.auth,
              needsSignIn: _needsSignIn,
              signInLine: 'سجّل دخول عشان نقرا التقرير',
              byHandLabel: 'أكتبه بإيدي',
              onByHand: _byHand,
              onSignInClosed: () {
                if (mounted) setState(() { _needsSignIn = false; _phase = _Phase.idle; _error = null; });
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ScanStage(
                image: _image,
                busy: _busy,
                labels: _labels,
                revealed: _revealed,
                adviceTitle: 'صفحة النتايج كلها جوّه الإطار',
                adviceBody: 'الأرقام والوحدات لازم تبان. صفحة واحدة في المرة.',
                waitingText: 'بيقرا التقرير…',
              ),
              const SizedBox(height: F.s14),
              const Text(
                'بيقرا الأرقام بس — ومفيش حاجة بتتحفظ من غير ما تدوس «تمام» بنفسك.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: F.minTextSize, color: F.onDarkMuted, height: 1.6),
              ),
              if (_phase == _Phase.failed && _error != null) ...[
                const SizedBox(height: F.gap),
                PanelOnDark(text: _error!),
                if (kDebugMode && _cause != null) ...[
                  const SizedBox(height: F.s8),
                  DebugPanel(_cause!),
                ],
              ],
              if (_phase == _Phase.retake) ...[
                const SizedBox(height: F.gap),
                const PanelOnDark(text: 'صوّره تاني في نور أحسن، أو اختار صورة أوضح من الصور.'),
              ],
              const SizedBox(height: F.gap),
              SizedBox(
                height: F.primaryButtonHeight,
                child: FilledButton(
                  onPressed: _busy ? null : () => _capture(ImageSource.camera),
                  style: FilledButton.styleFrom(
                    backgroundColor: F.green,
                    foregroundColor: F.onDark,
                    disabledBackgroundColor: F.greenDark,
                    disabledForegroundColor: F.mutedLight,
                    textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
                  ),
                  child: Text(_phase == _Phase.failed || _phase == _Phase.retake ? 'صوّر تاني' : 'صوّر التقرير'),
                ),
              ),
              const SizedBox(height: F.s10),
              Row(
                children: [
                  Expanded(
                    child: SecondaryOnDark(
                      label: 'اختار من الصور',
                      onPressed: _busy ? null : () => _capture(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(child: SecondaryOnDark(label: 'أكتبه بإيدي', onPressed: _busy ? null : _byHand)),
                ],
              ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
