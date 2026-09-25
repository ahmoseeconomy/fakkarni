import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/care/medication_change.dart';
import '../../domain/escalation/alert_mode.dart';
import '../../domain/medication/medication_purpose.dart';
import '../../domain/medication/stock.dart' show stockUnitOf;
import '../medication/nurse_draft.dart';
import '../medication/refill_actions.dart' show showRestockSheet;
import 'nurse_controller.dart';
import 'nurse_widgets.dart';

/// **«أدويته»** — القايمة كاملة بتفاصيلها: الجرعة، المواعيد بكلامها، الدوا
/// ده لإيه، التعليمات، ونوع التنبيه.
///
/// التعديل (لو المريض سمح): «ضيف دوا»، «عدّل الجرعة»، «وقّفه» — **كلها
/// طلبات** بتتبعت لموبايله وتتطبّق عليه بسكّته هو (٠٠٢٤). الممرض عمره ما
/// بيكتب في جدول المريض.
class NurseMedicationsScreen extends StatefulWidget {
  const NurseMedicationsScreen({required this.controller, this.now, super.key});

  final NurseController controller;
  final DateTime? now;

  @override
  State<NurseMedicationsScreen> createState() => _NurseMedicationsScreenState();
}

class _NurseMedicationsScreenState extends State<NurseMedicationsScreen> {
  /// بيعيش مع الشاشة — ورقة بتتقفل لسه ليها كادرات بتتبني (درس جولة ١٦).
  final _amount = TextEditingController();

