import '../../../domain/escalation/dose_moment.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/med_name.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/care/follower_role.dart';
import '../../../data/dose_state.dart';
import '../../../data/repositories/dose_event_repository.dart';
import '../../../domain/medication/medicine_form.dart';
import '../../../domain/wording/patient_words.dart';
import '../../medication/med_photo.dart';

/// **«باقي اليوم»** (إعادة التصميم، ٤ أكتوبر ٢٠٢٦) — كانت «جدول النهاردة».
///
/// صف لكل دقيقة بترتيب الوقت: **لكل دوا اسمه جنب رسمته** (المالك، ٦ أكتوبر
/// ٢٠٢٦ — دواءين شراب في نفس الدقيقة كانوا بياخدوا رسمة واحدة وأساميهم
/// مكوّمة، وراجل كبير ما يعرفش يفرّق الشرابين)، وكلمة الحالة تحتهم، وعلامة
/// الحالة على **خط رأسي متصل من دايرة لدايرة** — الفاصل الأفقي اللي كان
/// بيقطعه اتشال (نفس الجولة). والساعة بـص/م شمال. **الجرعات اللي في كارت
/// «الجرعة الجاية» مش هنا** (المالك) — الشاشة بتبعت الباقي بس.
///
/// قاعدة اللون: اتاخدت = ✓ أخضر هادي؛ الجاية = ساعة هادية **مش دهبي** (الدهبي
/// لـ«محتاجك دلوقتي» بس)؛ لو جرعة فاتت وصلت هنا نقطة دهبي و«لسه ما اتأكدتش»
/// من غير لوم ولا أحمر. المأخوذة **ما بتتشالش من السكة أبداً**. والدوسة على أي
/// صف بتفتح شاشة التذكير بتاعته.
class DayRail extends StatelessWidget {
  const DayRail({
    required this.groups,
    required this.now,
    required this.ruleLabelFor,
    this.onOpen,
    super.key,
  });

  /// الجرعات متجمّعة بالوقت — كل مجموعة دقيقة واحدة.
  final List<List<DoseEventView>> groups;
  final DateTime now;
  final String? Function(int doseScheduleId) ruleLabelFor;
  /// null (الممرض، ٥ أكتوبر ٢٠٢٦) = الصف مش بيتداس — مفيش شاشة تذكير
  /// تتفتح على موبايله، ودوسة بتعمل موجة من غير معنى أوحش من مفيش دوسة.
  final void Function(List<DoseEventView> group)? onOpen;

  /// عرض عمود العلامة، ومقاسها، ومقاس الرسمة الصغيرة.
  static const double _markWidth = 36;
  static const double _mark = 30;
  static const double pictureSize = 52;

  /// عرض عمود الساعة **ثابت** — من غيره «٢:٠٠ م» أضيق من «٥:٣٠ م» فعمود
  /// العلامة بيتزحزح مع كل صف والخط الرأسي بيطلع متكسّر (اتشاف في لقطة
  /// المرحلة أ، مش بالعين). ٦٤ بتسيع «١٢:٣٠ م» بخط ١٧ عريض.
  static const double _timeWidth = 64;

  @override
  Widget build(BuildContext context) {
    final sorted = [...groups]..sort((a, b) => a.first.scheduledAt.compareTo(b.first.scheduledAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // مفيش فاصل أفقي بين الصفوف (المالك): الفاصل كان بيقطع الخط
        // الرأسي، فالسكة كانت بتبان مكسورة بين كل دايرة والتانية.
        for (final (i, group) in sorted.indexed)
          _row(group, first: i == 0, last: i == sorted.length - 1),
      ],
    );
  }

  _Mark _markOf(List<DoseEventView> group) {
    if (group.every((d) => d.isDone)) return _Mark.done;
    final moment = doseMomentOf(
      scheduledAt: group.first.scheduledAt,
      now: now,
      markedMissed: group.any((d) => d.state == DoseState.missed),
    );
    return moment == DoseMoment.upcoming ? _Mark.upcoming : _Mark.needsYou;
  }

