import '../voice/help_button.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/gemini_config.dart';
import '../../ai/package_reader.dart';
import '../../ai/prescription_reader.dart' show PrescriptionReadException;
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../scan/debug_panel.dart';
import '../scan/scan_prescription_screen.dart' show PickImage, pickWithSystemCamera;
import '../scan/scan_stage.dart';
import 'add_medication_screen.dart';

/// **«صوّر العلبة أو الشريط»** — نفس مسار الروشتة ببرومبت العلب.
///
/// اللي بيخرج من هنا **مسوّدة فورم**، مش دوا: الشاشة اللي بعدها هي
/// [AddMedicationScreen] نفسها بالظبط، متعبّية، والحفظ محتاج دوسة إنسان
/// (القاعدة ٤).
///
/// **والعلبة ما بتقولش مواعيد.** الجرعة والمواعيد من الدكتور، فالحقول دي
/// بتفضل فاضية والراجل بيملاها زي الإدخال اليدوي بالظبط.
class ScanPackageScreen extends StatefulWidget {
  const ScanPackageScreen({
    required this.routine,
    required this.reader,
    this.pickImage = pickWithSystemCamera,
    this.today,
    super.key,
  });

  final DayRoutine routine;
  final MedicinePackageReader? reader;
  final PickImage pickImage;
  final DateTime? today;

  @override
  State<ScanPackageScreen> createState() => _ScanPackageScreenState();
}

enum _Phase { idle, reading, failed, retake }

class _ScanPackageScreenState extends State<ScanPackageScreen> {
  _Phase _phase = _Phase.idle;
  Uint8List? _image;
  String? _error;
  String? _cause;

  bool get _busy => _phase == _Phase.reading;

  Future<void> _capture(ImageSource source) async {
    final reader = widget.reader;
    if (reader == null || _busy) return;
    final image = await widget.pickImage(source);
    if (image == null || !mounted) return;

    setState(() {
      _phase = _Phase.reading;
      _image = image;
      _error = null;
      _cause = null;
    });

    try {
      final reading = await reader.read(image);
      if (!mounted) return;

      // **ولا حاجة اتقرت بوضوح = صوّر تاني، مش تخمين.** العلبة اللي
      // مالهاش اسم واضح مالهاش فايدة كمسوّدة: حقل مكتوب فيه نص اسم
      // أوحش من حقل فاضي، لأنه بيتقري كأنه اتقرا.
      if (reading.nothingClear) {
        setState(() {
          _phase = _Phase.retake;
          _image = null;
        });
        return;
      }

      setState(() => _phase = _Phase.idle);
      final saved = await Navigator.of(context).push<Object?>(
        MaterialPageRoute(
          builder: (_) => AddMedicationScreen(
            routine: widget.routine,
            today: widget.today,
            initialName: reading.nameField,
            packageReading: reading,
            // «استخدم صورة العلبة» — نفس الصورة اللي اتقرت، بتتصغّر وقت الحفظ
            packageImage: _image,
          ),
        ),
      );
      if (!mounted) return;
      if (saved != null) Navigator.of(context).pop(true);
    } on PrescriptionReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.message;
        _cause = e.cause?.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'حصلت مشكلة وإحنا بنقرا العلبة — صوّر تاني.';
        _cause = e.toString();
      });
    }
  }

  void _byHand() => Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AddMedicationScreen(routine: widget.routine, today: widget.today),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: F.inkDeep,
        appBar: AppBar(
          backgroundColor: F.inkDeep,
          foregroundColor: F.onDark,
          actions: const [Padding(padding: EdgeInsetsDirectional.only(end: F.s8), child: HelpButton('help_scan', onDark: true))],
          title: const Text(
            'علبة الدوا',
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.subtitleSize,
              fontWeight: FontWeight.w700,
              color: F.onDark,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap),
            children: [
              if (widget.reader == null) ...[
                const PanelOnDark(text: GeminiConfig.missingKeyMessage),
                const SizedBox(height: F.gap),
                SecondaryOnDark(label: 'أكتبه بإيدي', onPressed: _byHand),
              ] else ...[
                ScanStage(
                  image: _image,
                  busy: _busy,
                  // مفيش كشف سطر سطر هنا: العلبة حاجة واحدة مش قايمة.
                  labels: null,
                  revealed: 0,
                  adviceTitle: 'وشّ العلبة جوّه الإطار',
                  adviceBody: 'الاسم والتركيز لازم يبانوا. لو شريط، صوّر الضهر '
                      'اللي مكتوب عليه الاسم.',
                  waitingText: 'بيقرا العلبة…',
                ),
                const SizedBox(height: F.s14),
                const Text(
                  // القاعدة ٤ والقاعدة ٦ في سطر واحد قدّام الراجل.
                  'بيقرا اسم الدوا وتركيزه بس — المواعيد والجرعة من الدكتور، '
                  'وإنت اللي بتكتبها. ومفيش حاجة بتتحفظ من غير ما تدوس «احفظ».',
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
                  const PanelOnDark(key: ValueKey('package-retake'), text: unreadablePackage),
                ],
                const SizedBox(height: F.gap),
                SizedBox(
                  height: F.primaryButtonHeight,
                  child: FilledButton(
                    key: const ValueKey('package-capture'),
                    onPressed: _busy ? null : () => _capture(ImageSource.camera),
                    style: FilledButton.styleFrom(
                      backgroundColor: F.green,
                      foregroundColor: F.onDark,
                      disabledBackgroundColor: F.greenDark,
                      disabledForegroundColor: F.mutedLight,
                      textStyle: const TextStyle(
                          fontSize: F.minBodySize, fontWeight: FontWeight.w700),
                    ),
                    child: Text(_phase == _Phase.failed || _phase == _Phase.retake
                        ? 'صوّر تاني'
                        : 'صوّر العلبة'),
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
                    Expanded(
                      child: SecondaryOnDark(
                          label: 'أكتبه بإيدي', onPressed: _busy ? null : _byHand),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

/// **الجملة الوحيدة اللي بتتقال لما القراية مش واضحة** — مصدر واحد،
/// والشاشة والاختبار بيقروا منه.
const String unreadablePackage =
    'مقدرناش نقرا ده بوضوح — صوّر تاني أو اكتبه بإيدك.';
