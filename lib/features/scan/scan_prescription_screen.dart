import '../voice/help_button.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/gemini_config.dart';
import '../../ai/prescription_reader.dart';
import '../../ai/prescription_reading.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../medication/add_medication_screen.dart';
import '../medication/medication_draft.dart';
import 'debug_panel.dart';
import 'review_prescription_screen.dart';
import 'scan_stage.dart';

/// بيجيب صورة من الكاميرا أو المعرض. مفصول عشان الشاشة تتختبر من غير جهاز.
typedef PickImage = Future<Uint8List?> Function(ImageSource source);

/// الافتراضي: كاميرا النظام نفسها.
///
/// مفيش viewfinder بتاعنا عن قصد: المستخدم عنده ٧٢ سنة وعارف كاميرا موبايله،
/// وعمره ما شاف الإطار بتاعنا. الكاميرا بتاعة النظام بتظبط الفوكس والنور
/// وبتدّيه «صوّر تاني». الإطار المخصّص يتبني بس لو التجربة الحقيقية قالت
/// إن التصوير هو اللي بيبوّظ القراءة.
///
/// الدقة عالية عن قصد: الخط اليدوي أول حاجة بتموت مع التصغير. الأرقام دي
/// تتظبط على روشتة حقيقية مكتوبة بالإيد، مش على شاشة.
Future<Uint8List?> pickWithSystemCamera(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2560,
    maxHeight: 2560,
    imageQuality: 92,
  );
  return file?.readAsBytes();
}

/// «تصوير الروشتة» (المخطط 05).
///
/// **أمانة الكشف — مش زينة:** Gemini بيرجّع القراءة كلها مرة واحدة، فمفيش
/// «قراءة سطر سطر» حقيقية نعرضها وإحنا مستنيين. عشان كده:
/// - **أثناء الانتظار:** الإطار والصورة اللي اتصوّرت، وسطر «بيقرا الروشتة…»
///   بنقطة نابضة. **ولا سطر متعلّم** — التطبيق لسه ما قراش حاجة.
/// - **بعد ما الرد يوصل:** الكشف بيمشي على السطور **اللي رجعت فعلاً**، بعدد
///   السطور الحقيقي وأسمائها، وبعدها على طول لشاشة المراجعة.
/// الصناديق متراصّة مش متحطّة على مكانها في الورقة: Gemini مش بيرجّع
/// إحداثيات، والرسم على مكان متخيَّل كان هيبقى نفس الكذبة.
///
/// القاعدة ٤ زي ما هي: ولا سطر بيتحفظ هنا. المراجعة ودوسة الإنسان بعدها.
class ScanPrescriptionScreen extends StatefulWidget {
  const ScanPrescriptionScreen({
    required this.routine,
    required this.reader,
    this.pickImage = pickWithSystemCamera,
    this.today,
    this.onSaved,
    super.key,
  });

  final DayRoutine routine;

  /// سجل الروشتة اللي اتكتب بعد التأكيد — «تابع زيارة» بتبدأ منه.
  final void Function(int recordId)? onSaved;

  /// null = المفتاح مش متظبط. الشاشة بتقولها بوضوح ومش بتفتح الكاميرا.
  final PrescriptionReader? reader;
  final PickImage pickImage;
  final DateTime? today;

  /// كل سطر حقيقي بياخد الوقت ده عشان يتعلّم، وبعد آخر سطر مهلة قصيرة.
  static const Duration revealPerLine = Duration(milliseconds: 450);
  static const Duration revealHold = Duration(milliseconds: 350);

  @override
  State<ScanPrescriptionScreen> createState() => _ScanPrescriptionScreenState();
}

/// [reading]: مستنيين Gemini — مفيش سطور. [revealing]: الرد وصل، بنعلّم
/// السطور اللي رجعت. [retake]: رجع من المراجعة بـ«صوّر تاني» — الشاشة دي
/// نفسها هي الاختيار بين الكاميرا والصور، فمش بنفتح الكاميرا لوحدنا.
enum _Phase { idle, reading, revealing, failed, retake }

class _ScanPrescriptionScreenState extends State<ScanPrescriptionScreen> {
  _Phase _phase = _Phase.idle;
  String? _error;

  /// السبب التقني — بيتعرض في نسخة التطوير بس، عشان نشوف الرد على الجهاز
  /// نفسه بدل ما نخمّن. في الإصدار المريض بيشوف الجملة العربية وبس.
  String? _cause;

  /// الصورة اللي اتصوّرت فعلاً — بتتعرض جوّه الإطار.
  Uint8List? _image;

