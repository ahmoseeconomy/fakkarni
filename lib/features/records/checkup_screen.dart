import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/services/checkup_service.dart';
import '../../domain/health/checkup.dart';
import '../../domain/scheduling/day_routine.dart';
import '../onboarding/time_wheel.dart';

/// «دورة الفحص» (المخطط ١١): سبع مراحل، والمستخدم بيقدّمها بإيده.
///
/// الخالصة ✓ خضرا، الحالية برقمها بالذهبي (الحالة اللي إنت عليها)، واللي
/// بعدها باهتة. السطر اللي تحت العنوان بيقول ليه الشاشة موجودة أصلاً.
///
/// «اضبط تذكير الصيام» بيجدول إشعار حقيقي — من الضغطة بس (القاعدة ٤)، بساعات
/// **المستخدم** كتبها (القاعدة ٦). مش مبني: صندوق «قاعدة: لا يمكن للفحص أن
/// يبقى…» (حكم على التأخير) و«المتوقع ٢٤ ساعة» (رقم ماحدش قاله).
class CheckupScreen extends StatefulWidget {
  const CheckupScreen({required this.recordId, this.now, super.key});

  final int recordId;

  /// للاختبارات.
  final DateTime Function()? now;

  @override
  State<CheckupScreen> createState() => _CheckupScreenState();
}

