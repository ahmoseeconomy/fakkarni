import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/account/account_deletion.dart';
import '../../data/account/local_wipe.dart';

/// مين بيمسح — الكلام بيتغيّر، والسكّة واحدة.
enum DeletingAs { patient, follower, nurse }

/// اللي بيتمسح، سطر سطر — **بالظبط** اللي `delete_account_for_service`
/// (0033) بيمسحه، مش وصف عام. لو الدالة اتغيّرت، القايمة دي بتتغيّر معاها.
List<String> deletedLines(DeletingAs who, {String patientName = '', bool linked = true}) => switch (who) {
      // مش مربوط = مفيش حساب على السيرفر — الموبايل ده بس
      DeletingAs.patient when !linked => const [
          'أدويتك ومواعيدها، وكل الجرعات اللي اتسجّلت',
          'الملف الصحي: الروشتات والتحاليل والزيارات والأشعة',
          'قياسات السكر والضغط وباقي القياسات',
          'صور الأدوية وصور الورق',
          'بيانات الطوارئ وأسئلة الدكتور',
          'التذكيرات على الموبايل ده هتقف',
        ],
      DeletingAs.patient => const [
          'حسابك',
          'أدويتك ومواعيدها، وكل الجرعات اللي اتسجّلت',
          'الملف الصحي: الروشتات والتحاليل والزيارات والأشعة',
          'قياسات السكر والضغط وباقي القياسات',
          'صور الأدوية وصور الورق',
          'بيانات الطوارئ وأسئلة الدكتور',
          'ربط عيلتك وممرضك — مش هيشوفوا حاجة تاني',
          'كل ده على الموبايل ده كمان — والتذكيرات عليه هتقف',
        ],
      DeletingAs.follower || DeletingAs.nurse => [
          'حسابك',
          'ربطك بـ${_or(patientName, 'المريض')}، واسمك وتفضيلاتك',
          'التنبيهات اللي وصلتك عنه، وتوكن الإشعارات على الموبايل ده',
          if (who == DeletingAs.nurse) 'تذكيرات مواعيده على الموبايل ده',
        ],
    };

/// اللي **مش** بيتمسح — للمتابع والممرض بس: بيانات المريض بتاعته.
String? keptLine(DeletingAs who, {String patientName = ''}) => switch (who) {
      DeletingAs.patient => null,
      DeletingAs.follower => 'بيانات ${_or(patientName, 'المريض')} نفسها مش هتتمسح — دي بتاعته. '
          'وهيعرف إنك خرجت من الدايرة.',
      DeletingAs.nurse => 'بيانات ${_or(patientName, 'المريض')} نفسها مش هتتمسح — دي بتاعته. '
          'الجرعات اللي أكّدتها بتفضل متأكّدة من غير اسمك، وهيعرف إنك خرجت من الدايرة.',
    };

/// مش مربوط: مفيش سيرفر — الجملة بتقول المسح على الموبايل ده وبس.
const localOnlyLine = 'هنمسح كل بياناتك من على الموبايل ده.';

/// الاشتراك مش بتاعنا نلغيه — المتجر هو اللي بيحاسب.
const storeSubscriptionLine = 'لو عندك اشتراك، الغيه من إعدادات آبل أو جوجل — إحنا مش بنقدر نلغيه من هنا.';

const finalWarningLine = 'ده نهائي — مفيش رجوع، ومش هنقدر نرجّع أي حاجة بعد كده.';

String deletionOutcomeLine(DeletionOutcome outcome) => switch (outcome) {
      DeletionOutcome.deleted => 'اتمسح.',
      DeletionOutcome.offline => 'مفيش نت — ولا حاجة اتمسحت. جرّب تاني لما النت يرجع.',
      DeletionOutcome.failed => 'مقدرناش نكمّل المسح دلوقتي — حسابك لسه موجود. جرّب تاني بعد شوية.',
    };

String _or(String s, String fallback) => s.trim().isEmpty ? fallback : s.trim();