  /// السطور اللي رجعت من Gemini — null لحد ما الرد يوصل.
  List<ReadLine>? _lines;
  int _revealed = 0;

  bool get _busy => _phase == _Phase.reading || _phase == _Phase.revealing;

  Future<void> _capture(ImageSource source) async {
    final reader = widget.reader;
    if (reader == null || _busy) return;

    final image = await widget.pickImage(source);
    if (image == null || !mounted) return; // رجع من الكاميرا من غير صورة

    setState(() {
      _phase = _Phase.reading;
      _image = image;
      _lines = null;
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
          _lines = reading.lines;
        });
        for (var i = 0; i < reading.lines.length; i++) {
          await Future<void>.delayed(ScanPrescriptionScreen.revealPerLine);
          if (!mounted) return;
          setState(() => _revealed = i + 1);
        }
        await Future<void>.delayed(ScanPrescriptionScreen.revealHold);
        if (!mounted) return;
      }

      setState(() => _phase = _Phase.idle);
      final result = await Navigator.of(context).push<ReviewResult>(
        MaterialPageRoute(
          builder: (_) => ReviewPrescriptionScreen(
            reading: reading,
            routine: widget.routine,
            // اللي الكاميرا دته (٢٥٦٠ من المنتقي) — مش المصغّرة بتاعة الموديل
            image: image,
            today: widget.today,
            onSaved: widget.onSaved,
          ),
        ),
      );
      if (!mounted) return;
      switch (result) {
        case ReviewResult.retake:
          // القراءة الوحشة علاجها صورة أحسن — من الكاميرا أو من الصور.
          setState(() {
            _phase = _Phase.retake;
            _image = null;
            _lines = null;
          });
        case ReviewResult.confirmed:
          Navigator.of(context).pop();
        case null:
          setState(() {
            _image = null;
            _lines = null;
          });
      }
    } on PrescriptionReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.message;
        _cause = e.cause?.toString();
        _lines = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'حصلت مشكلة وإحنا بنقرا الروشتة — صوّر تاني.';
        _cause = e.toString();
        _lines = null;
      });
    }
  }

  /// «أكتبها بإيدي» — إدخال إنسان، فمفيش حاجة تتأكّد بعدها.
  Future<void> _writeByHand() async {
    final navigator = Navigator.of(context);
    // بترجّع جرعات اللي اتحفظ — null يعني رجع من غير حفظ.
    final saved = await navigator.push<MedicationDraft>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(routine: widget.routine, today: widget.today),
      ),
    );
    if (saved != null && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasReader = widget.reader != null;

    return Scaffold(
      backgroundColor: F.inkDeep,
      appBar: AppBar(
        backgroundColor: F.inkDeep,
        foregroundColor: F.onDark,
        actions: const [Padding(padding: EdgeInsetsDirectional.only(end: F.s8), child: HelpButton('help_scan', onDark: true))],
        title: const Text(
          'روشتة',
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
            if (!hasReader) ...[
              const PanelOnDark(text: GeminiConfig.missingKeyMessage),
              const SizedBox(height: F.gap),
              SizedBox(
                height: F.minTapTarget,
                child: SecondaryOnDark(label: 'أكتبها بإيدي', onPressed: _writeByHand),
              ),
            ] else ...[
              ScanStage(
                image: _image,
                busy: _busy,
                labels: _lines == null ? null : [for (final l in _lines!) _labelFor(l)],
                revealed: _revealed,
                adviceTitle: 'حطها على سطح مستوي والنور يكون كويس',
                adviceBody: 'خلّي الورقة كلها جوّه الإطار، ولو الخط مش باين قرّب شوية.',
                waitingText: 'بيقرا الروشتة…',
              ),
              const SizedBox(height: F.s14),
              const Text(
                'الذكاء بيقترح وإنت اللي بتأكّد — مفيش دوا بيتضاف '
                'من غير ما تدوس «تمام» بنفسك.',
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
                const PanelOnDark(
                  text: 'صوّرها تاني في نور أحسن، أو اختار صورة أوضح من الصور.',
                ),
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
                  child: Text(
                    _phase == _Phase.failed || _phase == _Phase.retake
                        ? 'صوّر تاني'
                        : 'صوّر الروشتة',
                  ),
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
                      label: 'أكتبها بإيدي',
                      onPressed: _busy ? null : _writeByHand,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// «Concor 5mg — الفطار» — من اللي Gemini رجّعه، مش من تخمين.
String _labelFor(ReadLine line) {
  final name = line.name.value ?? 'سطر مش واضح';
  final rule = line.timings.value == null ? null : line.timingLabel;
  return rule == null || rule.isEmpty ? name : '$name — $rule';
}
