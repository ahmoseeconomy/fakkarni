import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/gemini_config.dart';
import '../../ai/prescription_reader.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
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

/// شاشة التصوير — نصيحة التصوير الأول، وبعدها كاميرا النظام.
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

  @override
  State<ScanPrescriptionScreen> createState() => _ScanPrescriptionScreenState();
}

/// [retake]: رجع من المراجعة بـ«صوّر تاني» — الشاشة دي نفسها هي الاختيار
/// بين الكاميرا والصور، فمش بنفتح الكاميرا لوحدنا.
enum _Phase { idle, reading, failed, retake }

class _ScanPrescriptionScreenState extends State<ScanPrescriptionScreen> {
  _Phase _phase = _Phase.idle;
  String? _error;

  Future<void> _capture(ImageSource source) async {
    final reader = widget.reader;
    if (reader == null || _phase == _Phase.reading) return;

    final image = await widget.pickImage(source);
    if (image == null || !mounted) return; // رجع من الكاميرا من غير صورة

    setState(() {
      _phase = _Phase.reading;
      _error = null;
    });

    try {
      final reading = await reader.read(image);
      if (!mounted) return;
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
          setState(() => _phase = _Phase.retake);
        case ReviewResult.confirmed:
          Navigator.of(context).pop();
        case null:
          break;
      }
    } on PrescriptionReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'حصلت مشكلة وإحنا بنقرا الروشتة — صوّر تاني.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReader = widget.reader != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'روشتة',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(F.gap),
          children: [
            if (!hasReader)
              const _Panel(
                text: GeminiConfig.missingKeyMessage,
                strong: true,
              )
            else ...[
              const Text(
                'حطها على سطح مستوي والنور يكون كويس',
                style: TextStyle(
                  fontSize: F.questionSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'خلّي الورقة كلها جوّه الصورة، ولو الخط مش باين قرّب شوية.',
                style: TextStyle(fontSize: F.minBodySize, color: F.muted, height: 1.6),
              ),
              const SizedBox(height: F.gap),
              const _Panel(
                text: 'الذكاء بيقترح وإنت اللي بتأكّد — مفيش دوا بيتضاف '
                    'من غير ما تدوس «تمام» بنفسك.',
              ),
              if (_phase == _Phase.reading) ...[
                const SizedBox(height: F.gap),
                const _Panel(text: 'بقرا الروشتة… ثواني.', busy: true),
              ],
              if (_phase == _Phase.failed && _error != null) ...[
                const SizedBox(height: F.gap),
                _Panel(text: _error!, strong: true),
              ],
              if (_phase == _Phase.retake) ...[
                const SizedBox(height: F.gap),
                const _Panel(
                  text: 'صوّرها تاني في نور أحسن، أو اختار صورة أوضح من الصور.',
                  strong: true,
                ),
              ],
              const SizedBox(height: F.gap),
              SizedBox(
                height: F.primaryButtonHeight,
                child: FilledButton(
                  onPressed: _phase == _Phase.reading
                      ? null
                      : () => _capture(ImageSource.camera),
                  child: Text(
                    _phase == _Phase.failed || _phase == _Phase.retake
                        ? 'صوّر تاني'
                        : 'صوّر الروشتة',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: F.minTapTarget,
                child: OutlinedButton(
                  onPressed: _phase == _Phase.reading
                      ? null
                      : () => _capture(ImageSource.gallery),
                  child: const Text(
                    'اختار من الصور',
                    style: TextStyle(fontSize: F.minTextSize + 1, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// عاجي للمعلومة، وبحدود للتنبيه — من غير أحمر، حتى للخطأ.
class _Panel extends StatelessWidget {
  const _Panel({required this.text, this.strong = false, this.busy = false});

  final String text;
  final bool strong;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: strong ? Colors.white : F.ivory,
          borderRadius: BorderRadius.circular(F.radius),
          border: strong ? Border.all(color: F.ink, width: 1.5) : null,
        ),
        child: Row(
          children: [
            if (busy) ...[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3, color: F.green),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
              ),
            ),
          ],
        ),
      );
}
