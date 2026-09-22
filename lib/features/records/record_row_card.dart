import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/records_repository.dart';
import '../../data/services/checkup_service.dart';
import '../../domain/health/follow_display.dart';
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

  /// «دلوقتي» — بتتحقن من الاختبارات؛ بتحدد «بكرة» / «بعد بكرة».
  final DateTime? today;

  void _openCheckup(BuildContext context, int id) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CheckupScreen(recordId: id)),
      );

  Future<void> _options(BuildContext context) async {
    final record = this.record;
    final checkups = AppScope.of(context).checkups;
    final attachments = AppScope.of(context).attachments;
    final records = RecordsRepository(AppScope.of(context).db);
    final isFollow = record.checkupStage != null;
    await FSheet.show<void>(
      context,
      title: isFollow
          ? followDisplayTitle(CheckupService.kindOf(record), record.title)
          : record.title,
      children: [
        // **الاسم بتاع المتابعة بيتعدّل من هنا.** بيتولد من الورقة أول ما
        // تبدأ، والورقة ساعات مافيهاش اسم دكتور أصلاً — فالراجل بيفضل
        // قاعد قدّام «متابعة زيارة» مالهاش اسم يعرفها بيه. المسح مش
        // البديل: ده بيرمي المراحل والمواعيد معاها.
        if (isFollow)
          FSecondaryButton(
            key: const ValueKey('record-rename'),
            label: 'عدّل الاسم والدكتور',
            onPressed: () async {
              Navigator.of(context).pop();
              await _rename(context, records);
            },
          ),
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
            if (yes ?? false) {
              await checkups.delete(record.id, attachments: attachments);
              // المسح ممكن يشيل ميعاد — والتوفيق هو اللي بيلغي إشعاره.
              if (context.mounted) await AppScope.of(context).refreshAppointments();
            }
          },
        ),
      ],
    );
  }


  /// ورقة صغيرة بحقلين — الاسم والدكتور. اسم فاضي مش بيتحفظ.
  ///
  /// المتحكّمات عايشة جوه [_RenameBody] مش هنا: ورقة بتتقفل لسه ليها
  /// كادرات بتتبني، والتخلّص منها أول ما `show` ترجّع بيرمي
  /// «A TextEditingController was used after being disposed» — نفس
  /// العطل اللي ورقة ترويسة الروشتة دفعته في الجولة ١٦.
  Future<void> _rename(BuildContext context, RecordsRepository records) => FSheet.show<void>(
        context,
        title: 'اسم المتابعة',
        children: [
          _RenameBody(
            initialTitle: followDisplayTitle(CheckupService.kindOf(record), record.title),
            initialDoctor: record.doctor ?? '',
            onSave: (title, doctor) => records.rename(record.id, title: title, doctor: doctor),
          ),
        ],
      );

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
                    // المفتوحة بتتعرض بميعاد مرحلتها؛ اللي خلصت سجل عادي.
                    child: followIsOpen(CheckupService.kindOf(r), CheckupService.stageOf(r))
                        ? RecordSummary.follow(record: r, now: today ?? DateTime.now())
                        : RecordSummary(record: r),
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

class _RenameBody extends StatefulWidget {
  const _RenameBody({
    required this.initialTitle,
    required this.initialDoctor,
    required this.onSave,
  });

  final String initialTitle;
  final String initialDoctor;
  final Future<void> Function(String title, String doctor) onSave;

  @override
  State<_RenameBody> createState() => _RenameBodyState();
}

class _RenameBodyState extends State<_RenameBody> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _doctor = TextEditingController(text: widget.initialDoctor);

  @override
  void dispose() {
    _title.dispose();
    _doctor.dispose();
    super.dispose();
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
        filled: true,
        fillColor: F.fieldGround,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('rename-title'),
            controller: _title,
            textInputAction: TextInputAction.next,
            style: TextStyle(fontSize: F.minBodySize, color: F.ink),
            decoration: _deco('الاسم'),
          ),
          const SizedBox(height: F.s12),
          TextField(
            key: const ValueKey('rename-doctor'),
            controller: _doctor,
            textInputAction: TextInputAction.done,
            style: TextStyle(fontSize: F.minBodySize, color: F.ink),
            decoration: _deco('الدكتور'),
          ),
          const SizedBox(height: F.s12),
          FPrimaryButton(
            key: const ValueKey('rename-save'),
            label: 'احفظ',
            onPressed: () async {
              // اسم فاضي مش اسم: الزرار بيسكت بدل ما يحفظ فراغ.
              if (_title.text.trim().isEmpty) return;
              final nav = Navigator.of(context);
              await widget.onSave(_title.text, _doctor.text);
              if (mounted) nav.pop();
            },
          ),
        ],
      );
}
