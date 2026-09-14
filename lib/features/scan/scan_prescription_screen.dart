import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/gemini_config.dart';
import '../../ai/prescription_reader.dart';
import '../../ai/prescription_reading.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../medication/add_medication_screen.dart';
import 'debug_panel.dart';
import 'review_prescription_screen.dart';

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
    super.key,
  });

  final DayRoutine routine;

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
            today: widget.today,
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
    final saved = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(routine: widget.routine, today: widget.today),
      ),
    );
    if (saved == true && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasReader = widget.reader != null;

    return Scaffold(
      backgroundColor: F.inkDeep,
      appBar: AppBar(
        backgroundColor: F.inkDeep,
        foregroundColor: F.ivory,
        title: const Text(
          'روشتة',
          style: TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.subtitleSize,
            fontWeight: FontWeight.w700,
            color: F.ivory,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap),
          children: [
            if (!hasReader) ...[
              const _Panel(text: GeminiConfig.missingKeyMessage),
              const SizedBox(height: F.gap),
              SizedBox(
                height: F.minTapTarget,
                child: _SecondaryOnDark(label: 'أكتبها بإيدي', onPressed: _writeByHand),
              ),
            ] else ...[
              _Stage(
                image: _image,
                phase: _phase,
                lines: _lines,
                revealed: _revealed,
              ),
              const SizedBox(height: F.s14),
              const Text(
                'الذكاء بيقترح وإنت اللي بتأكّد — مفيش دوا بيتضاف '
                'من غير ما تدوس «تمام» بنفسك.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: F.minTextSize, color: F.ivoryWarm, height: 1.6),
              ),
              if (_phase == _Phase.failed && _error != null) ...[
                const SizedBox(height: F.gap),
                _Panel(text: _error!),
                if (kDebugMode && _cause != null) ...[
                  const SizedBox(height: F.s8),
                  DebugPanel(_cause!),
                ],
              ],
              if (_phase == _Phase.retake) ...[
                const SizedBox(height: F.gap),
                const _Panel(
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
                    foregroundColor: Colors.white,
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
                    child: _SecondaryOnDark(
                      label: 'اختار من الصور',
                      onPressed: _busy ? null : () => _capture(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(
                    child: _SecondaryOnDark(
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

/// الإطار بأركان: فاضي بنصيحة قبل التصوير، وبعده الصورة الحقيقية مغمّقة.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.image,
    required this.phase,
    required this.lines,
    required this.revealed,
  });

  final Uint8List? image;
  final _Phase phase;
  final List<ReadLine>? lines;
  final int revealed;

  @override
  Widget build(BuildContext context) {
    final lines = this.lines;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(F.radiusSection),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: F.greenDark),
            if (image != null) ...[
              Image.memory(
                image!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              // الصورة تحت، مغمّقة عشان الصناديق والنص يتقروا فوقها
              ColoredBox(color: F.inkDeep.withValues(alpha: 0.6)),
            ],
            const Padding(
              padding: EdgeInsets.all(F.s18),
              child: CustomPaint(painter: _CornerFrame()),
            ),
            if (image == null)
              const Padding(
                padding: EdgeInsets.all(F.s30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'حطها على سطح مستوي والنور يكون كويس',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: F.subtitleSize,
                        fontWeight: FontWeight.w700,
                        color: F.ivory,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: F.s10),
                    Text(
                      'خلّي الورقة كلها جوّه الإطار، ولو الخط مش باين قرّب شوية.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: F.minTextSize, color: F.ivoryWarm, height: 1.6),
                    ),
                  ],
                ),
              ),
            // السطور — بس بعد ما الرد يوصل، وبعدد اللي رجع فعلاً
            if (lines != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(F.s30, F.s30, F.s30, 84),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, line) in lines.indexed) ...[
                        _LineBox(label: _labelFor(line), read: i < revealed),
                        const SizedBox(height: F.s12),
                      ],
                    ],
                  ),
                ),
              ),
            if (phase == _Phase.reading || phase == _Phase.revealing)
              Positioned(
                left: 0,
                right: 0,
                bottom: F.s26,
                child: Center(
                  child: _ReadingBadge(
                    text: phase == _Phase.reading || lines == null
                        ? 'بيقرا الروشتة…'
                        : 'بيقرا · ${arabicNumber(revealed)}/${arabicNumber(lines.length)} سطور',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// «Concor 5mg — الفطار» — من اللي Gemini رجّعه، مش من تخمين.
  static String _labelFor(ReadLine line) {
    final name = line.name.value ?? 'سطر مش واضح';
    final rule = line.timings.value == null ? null : line.timingLabel;
    return rule == null || rule.isEmpty ? name : '$name — $rule';
  }
}

/// سطر واحد: متقطع شفاف قبل ما يتعلّم، ممتلئ عاجي بعده.
class _LineBox extends StatelessWidget {
  const _LineBox({required this.label, required this.read});

  final String label;
  final bool read;

  /// rgba(255,255,255,.28) و rgba(234,231,219,.18) — من README.
  static const _unreadStroke = Color(0x47FFFFFF);
  static final _readFill = F.ivoryWarm.withValues(alpha: 0.18);

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: F.minTapTarget - F.s8),
      padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s8),
      alignment: AlignmentDirectional.centerStart,
      decoration: read
          ? BoxDecoration(
              color: _readFill,
              borderRadius: BorderRadius.circular(F.radiusChip),
              border: Border.all(color: F.ivoryWarm, width: 1.5),
            )
          : null,
      child: Text(
        label,
        textDirection: nameDirection(label),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: F.minTextSize,
          fontWeight: FontWeight.w600,
          color: read ? F.ivory : F.ivory.withValues(alpha: 0.5),
          fontFamily: F.monoFamily,
          fontFamilyFallback: F.monoFallback,
        ),
      ),
    );
    if (read) return content;
    return CustomPaint(
      painter: const _DashedRect(color: _unreadStroke, radius: F.radiusChip),
      child: content,
    );
  }
}