  NurseController get _c => widget.controller;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final draft = await draftMedicationAsNurse(context, today: widget.now);
    if (draft == null || !mounted) return;
    await _c.submit(
      kind: MedicationChangeKind.add,
      payload: MedicationChangePayload(
        name: draft.name,
        timings: draft.timings,
        amountLabel: draft.amountLabel,
        durationDays: draft.durationDays,
        purpose: draft.purpose,
        instructions: draft.instructions,
        alertMode: draft.alertMode,
        startDate: draft.startDate,
      ),
    );
  }

  Future<void> _stop(CaregiverMedication med) async {
    final yes = await FSheet.show<bool>(
      context,
      title: 'توقّف ${med.name}؟',
      children: [
        Text(
          'هيتبعت لموبايله ويتوقّف أول ما يفتح التطبيق. لو هو عدّله بنفسه بعد كده، تعديله هو اللي بيكسب.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('nurse-stop-confirm'),
          label: 'أيوه، وقّفه',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: F.s8),
        FSecondaryButton(label: 'لأ، سيبه', onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
    if (yes != true || !mounted) return;
    await _c.submit(
      kind: MedicationChangeKind.stop,
      payload: const MedicationChangePayload(),
      medicationUuid: med.uuid,
      medicationName: med.name,
    );
  }

  Future<void> _restock(CaregiverMedication med) async {
    final added = await showRestockSheet(context, name: med.name, unit: stockUnitOf(med.amountLabel));
    if (added == null || !mounted) return;
    await _c.submit(
      kind: MedicationChangeKind.restock,
      payload: MedicationChangePayload(quantity: added.toDouble()),
      medicationUuid: med.uuid,
      medicationName: med.name,
    );
  }

  Future<void> _editAmount(CaregiverMedication med) async {
    _amount.text = med.amountLabel ?? '';
    final amount = await FSheet.show<String>(
      context,
      title: 'جرعة ${med.name}',
      children: [
        TextField(
          key: const ValueKey('nurse-amount-field'),
          controller: _amount,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: F.minBodySize, color: F.ink),
          decoration: InputDecoration(
            hintText: 'زي: قرص واحد',
            filled: true,
            fillColor: F.fieldGround,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
          ),
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('nurse-amount-save'),
          label: 'ابعتها',
          onPressed: () => Navigator.of(context).pop(_amount.text),
        ),
      ],
    );
    final value = amount?.trim();
    if (value == null || value.isEmpty || !mounted) return;
    await _c.submit(
      kind: MedicationChangeKind.amount,
      payload: MedicationChangePayload(amountLabel: value),
      medicationUuid: med.uuid,
      medicationName: med.name,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_c, _c.holder]),
        builder: (context, _) {
          final snapshot = _c.holder.snapshot;
          if (snapshot == null) return const SizedBox.shrink();
          if (snapshot.patient.permissions.canEditMeds) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _c.loadPending());
          }
          final canEdit = _c.canEdit;
          return ListView(
            padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: [
              const FSectionHead('أدويته'),
              const SizedBox(height: F.s8),
              if (_c.error case final e?) ...[
                GoldNote(e),
                const SizedBox(height: F.s10),
              ],
              for (final c in _c.pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: F.s10),
                  child: NurseQuietLine(NurseController.pendingLine(c), key: ValueKey('nurse-pending-${c.uuid}')),
                ),
              if (snapshot.medications.isEmpty) const NurseQuietLine('لسه مفيش أدوية على موبايله.'),
              for (final m in snapshot.medications) _MedicationCard(
                med: m,
                onAmount: canEdit ? () => _editAmount(m) : null,
                onStop: canEdit ? () => _stop(m) : null,
                onRestock: canEdit ? () => _restock(m) : null,
              ),
              if (canEdit) ...[
                const SizedBox(height: F.s8),
                FSecondaryButton(key: const ValueKey('nurse-add-medication'), label: 'ضيف دوا', onPressed: _add),
                const SizedBox(height: F.s6),
                const NurseQuietLine('أي تعديل بيتبعت لموبايله ويتطبّق أول ما يفتح التطبيق.'),
              ] else if (!snapshot.patient.permissions.canEditMeds)
                const NurseQuietLine('تعديل الأدوية محتاج المريض يسمح بيه من «عيلتك أو ممرضك» على موبايله.'),
            ],
          );
        },
      );
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({required this.med, this.onAmount, this.onStop, this.onRestock});

  final CaregiverMedication med;
  final VoidCallback? onAmount;
  final VoidCallback? onStop;

  /// «اشتريت علبة جديدة» — طلب معلّق (٠٠٢٨)، لو المريض سمح بالتعديل.
  final VoidCallback? onRestock;

  @override
  Widget build(BuildContext context) {
    final purpose = MedicationPurpose.fromStorage(med.purpose);
    final mode = AlertMode.fromStorage(med.alertMode);
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: F.s4),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label: ', style: TextStyle(color: F.mutedDark, fontWeight: FontWeight.w600)),
              TextSpan(text: value, style: TextStyle(color: F.ink)),
            ]),
            style: TextStyle(fontSize: F.minTextSize, height: 1.45),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s10),
      child: FCard(
        key: ValueKey('nurse-med-${med.uuid}'),
        padding: const EdgeInsets.all(F.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              med.name,
              style: TextStyle(
                fontSize: F.minBodySize,
                fontWeight: FontWeight.w800,
                color: F.ink,
                fontFamily: F.monoFamily,
                fontFamilyFallback: F.monoFallback,
              ),
            ),
            if (med.amountLabel case final a?) line('الجرعة', a),
            for (final r in med.rules) line('الميعاد', r),
            if (purpose != null) line('الدوا ده لإيه', purpose.label),
            if (med.instructions case final i? when i.trim().isNotEmpty) line('تعليمات', i.trim()),
            line('التنبيه', mode?.label ?? 'زي إعداد موبايله'),
            if (med.stockLine case final stock?)
              Padding(
                padding: const EdgeInsets.only(top: F.s6),
                child: Container(
                  key: ValueKey('nurse-stock-${med.uuid}'),
                  padding: const EdgeInsetsDirectional.only(start: F.s8),
                  decoration: med.stockLow
                      ? const BoxDecoration(border: BorderDirectional(start: BorderSide(color: F.gold, width: 3)))
                      : null,
                  child: Text(stock, style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.45)),
                ),
              ),
            if (onRestock != null && med.stockQuantity != null) ...[
              const SizedBox(height: F.s8),
              FSecondaryButton(
                key: ValueKey('nurse-restock-${med.uuid}'),
                label: 'اشتريت علبة جديدة',
                onPressed: onRestock,
              ),
            ],
            if (onAmount != null || onStop != null) ...[
              const SizedBox(height: F.s10),
              Row(
                children: [
                  Expanded(
                    child: FSecondaryButton(
                      key: ValueKey('nurse-amount-${med.uuid}'),
                      label: 'عدّل الجرعة',
                      onPressed: onAmount,
                    ),
                  ),
                  const SizedBox(width: F.s8),
                  Expanded(
                    child: FSecondaryButton(
                      key: ValueKey('nurse-stop-${med.uuid}'),
                      label: 'وقّفه',
                      onPressed: onStop,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
