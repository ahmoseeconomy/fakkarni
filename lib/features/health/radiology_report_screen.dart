import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ai/lab_reading.dart';
import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/tables.dart' show RecordKind;
import '../../data/repositories/records_repository.dart';
import '../scan/review_prescription_screen.dart' show ReviewResult;

/// «قراءة تقرير الأشعة» (المرحلة ٦ — المالك 2A/3A) — مراجعة قبل الحفظ،
/// زي كل قراية (القاعدة ٤): ولا صف بيتكتب غير بدوسة «تمام، احفظه».
///
/// **الخلاصة نقل مش تفكير**: اللي معروض هو المطبوع على الورقة بالحرف
/// (الموديل متقيّد في الـsystem instruction)، ومش واضح = مفيش خلاصة —
/// **والورقة عمرها ما بتضيع**: «تمام» شغّالة دايماً، فتقرير ما اتقراش
/// بيتحفظ بصورته كورقة أشعة (kind = imaging + attachment_path + notes —
/// مفيش جدول ولا عمود جديد، بقياس 1d).
class RadiologyReportScreen extends StatefulWidget {
  const RadiologyReportScreen({required this.reading, this.image, this.today, super.key});

  final LabReading reading;
  final Uint8List? image;

  /// للاختبارات.
  final DateTime? today;

  @override
  State<RadiologyReportScreen> createState() => _RadiologyReportScreenState();
}

class _RadiologyReportScreenState extends State<RadiologyReportScreen> {
  // اللي القارئ قاله بثقة — وبعدها اللي الإنسان كتبه (كلامه بيكسب).
  late String _exam =
      widget.reading.examName.needsReview ? '' : (widget.reading.examName.value ?? '').trim();
  late String _conclusion = widget.reading.conclusionText ?? '';
  bool _busy = false;