/// «امسح حسابي» — خطوتين: «ده اللي هيتمسح» ← «متأكد؟». المسح على السيرفر
/// الأول؛ **الموبايل ما بيتلمسش غير بعد ما السيرفر قال «اتمسح»**. بعدها
/// الموبايل بيرجع زي ما اتنزّل، والتطبيق بيرجع لشاشة البداية.
///
/// الزرار **حبر، مش أحمر** — الأحمر للطوارئ بس، حتى للحاجة اللي ما بترجعش.
/// و«رجوع» هو الأساسي في الخطوتين: المسح هو اللي محتاج قرار.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    required this.who,
    required this.linked,
    this.patientName = '',
    this.wipe,
    super.key,
  });

  final DeletingAs who;

  /// فيه حساب على السيرفر (جلسة + خدمة المسح)؟ لأ = **الموبايل ده بس**:
  /// نفس الخطوتين، ومفيش نداء شبكة خالص — `LocalWipe` وخلاص.
  final bool linked;
  final String patientName;

  /// للاختبارات — الافتراضي [LocalWipe] على خدمات التطبيق.
  final Future<void> Function(AppServices services)? wipe;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _confirming = false;
  bool _busy = false;
  DeletionOutcome? _outcome;

  Future<void> _delete() async {
    final services = AppScope.of(context);
    final remote = services.accountDeletion;
    if (_busy) return;
    setState(() {
      _busy = true;
      _outcome = null;
    });
    // مربوط: السيرفر الأول. مش مربوط: مفيش سيرفر يتسأل — الموبايل على طول.
    final outcome = widget.linked && remote != null ? await remote.deleteAccount() : DeletionOutcome.deleted;
    if (outcome == DeletionOutcome.deleted) {
      final wipe = widget.wipe ??
          (AppServices s) => LocalWipe(
                db: s.db,
                patientId: s.patientId,
                sink: s.scheduler.sink,
                auth: s.auth,
              ).run();
      await wipe(services);
      if (!mounted) return;
      // لشاشة البداية: الجذر بيقرا «مفيش مريض ومفيش جلسة»
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kept = keptLine(widget.who, patientName: widget.patientName);
    return Scaffold(
      appBar: AppBar(title: const Text('امسح حسابي')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
        children: [
          if (!widget.linked) ...[
            Text(localOnlyLine,
                key: const ValueKey('delete-local-only'),
                style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.5)),
            const SizedBox(height: F.s12),
          ],
          const FSectionHead('اللي هيتمسح'),
          const SizedBox(height: F.s8),
          for (final line in deletedLines(widget.who, patientName: widget.patientName, linked: widget.linked))
            Padding(
              padding: const EdgeInsets.only(bottom: F.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: F.s4),
                    child: Icon(Icons.remove_circle_outline, size: 22, color: F.ink),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(
                    child: Text(line,
                        style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
                  ),
                ],
              ),
            ),
          if (kept != null) ...[
            const SizedBox(height: F.s8),
            Text(kept,
                key: const ValueKey('delete-kept'),
                style: TextStyle(fontSize: F.minBodySize, color: F.mutedDark, height: 1.5)),
          ],
          const SizedBox(height: F.gap),
          if (widget.linked)
          Container(
            key: const ValueKey('delete-store-note'),
            padding: const EdgeInsets.all(F.s12),
            decoration: BoxDecoration(
              color: F.railGround,
              borderRadius: BorderRadius.circular(F.radiusCard),
            ),
            child: Text(storeSubscriptionLine,
                style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
          ),
          const SizedBox(height: F.gap),
          if (_outcome != null) ...[
            GoldNote(deletionOutcomeLine(_outcome!)),
            const SizedBox(height: F.s12),
          ],
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: F.s12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3, color: F.green),
                  ),
                  const SizedBox(width: F.s12),
                  Text('بنمسح…', style: TextStyle(fontSize: F.minBodySize, color: F.ink)),
                ],
              ),
            )
          else if (!_confirming) ...[
            FPrimaryButton(
              key: const ValueKey('delete-back'),
              label: 'لأ، رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: F.s12),
            FSecondaryButton(
              key: const ValueKey('delete-continue'),
              label: 'كمّل للمسح',
              onPressed: () => setState(() => _confirming = true),
            ),
          ] else ...[
            Text(
              'متأكد؟',
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.subtitleSize,
                fontWeight: FontWeight.w800,
                color: F.ink,
              ),
            ),
            const SizedBox(height: F.s8),
            Text(finalWarningLine,
                key: const ValueKey('delete-final-warning'),
                style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
            const SizedBox(height: F.gap),
            FPrimaryButton(
              key: const ValueKey('delete-back'),
              label: 'لأ، رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: F.s12),
            FSecondaryButton(
              key: const ValueKey('delete-confirm'),
              label: 'امسح حسابي نهائي',
              onPressed: _delete,
            ),
          ],
        ],
      ),
    );
  }
}
