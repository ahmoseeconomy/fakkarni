import '../voice/help_button.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../records/attachment_viewer.dart';

/// **صورة الدوا جنب اسمه** — العين بتعرف الحباية قبل ما تقرا اسمها.
///
/// مفيش صورة، أو الملف راح، أو اتفكّ غلط → [fallback] (الأيقونة اللي كانت
/// موجودة). **عمرها ما بتعرض صورة مكسورة.** الدوسة بتفتحها ملء الشاشة.
class MedPhotoThumb extends StatelessWidget {
  const MedPhotoThumb({
    required this.path,
    required this.name,
    required this.fallback,
    this.size = 48,
    super.key,
  });

  final String? path;
  final String name;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final scope = AppScope.maybeOf(context);
    if (path == null || scope == null) return fallback;
    return FutureBuilder<File?>(
      future: scope.medPhotoStore.fileFor(path),
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return fallback;
        return Semantics(
          button: true,
          label: 'صورة $name — افتحها كبيرة',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('med-photo-$path'),
            borderRadius: BorderRadius.circular(F.radiusChip),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AttachmentViewerScreen(file: file, title: name),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(F.radiusChip),
              child: Image.file(
                file,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                // ملف بايظ → الأيقونة، مش مربع مكسور
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// بيجيب صورة من الكاميرا أو الصور — متحقنة للاختبارات. الصورة بتتصغّر
/// بعدين لـ٨٠٠ ويتشال الـEXIF (`prepareMedPhoto`)؛ هنا بنطلب دقة معقولة
/// عشان الذاكرة وبس.
Future<Uint8List?> Function(ImageSource source) pickMedPhoto = (source) async {
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
  return file?.readAsBytes();
};

/// خانة «صورة الدوا (اختياري)» في الفورم.
///
/// [preview] الصورة الحالية (بايتس قبل الحفظ، أو الملف المحفوظ)، و[boxImage]
/// صورة العلبة اللي اتقرت لو الدوا جاي من «صوّر العلبة».
class MedPhotoSlot extends StatelessWidget {
  const MedPhotoSlot({
    required this.onPicked,
    required this.onRemove,
    this.previewBytes,
    this.previewFile,
    this.boxImage,
    super.key,
  });

  final Uint8List? previewBytes;
  final File? previewFile;
  final Uint8List? boxImage;
  final ValueChanged<Uint8List> onPicked;
  final VoidCallback onRemove;

  Future<void> _pick(ImageSource source) async {
    final bytes = await pickMedPhoto(source);
    if (bytes != null) onPicked(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final has = previewBytes != null || previewFile != null;
    return Column(
      key: const ValueKey('med-photo-slot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HelpRow(
          id: 'help_photo',
          child: Text('صورة الدوا (اختياري)',
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
        ),
        const SizedBox(height: F.s4),
        Text('صورة الحباية أو العلبة — بتساعدك تعرف الدوا من شكله.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
        const SizedBox(height: F.s8),
        if (has) ...[
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(F.radiusChip),
                child: previewBytes != null
                    ? Image.memory(previewBytes!, key: const ValueKey('med-photo-preview'), width: 88, height: 88,
                        fit: BoxFit.cover, errorBuilder: (_, _, _) => const _NoPreview())
                    : Image.file(previewFile!, key: const ValueKey('med-photo-preview'), width: 88, height: 88,
                        fit: BoxFit.cover, errorBuilder: (_, _, _) => const _NoPreview()),
              ),
              const SizedBox(width: F.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FSecondaryButton(
                      key: const ValueKey('med-photo-change'),
                      label: 'غيّرها',
                      onPressed: () => _pick(ImageSource.camera),
                    ),
                    const SizedBox(height: F.s8),
                    FSecondaryButton(key: const ValueKey('med-photo-remove'), label: 'شيلها', onPressed: onRemove),
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          if (boxImage case final box?) ...[
            FSecondaryButton(
              key: const ValueKey('med-photo-use-box'),
              label: 'استخدم صورة العلبة',
              onPressed: () => onPicked(box),
            ),
            const SizedBox(height: F.s8),
          ],
          Row(
            children: [
              Expanded(
                child: FSecondaryButton(
                  key: const ValueKey('med-photo-camera'),
                  label: 'صوّر',
                  onPressed: () => _pick(ImageSource.camera),
                ),
              ),
              const SizedBox(width: F.s8),
              Expanded(
                child: FSecondaryButton(
                  key: const ValueKey('med-photo-gallery'),
                  label: 'من الصور',
                  onPressed: () => _pick(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NoPreview extends StatelessWidget {
  const _NoPreview();
  @override
  Widget build(BuildContext context) => Container(
        width: 88,
        height: 88,
        color: F.railGround,
        child: Icon(Icons.medication_outlined, color: F.mutedDark, size: 36),
      );
}
