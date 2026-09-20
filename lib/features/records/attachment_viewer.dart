import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/app_database.dart';

/// الصورة اللي السجل جه منها، ملء الشاشة.
///
/// الصورة **على الموبايل ده بس** — عمرها ما بتتبعت لحد (شوف التعليق عند
/// `attachments.save`). السجل اللي مالوش صورة ما بيفتحش الشاشة دي أصلاً:
/// مفيش إطار فاضي ولا صورة مكسورة.
class AttachmentViewerScreen extends StatelessWidget {
  const AttachmentViewerScreen({required this.file, required this.title, super.key});

  final File file;

  /// اسم السجل — عشان اللي فاتح يعرف بيبصّ على إيه.
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.onDark),
                  ),
                ),
                const SizedBox(width: F.s10),
                // **زرار بكلمة، مش علامة × لوحدها** (قاعدة الواجهة).
                SizedBox(
                  height: F.minTapTarget,
                  child: TextButton(
                    key: const ValueKey('attachment-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: F.onDark,
                      textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('اقفل'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              key: const ValueKey('attachment-zoom'),
              minScale: 1,
              maxScale: 5,
              child: Center(child: Image.file(file, fit: BoxFit.contain)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s12),
            child: Text(
              'قرّب بصوابعك عشان تكبّر',
              style: TextStyle(fontSize: F.minTextSize, color: F.onDarkMuted, height: 1.5),
            ),
          ),
        ],
      ),
    ),
  );
}

/// بيفتح صورة السجل لو ليه صورة — وبيرجّع false من غير ما يعمل حاجة لو
/// مالوش، أو لو الملف نفسه مش موجود (اتمسح من برّه، أو نسخة احتياطية رجعت
/// من غير الفولدر). **مفيش رسالة خطأ**: السجل من غير صورة سجل عادي.
Future<bool> openAttachment(BuildContext context, RecordRow record) async {
  final path = record.attachmentPath;
  if (path == null) return false;
  final file = await AppScope.of(context).attachments.fileFor(path);
  if (file == null || !context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AttachmentViewerScreen(file: file, title: record.title),
    ),
  );
  return true;
}
