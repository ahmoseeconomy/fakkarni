import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/med_name.dart';
import '../../data/repositories/medication_repository.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/medication/medicine_form.dart';
import '../../domain/scheduling/day_pattern.dart';
import '../../domain/scheduling/dose_schedule.dart';
import 'add_sheet.dart';
import 'edit_medication_screen.dart';
import 'med_groups.dart';
import 'med_photo.dart';

/// تبويب «أدويتك» (إعادة التصميم، ٤ أكتوبر ٢٠٢٦).
///
/// الأدوية **متجمّعة بالغرض** (`MedGroup`) — كل دوا صف واحد مهما كان عدد
/// جرعاته، والساعات كلها مكتوبة في سطر القاعدة. صورته هو، أو رسمة نوعه
/// والاسم مكتوب عليها. على كل صف «تعديل» بس — والإيقاف والرجوع والشيل جوّه
/// شاشة التعديل. اللي ما اتقالش لإيه في «من غير تصنيف»، والموقوف بيفضل
/// باين في «موقوفة» آخر الشاشة — **ما يختفيش**، زي الجرعة المأخوذة في السكة.
/// و«ضيف دوا» تحت بيفتح نفس شيت الدوك.
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({this.today, super.key});

  /// للاختبارات — يوم «هيبدأ يوم …».
  final DateTime? today;

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  Stream<List<MedicationSummary>>? _all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_all != null) return;
    final services = AppScope.of(context);
    _all = services.medications.watchAllSummaries(services.patientId);
  }

  void _edit(int medicationId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EditMedicationScreen(medicationId: medicationId)));

  @override
  Widget build(BuildContext context) {
    final today = widget.today ?? DateTime.now();
    return StreamBuilder<List<MedicationSummary>>(
      stream: _all,
      builder: (context, snap) {
        final all = snap.data ?? const <MedicationSummary>[];
        final active = [
          for (final m in all)
            if (m.medication.stoppedAt == null) m,
        ];
        final stopped = [
          for (final m in all)
            if (m.medication.stoppedAt != null) m,
        ]..sort(_byName);
        final groups = groupByPurpose(active);
        final pad = MediaQuery.paddingOf(context);

        return ListView(
          // مفيش شريط علوي على الهيكل — التبويب بيسيب مكان شريط النظام لنفسه
          padding: EdgeInsets.fromLTRB(F.gap, pad.top + F.gap, F.gap, F.gap + pad.bottom),
          children: [
            // العنوان على اليمين (البداية)، ومن غير سطر عدد تحته (المالك)
            Text(
              'أدويتك',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.screenTitleSize + 3,
                fontWeight: FontWeight.w800,
                color: F.ink,
              ),
            ),
            if (active.isEmpty) ...[
              const SizedBox(height: F.s4),
              Text(
                'لسه مفيش أدوية.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
            ],
            for (final g in groups.entries) ...[
              const SizedBox(height: F.gap),
              MedGroupHead(g.key),
              for (final (i, m) in g.value.indexed) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: F.line),
                _MedRow(summary: m, today: today, onEdit: () => _edit(m.medication.id)),
              ],
            ],
            if (stopped.isNotEmpty) ...[
              const SizedBox(height: F.gap),
              const MedGroupHead(MedGroup.stopped),
              for (final (i, m) in stopped.indexed) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: F.line),
                _MedRow(summary: m, today: today, stopped: true, onEdit: () => _edit(m.medication.id)),
              ],
            ],
            const SizedBox(height: F.gap),
            // «قريب منك» مكانه حبّاية «القريب مني» على الرئيسية، مش هنا.
            _AddButton(onTap: () => showAddSheet(context)),
          ],
        );
      },
    );
  }

  static int _byName(MedicationSummary a, MedicationSummary b) =>
      a.medication.name.toLowerCase().compareTo(b.medication.name.toLowerCase());
}

/// الأدوية الشغّالة بمجموعاتها، بترتيب [MedGroup] (التلاتة اللي في التصميم
/// الأول)، والمجموعة الفاضية مش موجودة. جوّه المجموعة: بأول ساعة، وبعدين
/// بالاسم.
Map<MedGroup, List<MedicationSummary>> groupByPurpose(List<MedicationSummary> active) {
  final by = <MedGroup, List<MedicationSummary>>{};
  for (final m in active) {
    by.putIfAbsent(MedGroup.of(MedicationPurpose.fromStorage(m.medication.purpose)), () => []).add(m);
  }
  int firstMinute(MedicationSummary m) =>
      m.schedules.isEmpty ? 24 * 60 : m.schedules.map((s) => s.timing.minuteOfDay.minutes).reduce((a, b) => a < b ? a : b);
  return {
    for (final g in MedGroup.values)
      if (by[g] case final list?)
        g: list
          ..sort((a, b) {
            final t = firstMinute(a).compareTo(firstMinute(b));
            return t != 0 ? t : a.medication.name.toLowerCase().compareTo(b.medication.name.toLowerCase());
          }),
  };
}