  DateTime get _today {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  Future<void> _edit() async {
    final result = await showDialog<({String exam, String conclusion})>(
      context: context,
      builder: (_) => _EditDialog(exam: _exam, conclusion: _conclusion),
    );
    if (result == null || !mounted) return;
    setState(() {
      _exam = result.exam;
      _conclusion = result.conclusion;
    });
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final reading = widget.reading;
    final today = widget.today ?? DateTime.now();

    // الصورة: لو التخزين فشل الورقة بتتحفظ من غيرها — السجل هو الوعد.
    String? path;
    final image = widget.image;
    if (image != null) {
      try {
        path = await services.attachments.save(image);
      } catch (error) {
        debugPrint('صورة تقرير الأشعة ما اتحفظتش: $error');
      }
    }

    final exam = _exam.trim();
    final conclusion = _conclusion.trim();
    await RecordsRepository(services.db).add(
      patientId: services.patientId,
      kind: RecordKind.imaging,
      title: exam.isEmpty ? 'تقرير أشعة' : exam,
      happenedAt: reading.date.value != null && !reading.date.needsReview
          ? reading.date.value!
          : DateTime(today.year, today.month, today.day),
      place: reading.lab.needsReview ? null : reading.lab.value,
      // الخلاصة **بالحرف** — اللي القارئ نقله أو اللي الإنسان كتبه، ولا
      // كلمة بتتعدّل في السكّة دي (طفرة بتوقّع على أي لمسة هنا).
      notes: conclusion.isEmpty ? null : conclusion,
      attachmentPath: path,
    );
    if (mounted) navigator.pop(ReviewResult.confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final reading = widget.reading;
    final meta = [
      if (!reading.lab.needsReview && reading.lab.value != null) reading.lab.value!,
      if (!reading.date.needsReview && reading.date.value != null) arabicDate(reading.date.value!),
    ].join(' — ');
    final conclusion = _conclusion.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('قراءة تقرير الأشعة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          Text(
            'الورقة زي ما اتقرت',
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.screenTitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          if (meta.isNotEmpty)
            Text(meta, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
          const SizedBox(height: F.s8),
          Text(
            'بننقل اللي مكتوب في التقرير زي ما هو — من غير أي كلمة من عندنا.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          // تاريخ ناقص أو مش واضح = بيتسجّل بتاريخ النهارده — بنقولها
          // بالذهبي **قبل** الدوسة، زي شاشة المعمل بالحرف.
          if (reading.date.value == null || reading.date.needsReview) ...[
            const SizedBox(height: F.s8),
            GoldNote(
              'التقرير مش كاتب تاريخ واضح — هيتسجّل بتاريخ النهارده '
              '(${arabicDate(_today)}).',
              key: const ValueKey('date-fallback'),
            ),
          ],
          const SizedBox(height: F.gap),
          FCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الفحص',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                ),
                const SizedBox(height: F.s4),
                Text(
                  _exam.trim().isEmpty ? 'مش مكتوب اسم فحص واضح — هتتحفظ «تقرير أشعة»' : _exam,
                  key: const ValueKey('radiology-exam'),
                  textDirection: _directionOf(_exam),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    fontFamily: F.bodyFamily,
                    fontFamilyFallback: F.fontFallback,
                  ),
                ),
                const SizedBox(height: F.s10),
                Text(
                  'الخلاصة زي ما هي مكتوبة في التقرير',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                ),
                const SizedBox(height: F.s4),
                if (conclusion.isEmpty)
                  Text(
                    'مفيش خلاصة اتقرت من الصورة — الورقة هتتحفظ بصورتها، '
                    'وتقدر تكتبها بإيدك من «عدّل».',
                    key: const ValueKey('radiology-no-conclusion'),
                    style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
                  )
                else
                  Text(
                    conclusion,
                    key: const ValueKey('radiology-conclusion'),
                    textDirection: _directionOf(conclusion),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: F.minBodySize,
                      color: F.ink,
                      height: 1.6,
                      fontFamily: F.bodyFamily,
                      fontFamilyFallback: F.fontFallback,
                    ),
                  ),
                const SizedBox(height: F.s10),
                FSecondaryButton(label: 'عدّل', onPressed: _edit),
              ],
            ),
          ),
          const SizedBox(height: F.gap),
          // نفس الوزن بالظبط — مليانين، نفس المقاس (القاعدة ٤).
          Row(
            children: [
              Expanded(
                child: _Equal(
                  label: 'صوّر تاني',
                  fill: F.ink,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(ReviewResult.retake),
                ),
              ),
              const SizedBox(width: F.s10),
              Expanded(
                child: _Equal(
                  label: 'تمام، احفظه',
                  fill: F.green,
                  // دايماً مفتوحة: الورقة عمرها ما بتضيع — من غير خلاصة
                  // بتتحفظ بصورتها.
                  onPressed: _busy ? null : _confirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// خلاصة لاتينية بتترسم LTR عشان ترتيبها ما يتقلبش جوّه صفحة RTL —
  /// والعربي عربي. أول حرف قوي هو اللي بيحكم، زي `MedName`.
  static TextDirection _directionOf(String text) =>
      RegExp(r'[؀-ۿ]').hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;
}

/// «عدّل» — الدايالوج صاحب الـcontrollers فبيتقفلوا معاه بعد ما حركة
/// القفل تخلص (درس جولة ١٦).
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.exam, required this.conclusion});

  final String exam, conclusion;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _exam = TextEditingController(text: widget.exam);
  late final _conclusion = TextEditingController(text: widget.conclusion);

  @override
  void dispose() {
    _exam.dispose();
    _conclusion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: const Text(
          'عدّل الورقة دي',
          style: TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textInputAction: TextInputAction.next,
                key: const ValueKey('edit-exam'),
                controller: _exam,
                style: const TextStyle(fontSize: F.minBodySize),
                decoration: const InputDecoration(labelText: 'اسم الفحص زي ما هو في الورقة'),
              ),
              TextField(
                // متعدد السطور بياخد newline — وإلا زرار السطر الجديد بيبقى «تم»
                textInputAction: TextInputAction.newline,
                key: const ValueKey('edit-conclusion'),
                controller: _conclusion,
                maxLines: 6,
                minLines: 3,
                style: const TextStyle(fontSize: F.minBodySize),
                decoration: const InputDecoration(labelText: 'الخلاصة زي ما هي مكتوبة'),
              ),
            ],
          ),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('edit-save'),
                label: 'تمام',
                onPressed: () => Navigator.of(context)
                    .pop((exam: _exam.text.trim(), conclusion: _conclusion.text.trim())),
              ),
            ],
          ),
        ],
      );
}

class _Equal extends StatelessWidget {
  const _Equal({required this.label, required this.fill, required this.onPressed});

  final String label;
  final Color fill;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.primaryButtonHeight,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: fill,
            foregroundColor: F.onFill(fill),
            disabledBackgroundColor: F.railGround,
            disabledForegroundColor: F.mutedDark,
            textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
          ),
          child: Text(label, maxLines: 1),
        ),
      );
}