class _CheckupScreenState extends State<CheckupScreen> {
  Stream<RecordRow?>? _row;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  CheckupService get _checkups => AppScope.of(context).checkups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _row ??= _checkups.watch(widget.recordId);
  }

  Future<void> _fasting(RecordRow row) async {
    final checkups = _checkups;
    final messenger = ScaffoldMessenger.of(context);
    final input = await showModalBottomSheet<({DateTime draw, int hours})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: F.ivory,
      builder: (_) => _FastingSheet(now: _now),
    );
    if (input == null) return;
    final result = await checkups.setFastingReminder(row.id, draw: input.draw, hours: input.hours, now: _now);
    final text = switch (result) {
      FastingResult.scheduled => null,
      FastingResult.inPast => 'وقت بداية الصيام ده عدّى — اختار ميعاد سحب تاني.',
      FastingResult.tooMany => 'فيه تذكيرين صيام متظبطين لفحوصات تانية — شيل واحد الأول.',
      FastingResult.badHours => 'اكتب عدد الساعات اللي المعمل قالها.',
    };
    if (text != null) {
      messenger.showSnackBar(SnackBar(content: Text(text, style: const TextStyle(fontSize: F.minBodySize))));
    }
  }

  Future<void> _stop(RecordRow row) async {
    final checkups = _checkups;
    final navigator = Navigator.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('توقّف دورة «${row.title}»؟', style: const TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700)),
        content: const Text(
          'هتتمسح من الملف مشطوبة وتقدر ترجّعها، وتذكير الصيام بتاعها — لو فيه — بيتلغي.',
          style: TextStyle(fontSize: F.minBodySize, height: 1.5),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(key: const ValueKey('stop-confirm'), label: 'أيوه، وقّفها', onPressed: () => Navigator.of(context).pop(true)),
              const SizedBox(height: F.s8),
              FSecondaryButton(label: 'لأ، كمّل', onPressed: () => Navigator.of(context).pop(false)),
            ],
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await checkups.softDelete(row.id);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دورة الفحص')),
      body: StreamBuilder<RecordRow?>(
        stream: _row,
        builder: (context, snap) {
          final row = snap.data;
          final stage = CheckupStage.fromNumber(row?.checkupStage);
          if (row == null || stage == null) return const SizedBox.shrink();
          final reminder = row.fastingReminderAt;
          return ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
            children: [
              Text(
                '${row.title} — ${arabicNumber(CheckupStage.values.length)} مراحل',
                textDirection: nameDirection(row.title),
                style: const TextStyle(fontFamily: F.displayFamily, fontSize: F.screenTitleSize, fontWeight: FontWeight.w700, color: F.ink),
              ),
              const SizedBox(height: F.s4),
              const Text(
                'الفحص مش ميعاد واحد — كل خطوة ليها وقتها، وهنا بتعرف وقفت فين.',
                key: ValueKey('checkup-why'),
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
              const SizedBox(height: F.gap),
              for (final s in CheckupStage.values)
                _StageRow(
                  stage: s,
                  current: stage,
                  last: s == CheckupStage.values.last,
                  detail: s == CheckupStage.sampleDraw && reminder != null
                      ? '${arabicDate(row.happenedAt)} · ${arabicTime(row.happenedAt)}'
                      : null,
                  children: s != stage
                      ? const []
                      : [
                          const SizedBox(height: F.s10),
                          if (stage.next != null)
                            FPrimaryButton(
                              key: const ValueKey('checkup-advance'),
                              label: 'خلصت — على «${stage.next!.label}»',
                              onPressed: () => _checkups.advance(row.id),
                            ),
                          if (stage.next == null)
                            const Text(
                              'ده آخر مرحلة.',
                              style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.greenDeep),
                            ),
                          if (fastingReminderStillUseful(stage)) ...[
                            const SizedBox(height: F.s8),
                            if (reminder == null)
                              FPrimaryButton(
                                key: const ValueKey('fasting-set'),
                                label: 'اضبط تذكير الصيام',
                                gold: false,
                                onPressed: () => _fasting(row),
                              )
                            else ...[
                              Text(
                                'تذكير الصيام متظبط: ${arabicDate(reminder)} · ${arabicTime(reminder)}',
                                key: const ValueKey('fasting-set-line'),
                                style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
                              ),
                              const SizedBox(height: F.s6),
                              FSecondaryButton(label: 'شيل تذكير الصيام', onPressed: () => _checkups.cancelFasting(row.id)),
                            ],
                          ],
                          if (stage.previous != null) ...[
                            const SizedBox(height: F.s8),
                            FSecondaryButton(
                              key: const ValueKey('checkup-back'),
                              label: 'رجوع لـ«${stage.previous!.label}»',
                              onPressed: () => _checkups.back(row.id),
                            ),
                          ],
                        ],
                ),
              const SizedBox(height: F.gap),
              FSecondaryButton(label: 'وقّف الدورة دي', onPressed: () => _stop(row)),
            ],
          );
        },
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.current,
    required this.last,
    required this.children,
    this.detail,
  });

  final CheckupStage stage;
  final CheckupStage current;
  final bool last;
  final List<Widget> children;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final done = stage.number < current.number;
    final isCurrent = stage == current;
    final later = stage.number > current.number;

    final Widget node = Container(
      key: ValueKey('stage-${stage.number}'),
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? F.green : (isCurrent ? F.gold : Colors.white),
        border: later ? Border.all(color: F.line, width: 1.5) : null,
      ),
      child: done
          ? const Icon(Icons.check, size: 24, color: Colors.white)
          : Text(
              arabicNumber(stage.number),
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: later ? F.mutedLight : F.ink),
            ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                node,
                if (!last) Expanded(child: Container(width: 2, color: done ? F.green : F.line)),
              ],
            ),
          ),
          const SizedBox(width: F.s10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: F.gap, top: F.s6),
              child: Opacity(
                opacity: later ? 0.55 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      stage.label,
                      style: TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                        color: F.ink,
                      ),
                    ),
                    if (detail != null) Text(detail!, style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «اضبط تذكير الصيام»: ميعاد السحب (يوم + ساعة) وعدد ساعات الصيام **زي ما
/// المعمل قال** — مفيش رقم افتراضي.
class _FastingSheet extends StatefulWidget {
  const _FastingSheet({required this.now});

  final DateTime now;

  @override
  State<_FastingSheet> createState() => _FastingSheetState();
}

class _FastingSheetState extends State<_FastingSheet> {
  late DateTime _day = DateTime(widget.now.year, widget.now.month, widget.now.day + 1);
  MinuteOfDay _time = MinuteOfDay.hm(8);
  final _hours = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hours.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  int? get _parsedHours => int.tryParse(_hours.text.trim().replaceAllMapped(
        RegExp('[٠-٩]'),
        (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x660 + 0x30),
      ));

  @override
  Widget build(BuildContext context) {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final quick = [
      ('بكرة', DateTime(today.year, today.month, today.day + 1)),
      ('بعد بكرة', DateTime(today.year, today.month, today.day + 2)),
    ];
    final onQuick = quick.any((q) => q.$2 == _day);
    final hours = _parsedHours;
    final ok = hours != null && isTypedFastingHours(hours);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(F.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تذكير الصيام', style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, fontWeight: FontWeight.w700)),
              const SizedBox(height: F.s12),
              const SectionHead('ميعاد سحب العينة إمتى؟'),
              const SizedBox(height: F.s8),
              Wrap(
                spacing: F.s8,
                runSpacing: F.s8,
                children: [
                  for (final (label, day) in quick)
                    AnchorChip(label: label, selected: _day == day, onTap: () => setState(() => _day = day)),
                  AnchorChip(
                    label: onQuick ? 'يوم تاني' : arabicDate(_day),
                    selected: !onQuick,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: today,
                        lastDate: DateTime(today.year + 1, today.month, today.day),
                      );
                      if (picked != null) setState(() => _day = picked);
                    },
                  ),
                ],
              ),
              const SizedBox(height: F.s8),
              SizedBox(height: 180, child: TimeWheel(value: _time, onChanged: (t) => setState(() => _time = t))),
              const SizedBox(height: F.s12),
              const SectionHead('المعمل قال صيام كام ساعة؟'),
              const SizedBox(height: F.s8),
              TextField(
                key: const ValueKey('fasting-hours'),
                controller: _hours,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'زي ما المعمل قال',
                  hintStyle: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                  suffixText: 'ساعة',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
                ),
              ),
              const SizedBox(height: F.s6),
              const Text(
                'التطبيق مش بيحدد مدة الصيام — المعمل أو الدكتور هو اللي بيقولها.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
              const SizedBox(height: F.gap),
              FPrimaryButton(
                key: const ValueKey('fasting-save'),
                label: 'اضبط التذكير',
                onPressed: !ok
                    ? null
                    : () => Navigator.of(context).pop((
                          draw: DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute),
                          hours: hours,
                        )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
