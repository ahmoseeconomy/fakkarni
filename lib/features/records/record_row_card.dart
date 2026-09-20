import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import 'attachment_viewer.dart';
import 'checkup_screen.dart';
import 'health_file_screen.dart' show RecordSummary;

/// صف سجل واحد بكل اللي بيعمله: يفتح متابعته، أو صورته، أو «⋯ خيارات».
///
/// **مستخرج عشان يفضل واحد.** الصف ده كان عايش في «الملف الصحي» بس؛ ولما
/// الملف اتقسم لمداخل، القايمة اللي بيفتحها المدخل كانت هتبقى صفوف من
/// غير مسح ومن غير صورة — يعني تقسيم الشاشة كان هيشيل طريقين شغّالين في
/// صمت. دلوقتي الاتنين بيستعملوا نفس الصف.
class RecordRowCard extends StatelessWidget {
  const RecordRowCard({required this.record, this.today, super.key});

  final RecordRow record;
  final DateTime? today;

  void _openCheckup(BuildContext context, int id) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CheckupScreen(recordId: id)),
      );

  Future<void> _options(BuildContext context) async {
    final record = this.record;
    final checkups = AppScope.of(context).checkups;
    final attachments = AppScope.of(context).attachments;
    await FSheet.show<void>(
      context,
      title: record.title,
      children: [
        FSecondaryButton(
          key: const ValueKey('record-delete'),
          label: 'امسحه',
          onPressed: () async {
            Navigator.of(context).pop();
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: F.dialogGround,
                title: Text(
                  'تمسح «${record.title}»؟',
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.subtitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                // **الخسارة بتتقال قبل الدوسة، مش بعدها.** مفيش مهلة ٣٠
                // يوم دلوقتي، فالجملة الوحيدة اللي بتحمي حد هي دي — واللي
                // مالوش رجعة فيها (الصورة) بيتسمّى بالاسم.
                content: Text(
                  record.attachmentPath == null
                      ? 'هيتشال من الملف خالص، ومفيش رجوع.'
                      : 'هيتشال من الملف خالص، ومعاه الصورة المرفقة. مفيش رجوع.',
                  style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
                ),
                actions: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FPrimaryButton(
                        key: const ValueKey('record-delete-confirm'),
                        label: 'أيوه، امسحه',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      const SizedBox(height: F.s8),
                      FSecondaryButton(label: 'لأ، سيبه', onPressed: () => Navigator.of(context).pop(false)),
                    ],
                  ),
                ],
              ),
            );
            // عن طريق المتابعة: لو السجل ده عليه تذكيرات بتتلغي معاه
            if (yes ?? false) await checkups.delete(record.id, attachments: attachments);
          },
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s10),
      child: FCard(
        key: ValueKey('record-${r.id}'),
        child: Row(
          children: [
            Expanded(
              // المتابعة بتفتح شاشتها زي ما هي؛ غير كده السجل اللي ليه
              // صورة بيفتحها ملء الشاشة، واللي مالوش صورة ما بيتفتحش —
              // من غير إطار فاضي ولا زرار ما بيعملش حاجة.
              child: switch ((r.checkupStage, r.attachmentPath)) {
                (final int _, _) => InkWell(
                    key: ValueKey('checkup-open-${r.id}'),
                    onTap: () => _openCheckup(context, r.id),
                    child: RecordSummary(record: r),
                  ),
                (null, final String _) => InkWell(
                    key: ValueKey('record-photo-${r.id}'),
                    onTap: () => openAttachment(context, r),
                    child: RecordSummary(record: r),
                  ),
                _ => RecordSummary(record: r),
              },
            ),
            const SizedBox(width: F.s8),
            SizedBox(
              height: F.minTapTarget,
              child: TextButton(
                key: ValueKey('record-options-${r.id}'),
                onPressed: () => _options(context),
                style: TextButton.styleFrom(
                  foregroundColor: F.ink,
                  textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
                ),
                child: const Text('⋯ خيارات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