class _ReadingBadge extends StatelessWidget {
  const _ReadingBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s8),
        decoration: BoxDecoration(
          color: F.inkDeep.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(F.radiusTile),
          border: Border.all(color: F.ivory.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PulseDot(),
            const SizedBox(width: F.s8),
            Text(
              text,
              style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ivory),
            ),
          ],
        ),
      );
}

/// نقطة نابضة — ساكنة مع «تقليل الحركة».
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(color: F.ivory, shape: BoxShape.circle),
        ),
      );
}

/// أركان الإطار — أربع زوايا عاجي، من غير مستطيل كامل.
class _CornerFrame extends CustomPainter {
  const _CornerFrame();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = F.ivory
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arm = 30.0;
    final w = size.width, h = size.height;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (w, 0.0, -1.0, 1.0),
      (0.0, h, 1.0, -1.0),
      (w, h, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(x, y), Offset(x + arm * dx, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + arm * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerFrame old) => false;
}

class _DashedRect extends CustomPainter {
  const _DashedRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
        Radius.circular(radius),
      ));
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRect old) => old.color != color || old.radius != radius;
}

/// ثانوي على الغامق — محدّد عاجي، ٥٦.
class _SecondaryOnDark extends StatelessWidget {
  const _SecondaryOnDark({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: F.ivory,
            disabledForegroundColor: F.mutedLight,
            side: BorderSide(color: F.ivory.withValues(alpha: 0.4), width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: F.s8),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

/// معلومة أو غلطة على الغامق — من غير أحمر، حتى للخطأ.
class _Panel extends StatelessWidget {
  const _Panel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.s14),
        decoration: BoxDecoration(
          color: F.ivoryWarm,
          borderRadius: BorderRadius.circular(F.radiusCard),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
      );
}
