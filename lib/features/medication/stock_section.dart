import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/stock_repository.dart';
import '../../data/repositories/stock_unit_store.dart';
import '../../domain/medication/stock.dart';
import 'refill_actions.dart';
import 'stock_left_card.dart';

/// **المخزون على شاشة الدوا** — اختياري. «عندك كام {وحدة} دلوقتي؟» على
/// عجلة، والعجلة **ما بتكتبش حاجة لحد ما تتحرّك** (رقم بنخترعه = مخزون
/// غلط). بعدها: «معاك ٢٠ قرص — تكفّي ١٠ أيام»، «نبّهني لما يفضل كام
/// يوم؟»، و«اشتريت علبة جديدة».
class StockSection extends StatefulWidget {
  const StockSection({required this.medicationId, required this.name, required this.amountLabel, super.key});

  final int medicationId;
  final String name;
  final String? amountLabel;

  @override
  State<StockSection> createState() => _StockSectionState();
}

class _StockSectionState extends State<StockSection> {
  Stream<List<MedicationStockView>>? _stream;
  bool _editing = false;

  /// الوحدة اللي اتختارت هنا لو الجرعة ما بتقولش — [StockUnitStore].
  String? _chosen;

  @override
  void initState() {
    super.initState();
    StockUnitStore.read(widget.medicationId).then((u) {
      if (mounted && u != null) setState(() => _chosen = u);
    });
  }

  Future<void> _chooseUnit(String? unit) async {
    setState(() => _chosen = unit);
    if (unit != null) await StockUnitStore.write(widget.medicationId, unit);
  }

  StockRepository get _repo => StockRepository(AppScope.of(context).db);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _stream ??= _repo.watch(s.patientId);
  }

  /// أول حركة بتدخل وضع التعديل — من غيرها أول تكّة كانت بتعمل الصف
  /// والشاشة بتقلب للملخص والعجلة لسه بتلف.
  Future<void> _set(int value) async {
    if (!_editing) setState(() => _editing = true);
    await _repo.setQuantity(widget.medicationId, value.toDouble());
  }

  Future<void> _restock(String unit, {StockPack pack = StockPack.box}) async {
    final added = await showRestockSheet(context, name: widget.name, unit: unit, pack: pack);
    if (added == null || !mounted) return;
    await _repo.restock(widget.medicationId, added.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveStockUnit(widget.amountLabel, chosen: _chosen);
    final fromAmount = stockUnitOf(widget.amountLabel) != unknownStockUnit;
    final unit = resolved ?? unknownStockUnit;
    final label = TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark);
    return StreamBuilder<List<MedicationStockView>>(
      stream: _stream,
      builder: (context, snap) {
        final view = (snap.data ?? const <MedicationStockView>[])
            .where((v) => v.medicationId == widget.medicationId)
            .firstOrNull;
        return Column(
          key: const ValueKey('stock-section'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (view != null && !_editing) ...[
              Text('المخزون', style: label),
              const SizedBox(height: F.s8),
              Text(
                stockSummaryLine(stock: view.quantity, unit: unit, daysLeft: view.daysLeft),
                key: const ValueKey('stock-summary'),
                style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
              ),
              const SizedBox(height: F.s8),
              FSecondaryButton(
                key: const ValueKey('stock-restock'),
                label: 'اشتريت علبة جديدة',
                onPressed: () => _restock(unit),
              ),
              // مش كل الناس بتشتري علبة (طلب المالك، ٢٩ سبتمبر ٢٠٢٦)
              if (stripAllowed(resolved)) ...[
                const SizedBox(height: F.s8),
                FSecondaryButton(
                  key: const ValueKey('stock-restock-strip'),
                  label: 'اشتريت شريط',
                  onPressed: () => _restock(unit, pack: StockPack.strip),
                ),
              ],
              const SizedBox(height: F.s8),
              FSecondaryButton(
                key: const ValueKey('stock-edit'),
                label: 'صحّح الرقم',
                onPressed: () => setState(() => _editing = true),
              ),
              const SizedBox(height: F.s12),
              Text('نبّهني لما يفضل كام يوم؟', style: label),
              FNumberWheel(
                key: const ValueKey('stock-warn-days'),
                value: view.warnDays,
                min: 1,
                max: 30,
                unit: 'يوم',
                semanticsLabel: 'نبّهني قبلها بكام يوم',
                onChanged: (v) => _repo.setWarnDays(widget.medicationId, v),
              ),
            ] else
              // «باقي كام قرص؟» — كارت لوحده، بوحدة الدوا (أو «ده إيه؟» الأول)
              StockLeftCard(
                unit: resolved,
                unitChosen: !fromAmount,
                // فاضية لحد ما تتحرّك — الرقم ده بتاع الإنسان، مش بتاعنا
                value: view?.quantity.round(),
                onUnit: _chooseUnit,
                onChanged: _set,
                trailing: view == null
                    ? null
                    : FSecondaryButton(
                        key: const ValueKey('stock-edit-done'),
                        label: 'تمام',
                        onPressed: () => setState(() => _editing = false),
                      ),
              ),
          ],
        );
      },
    );
  }
}
