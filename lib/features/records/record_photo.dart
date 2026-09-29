import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/files/paper_share.dart';
import '../../data/repositories/records_repository.dart';
import '../scan/scan_prescription_screen.dart' show pickWithSystemCamera;

/// صورة على سجل زيارة أو تحليل أو أشعة — **بتتحفظ وبس، ما بتتقراش**
/// (قرار المالك، ٢٩ سبتمبر ٢٠٢٦). روشتة الزيارة مش بتضيف أدوية: ده شغل
/// «صوّر روشتة». وصورة واحدة لكل سجل؛ التانية بتاخد مكانها بعد سؤال.
///
/// الصورة بتفضل على الموبايل (نفس [RecordsRepository.add]) — ولو المريض
/// فاتح «شارك صور الورق مع الممرض» بتترفع زي أي ورقة.

/// بيجيب البايتات — متبدّل في الاختبارات (نفس فكرة `dialNumber`).
Future<Uint8List?> Function(ImageSource source) pickRecordPhotoBytes = pickWithSystemCamera;

/// اسم الصورة على السجل: الزيارة روشتتها، والتحليل والأشعة تقريرهم.
/// null = النوع ده مالوش صورة بتتضاف من هنا.
String? recordPhotoWord(RecordKind kind) => switch (kind) {
      RecordKind.visit => 'صورة الروشتة',
      RecordKind.lab || RecordKind.imaging => 'صورة التقرير',
      RecordKind.prescription || RecordKind.booking => null,
    };

/// «صوّرها دلوقتي» أو «اختار من الصور» — والصورة. null = رجع من غير صورة.
Future<Uint8List?> askRecordPhoto(BuildContext context, {required String title}) async {
  final source = await FSheet.show<ImageSource>(
    context,
    title: title,
    children: [
      FPrimaryButton(
        key: const ValueKey('record-photo-camera'),
        label: 'صوّرها دلوقتي',
        onPressed: () => Navigator.of(context).pop(ImageSource.camera),
      ),
      const SizedBox(height: F.s8),
      FSecondaryButton(
        key: const ValueKey('record-photo-gallery'),
        label: 'اختار من الصور',
        onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
      ),
    ],
  );
  if (source == null) return null;
  return pickRecordPhotoBytes(source);
}

/// «ضيف صورة الروشتة / التقرير» على سجل موجود. لو عليه صورة، بيسأل الأول
/// — القديمة بتتمسح ومفيش رجوع، فده بيتقال قبل الدوسة. بيرجّع true لو اتحفظت.
Future<bool> attachRecordPhoto(BuildContext context, RecordRow record) async {
  final word = recordPhotoWord(record.kind);
  if (word == null) return false;
  if (record.attachmentPath != null) {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: Text(
          'تغيّر $word؟',
          style: TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.subtitleSize,
            fontWeight: FontWeight.w700,
            color: F.ink,
          ),
        ),
        content: Text(
          'الصورة الجديدة هتاخد مكان القديمة، والقديمة هتتمسح. مفيش رجوع.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('record-photo-replace'),
                label: 'أيوه، غيّرها',
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: F.s8),
              FSecondaryButton(label: 'لأ، سيبها', onPressed: () => Navigator.of(context).pop(false)),
            ],
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !context.mounted) return false;
  }
  final bytes = await askRecordPhoto(context, title: word);
  if (bytes == null || !context.mounted) return false;
  final services = AppScope.of(context);
  final path = await services.attachments.save(bytes);
  final uuid = await RecordsRepository(services.db)
      .setAttachment(record.id, path, attachments: services.attachments);
  if (uuid == null) {
    // السجل اتمسح في النص — الصورة ما يفضلش ليها صاحب
    await services.attachments.delete(path);
    return false;
  }
  await PaperShareService.forgetUpload(uuid);
  final papers = services.papers;
  if (papers != null) await papers.sync(patientId: services.patientId);
  return true;
}