/// سطور الجرعة على صف «أدويتك» (المالك، بعد ما شافها على الموبايل): الجرعة
/// في سطر، والساعات في السطر اللي تحته — من غير شَرطة. كلمة الأكل والأيام
/// في سطر تالت، بس لو موجودين.
///
/// «قرص» / «٨:٠٠ ص و٨:٠٠ م» / «بعد الأكل».
({String dose, String times, String? extra}) doseLines(MedicationSummary summary) {
  final med = summary.medication;
  final schedules = [...summary.schedules]..sort((a, b) => a.timing.minuteOfDay.minutes.compareTo(b.timing.minuteOfDay.minutes));
  String timeOf(DoseSchedule s) => arabicTime(DateTime(2026, 1, 1, s.timing.minuteOfDay.hour, s.timing.minuteOfDay.minute));
  final meals = {for (final s in schedules) ?s.ruleLabel}.join(' و');
  final days = {for (final s in schedules) ?dayPatternLabel(s.days)}.join(' و');
  final extra = [if (meals.isNotEmpty) meals, if (days.isNotEmpty) days].join(' — ');
  return (
    // الجرعة مش معروفة — بهدوء، من غير لوم: سؤال للصيدلي مش غلطة
    dose: med.amountLabel ?? 'الجرعة مش معروفة',
    times: {for (final s in schedules) timeOf(s)}.join(' و'),
    extra: extra.isEmpty ? null : extra,
  );
}

/// دوا بدايته لسه جاية: كل جدوله بيبدأ بعد النهارده.
bool startsLater(MedicationSummary s, DateTime today) =>
    s.schedules.isNotEmpty && s.schedules.every((sch) => !sch.isActiveOn(today) && sch.startDate.isAfter(today));

DateTime firstStartDay(MedicationSummary s) => s.schedules.map((sch) => sch.startDate).reduce((a, b) => a.isBefore(b) ? a : b);

/// مقاس الصورة في الصف (المالك اختار ١٢٠ — قريب من التصميم ١١٥).
const medRowPictureSize = 120.0;

class _MedRow extends StatelessWidget {
  const _MedRow({required this.summary, required this.today, required this.onEdit, this.stopped = false});

  final MedicationSummary summary;
  final DateTime today;
  final VoidCallback onEdit;
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final med = summary.medication;
    final purpose = MedicationPurpose.fromStorage(med.purpose);
    final lines = doseLines(summary);
    return Padding(
      key: ValueKey('med-row-${med.id}'),
      padding: const EdgeInsets.symmetric(vertical: F.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Opacity(
            opacity: stopped ? 0.55 : 1,
            child: MedPhotoThumb(path: med.photoPath, name: med.name, form: MedicineForm.fromWire(med.form), size: medRowPictureSize),
          ),
          const SizedBox(width: F.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MedName(
                  med.name,
                  style: TextStyle(
                    fontSize: F.medicationNameSize,
                    fontWeight: FontWeight.w800,
                    color: stopped ? F.mutedDark : F.ink,
                    fontFamily: F.bodyFamily,
                    fontFamilyFallback: F.fontFallback,
                    height: 1.3,
                  ),
                ),
                if (purpose != null) ...[
                  const SizedBox(height: F.s6),
                  Align(alignment: AlignmentDirectional.centerStart, child: MedPurposeChip(purpose)),
                ],
                const SizedBox(height: F.s6),
                Text(
                  lines.dose,
                  key: ValueKey('med-dose-${med.id}'),
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.45),
                ),
                if (lines.times.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        // الساعة أيقونة هادية — الدهبي لـ«محتاجك دلوقتي» بس
                        child: Icon(Icons.schedule, size: 22, color: F.mutedDark),
                      ),
                      const SizedBox(width: F.s6),
                      Expanded(
                        child: Text(
                          lines.times,
                          key: ValueKey('med-times-${med.id}'),
                          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                if (lines.extra case final extra?)
                  Text(
                    extra,
                    key: ValueKey('med-extra-${med.id}'),
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.45),
                  ),
                if (!stopped && startsLater(summary, today))
                  Padding(
                    padding: const EdgeInsets.only(top: F.s4),
                    child: Text(
                      'هيبدأ يوم ${arabicDate(firstStartDay(summary))}',
                      key: ValueKey('starts-later-${med.id}'),
                      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink),
                    ),
                  ),
                if (stopped)
                  Padding(
                    padding: const EdgeInsets.only(top: F.s4),
                    child: Text(
                      'موقوف — التذكيرات واقفة',
                      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: F.s8),
          Container(width: 1, height: medRowPictureSize * 0.7, color: F.line),
          const SizedBox(width: F.s4),
          _EditButton(medicationId: med.id, onTap: onEdit),
        ],
      ),
    );
  }
}

/// «تعديل» — دايرة بقلم وكلمتها تحتها. مفيش زرار أيقونة من غير كلمة.
class _EditButton extends StatelessWidget {
  const _EditButton({required this.medicationId, required this.onTap});

  final int medicationId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'تعديل',
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('med-edit-$medicationId'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(F.radiusTile),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: F.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: F.s6, horizontal: F.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: F.medGroupEyeSkinTint, shape: BoxShape.circle),
                  child: Padding(
                    padding: const EdgeInsets.all(F.s10),
                    child: Icon(Icons.edit_outlined, size: 24, color: F.green),
                  ),
                ),
                const SizedBox(height: F.s4),
                Text(
                  'تعديل',
                  style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// «ضيف دوا» — أخضر مش مرجاني، علامة زايد وكلمتين. بيفتح نفس شيت الدوك.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: F.primaryButtonHeight,
    child: FilledButton.icon(
      key: const ValueKey('add-medication-card'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: F.green,
        foregroundColor: F.onGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard * 2)),
      ),
      icon: const Icon(Icons.add_circle, size: 30),
      label: const Text(
        addSheetTitle,
        style: TextStyle(fontSize: F.minBodySize + 2, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
