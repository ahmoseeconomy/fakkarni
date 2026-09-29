import '../../voice/help_button.dart';
import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../data/repositories/stock_unit_store.dart';
import '../../../domain/medication/stock.dart';
import '../../medication/refill_actions.dart';

/// **«قرب يخلص» على «يومك»** — سطر ذهبي لكل دوا («كونكور فاضله ٤ أيام»)
/// وتحته «اشتريت علبة جديدة» و«اطلبه من الصيدلية». الذهبي بمعناه الواحد:
/// ده محتاج انتباهك دلوقتي. مفيش حاجة لما مفيش دوا قرب يخلص.
class RefillLines extends StatefulWidget {
  const RefillLines({super.key});

  @override
  State<RefillLines> createState() => _RefillLinesState();
}

class _RefillLinesState extends State<RefillLines> {
  Stream<List<MedicationStockView>>? _stream;

  /// الوحدة اللي اتختارت على الموبايل ده لدوا جرعته ما بتقولش.
  Map<int, String> _chosen = const {};

  @override
  void initState() {
    super.initState();
    StockUnitStore.all().then((m) {
      if (mounted) setState(() => _chosen = m);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _stream ??= StockRepository(s.db).watch(s.patientId);
  }

  String _unit(MedicationStockView v) =>
      resolveStockUnit(v.unit == unknownStockUnit ? null : v.unit, chosen: _chosen[v.medicationId]) ?? v.unit;

  Future<void> _restock(MedicationStockView v, {StockPack pack = StockPack.box}) async {
    final added = await showRestockSheet(context, name: v.name, unit: _unit(v), pack: pack);
    if (added == null || !mounted) return;
    final services = AppScope.of(context);
    await StockRepository(services.db).restock(v.medicationId, added.toDouble());
    await services.refreshRefills();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MedicationStockView>>(
        stream: _stream,
        builder: (context, snap) {
          final low = [for (final v in snap.data ?? const <MedicationStockView>[]) if (v.isLow) v];
          if (low.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final v in low)
                Padding(
                  padding: const EdgeInsets.only(bottom: F.gap),
                  child: Container(
                    key: ValueKey('refill-${v.medicationId}'),
                    padding: const EdgeInsets.all(F.s14),
                    decoration: BoxDecoration(
                      color: F.cardGround,
                      borderRadius: BorderRadius.circular(F.radiusCard),
                      border: const BorderDirectional(start: BorderSide(color: F.gold, width: 4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(alignment: AlignmentDirectional.centerEnd, child: HelpButton('help_stock_low')),
                        Text(
                          stockLowLine(v.name, stock: v.quantity, daysLeft: v.daysLeft ?? 0),
                          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.4),
                        ),
                        const SizedBox(height: F.s8),
                        FSecondaryButton(
                          key: ValueKey('refill-restock-${v.medicationId}'),
                          label: 'اشتريت علبة جديدة',
                          onPressed: () => _restock(v),
                        ),
                        // مش كل الناس بتشتري علبة (طلب المالك، ٢٩ سبتمبر ٢٠٢٦)
                        if (stripAllowed(_unit(v))) ...[
                          const SizedBox(height: F.s6),
                          FSecondaryButton(
                            key: ValueKey('refill-strip-${v.medicationId}'),
                            label: 'اشتريت شريط',
                            onPressed: () => _restock(v, pack: StockPack.strip),
                          ),
                        ],
                        const SizedBox(height: F.s6),
                        FSecondaryButton(
                          key: ValueKey('refill-order-${v.medicationId}'),
                          label: 'اطلبه من الصيدلية',
                          onPressed: () => orderFromPharmacy(context, v.name, allowStrip: stripAllowed(_unit(v))),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
