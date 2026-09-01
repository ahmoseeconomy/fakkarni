import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/app_database.dart';
import '../../domain/scheduling/dose_schedule.dart';

/// تعديل دوا موجود: الجرعة زي ما الصيدلي قالها، أو إيقافه.
///
/// حاجتين بس عن قصد. التوقيت بيتعدّل من روتين اليوم مش من هنا، والإيقاف
/// **بإيد إنسان وبس** وبخطوتين — التطبيق عمره ما بيوقف دوا من نفسه.
class EditMedicationScreen extends StatefulWidget {
  const EditMedicationScreen({required this.medicationId, super.key});

  final int medicationId;

  @override
  State<EditMedicationScreen> createState() => _EditMedicationScreenState();
}

class _EditMedicationScreenState extends State<EditMedicationScreen> {
  final _amount = TextEditingController();
  Stream<MedicationRow?>? _medication;
  List<DoseSchedule> _schedules = const [];
  bool _seeded = false;
  bool _confirmingStop = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_medication != null) return;
    final services = AppScope.of(context);
    _medication = services.medications.watchMedication(widget.medicationId);
    services.medications.schedulesFor(widget.medicationId).then((s) {
      if (mounted) setState(() => _schedules = s);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    await services.medications.updateAmount(widget.medicationId, _amount.text);
    // نص التذكير فيه الجرعة — لازم يتعاد بناؤه بالنص الجديد.
    await services.scheduler.rescheduleAll();

    if (mounted) navigator.pop(true);
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    await services.medications.stopMedication(widget.medicationId);
    // تذكيراته بتتلغى هنا — جوّه نطاق الجرعات بس.
    await services.scheduler.rescheduleAll();

    if (mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الدوا',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<MedicationRow?>(
          stream: _medication,
          builder: (context, snapshot) {
            final med = snapshot.data;
            if (med == null) {
              return const Center(child: CircularProgressIndicator(color: F.green));
            }
            if (!_seeded) {
              _seeded = true;
              _amount.text = med.amountLabel ?? '';
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(F.gap),
                    children: [
                      Text(
                        med.name,
                        style: const TextStyle(
                          fontSize: F.questionSize,
                          fontWeight: FontWeight.w700,
                          color: F.ink,
                          fontFamily: F.monoFamily,
                          fontFamilyFallback: F.monoFallback,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _schedules.isEmpty
                            ? 'التوقيت بيتعدّل من «عدّل يومك».'
                            : '${_schedules.map((s) => s.ruleLabel).join(' + ')} — '
                                'التوقيت بيتعدّل من «عدّل يومك».',
                        style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.6),
                      ),
                      const SizedBox(height: F.gap + 6),
                      const Text(
                        'الجرعة',
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.muted),
                      ),
                      const SizedBox(height: 8),
                      if (med.amountUnknown) ...[
                        // الذهبي هنا بمعناه الواحد: ده محتاج انتباهك.
                        const Text(
                          'الورقة ما قالتش الجرعة — اسأل الصيدلي واكتبها هنا.',
                          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.gold, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: _amount,
                        style: const TextStyle(fontSize: F.minBodySize),
                        decoration: InputDecoration(
                          hintText: 'زي: قرص واحد',
                          hintStyle: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(F.radius),
                            borderSide: const BorderSide(color: F.line),
                          ),
                        ),
                      ),
                      const SizedBox(height: F.gap + 6),
                      if (_confirmingStop) _StopConfirm(
                        name: med.name,
                        busy: _busy,
                        onStop: _stop,
                        onKeep: () => setState(() => _confirmingStop = false),
                      ) else
                        SizedBox(
                          height: F.minTapTarget,
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => setState(() => _confirmingStop = true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: F.ink,
                              side: const BorderSide(color: F.ink, width: 1.5),
                            ),
                            child: const Text(
                              'وقّف الدوا ده',
                              style: TextStyle(fontSize: F.minTextSize + 1, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'ملحوظة: خلّصت العلبة أو الدكتور غيّر الدوا؟ وقّفه من هنا. '
                        'التطبيق عمره ما بيوقف دوا لوحده'
                        '${_durationNote(med)}',
                        style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.6),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(F.gap),
                  child: SizedBox(
                    width: double.infinity,
                    height: F.primaryButtonHeight,
                    child: FilledButton(
                      onPressed: _busy || _confirmingStop ? null : _save,
                      child: const Text('احفظ'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _durationNote(MedicationRow med) {
    final days = _schedules.map((s) => s.durationDays).whereType<int>();
    if (days.isEmpty) return '.';
    return ' — العلاج ده ${arabicNumber(days.first)} يوم وبعدها بيوقف لوحده.';
  }
}

/// خطوة التأكيد — سؤال واضح وجوابين بنفس الحجم. من غير أحمر.
class _StopConfirm extends StatelessWidget {
  const _StopConfirm({
    required this.name,
    required this.busy,
    required this.onStop,
    required this.onKeep,
  });

  final String name;
  final bool busy;
  final VoidCallback onStop;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(F.radius),
          border: Border.all(color: F.ink, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'توقّف $name؟ التذكيرات هتقف لحد ما تضيفه تاني.',
              style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: F.minTapTarget,
                    child: FilledButton(
                      onPressed: busy ? null : onStop,
                      style: FilledButton.styleFrom(
                        backgroundColor: F.ink,
                        foregroundColor: F.ivory,
                        minimumSize: const Size.fromHeight(F.minTapTarget),
                      ),
                      child: const Text('أيوه، وقّفه'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: F.minTapTarget,
                    child: OutlinedButton(
                      onPressed: busy ? null : onKeep,
                      child: const Text(
                        'لا، سيبه',
                        style: TextStyle(fontSize: F.minTextSize + 1, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