  Widget _row(List<DoseEventView> group, {required bool first, required bool last}) {
    final mark = _markOf(group);
    final done = mark == _Mark.done;
    final firstDose = group.first;
    return InkWell(
      key: ValueKey('rail-row-${firstDose.doseScheduleId}'),
      onTap: onOpen == null ? null : () => onOpen!(group),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: F.s10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // **كل دوا باسمه جنب رسمته هو** — مش رسمة واحدة
                    // للمجموعة وأسامي مكوّمة: شرابين في نفس الدقيقة لازم
                    // يتفرّقوا بالعين.
                    for (final (j, dose) in group.indexed) ...[
                      if (j > 0) const SizedBox(height: F.s6),
                      Row(
                        children: [
                          // الاسم **لاصق في رسمته** — مش في طرف والرسمة في
                          // طرف: المطابقة بالعين هي الهدف كله.
                          Flexible(
                            child: MedName(
                              dose.medicationName,
                              style: TextStyle(
                                fontSize: F.minBodySize,
                                fontWeight: FontWeight.w700,
                                color: done ? F.mutedDark : F.ink,
                                fontFamily: F.bodyFamily,
                                fontFamilyFallback: F.fontFallback,
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(width: F.s8),
                          Opacity(
                            opacity: done ? 0.6 : 1,
                            child: MedPhotoThumb(
                              path: dose.photoPath,
                              name: dose.medicationName,
                              form: MedicineForm.fromWire(dose.form),
                              size: pictureSize,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_secondLine(group, mark) case final line?)
                      Text(
                        line,
                        key: done ? ValueKey('taken-line-${firstDose.doseScheduleId}') : null,
                        style: TextStyle(
                          fontSize: F.minTextSize,
                          fontWeight: mark == _Mark.needsYou ? FontWeight.w700 : FontWeight.w400,
                          color: mark == _Mark.needsYou ? F.ink : F.mutedDark,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: F.s6),
            SizedBox(
              width: _markWidth,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // الخط الرأسي — متصل من أول صف لآخر صف: نصّ فوق ونصّ تحت العلامة
                  Column(
                    children: [
                      Expanded(child: Container(width: 2, color: first ? null : F.line)),
                      Expanded(child: Container(width: 2, color: last ? null : F.line)),
                    ],
                  ),
                  _markWidget(mark),
                ],
              ),
            ),
            const SizedBox(width: F.s6),
            SizedBox(
              width: _timeWidth,
              child: Center(
                child: Text(
                  arabicTime(firstDose.scheduledAt),
                  key: ValueKey('rail-time-${firstDose.doseScheduleId}'),
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: done ? F.mutedDark : F.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// السطر التاني: اتاخدت «أخدته ٨:٠٥ ص» (أو مين أكّدها)، اتأجّلت، فاتت «لسه
  /// ما اتأكدتش»، في معادها «معادها دلوقتي»، وإلا كلمة الأكل أو الجرعة.
  String? _secondLine(List<DoseEventView> group, _Mark mark) {
    final d = group.first;
    if (mark == _Mark.done) {
      if (d.state == DoseState.skipped) return 'اتأجّل';
      final at = arabicTime(d.actedAt ?? d.scheduledAt);
      // حد تاني أكّدها (الممرض، ٠٠٢٣): بنقول مين، مش «أخدته»
      return d.actedBy != null ? '${proxyConfirmedLine(d.actedBy)} $at' : takenAtLine(at);
    }
    if (mark == _Mark.needsYou) {
      final moment = doseMomentOf(
        scheduledAt: d.scheduledAt,
        now: now,
        markedMissed: group.any((x) => x.state == DoseState.missed),
      );
      return moment == DoseMoment.missed ? 'لسه ما اتأكدتش' : 'معادها دلوقتي';
    }
    final rule = ruleLabelFor(d.doseScheduleId);
    if (rule != null) return rule;
    final amount = d.amountLabel?.trim();
    return amount == null || amount.isEmpty ? null : amount;
  }

  Widget _markWidget(_Mark mark) => switch (mark) {
        _Mark.done => Container(
            key: const ValueKey('rail-mark-done'),
            width: _mark,
            height: _mark,
            decoration: BoxDecoration(color: F.greenOk, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.check, size: _mark - 10, color: F.onFill(F.greenOk)),
          ),
        // الجاية: ساعة هادية على أرضية الصفحة — مش دهبي
        _Mark.upcoming => Container(
            key: const ValueKey('rail-mark-upcoming'),
            width: _mark,
            height: _mark,
            decoration: BoxDecoration(color: F.pageGround, shape: BoxShape.circle, border: Border.all(color: F.line, width: 1.5)),
            alignment: Alignment.center,
            child: Icon(Icons.schedule, size: _mark - 10, color: F.mutedDark),
          ),
        // محتاجاك دلوقتي: نقطة دهبي — نفس معنى حافة الكارت
        _Mark.needsYou => Container(
            key: const ValueKey('rail-mark-needs-you'),
            width: _mark,
            height: _mark,
            decoration: BoxDecoration(color: F.pageGround, shape: BoxShape.circle, border: Border.all(color: F.gold, width: 2)),
            alignment: Alignment.center,
            child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: F.gold, shape: BoxShape.circle)),
          ),
      };
}

enum _Mark { done, upcoming, needsYou }
