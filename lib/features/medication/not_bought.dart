import '../voice/help_button.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/not_bought_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/medication/stock.dart' show stockUnitOf;
import 'refill_actions.dart';

/// **«أدوية لسه ماتشترتش»** — تذكرة شرا، مش مفتاح للتذكير.
///
/// الدوا بيرن في ميعاده من يوم التأكيد زي أي دوا؛ القايمة دي بتقول بس
/// إنه لسه محتاج يتشرى. «اطلبها من الصيدلية» على نفس سكّة واتساب بتاعة
/// المخزون (المستخدم بيبعت بنفسه)، و«اشتريته» بتشيله — ولو المخزون متتبّع
/// بتسأل كام في العلبة.
class NotBoughtSection extends StatefulWidget {
  const NotBoughtSection({this.showHead = true, super.key});

  final bool showHead;

  @override
  State<NotBoughtSection> createState() => _NotBoughtSectionState();
}

class _NotBoughtSectionState extends State<NotBoughtSection> {
  Stream<List<MedicationRow>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _stream ??= NotBoughtRepository(s.db).watch(s.patientId);
  }

  Future<void> _bought(MedicationRow med) async {
    final services = AppScope.of(context);
    final stock = StockRepository(services.db);
    // المخزون متتبّع؟ كام في العلبة — نفس «اشتريت علبة جديدة»
    if (await stock.rowFor(med.id) != null && mounted) {
      final added = await showRestockSheet(context, name: med.name, unit: stockUnitOf(med.amountLabel));
      if (added != null) await stock.restock(med.id, added.toDouble());
    }
    await NotBoughtRepository(services.db).markBought(med.id);
    await services.refreshRefills();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MedicationRow>>(
        stream: _stream,
        builder: (context, snap) {
          final meds = snap.data ?? const <MedicationRow>[];
          if (meds.isEmpty) return const SizedBox.shrink();
          return Column(
            key: const ValueKey('not-bought-section'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showHead) ...[
                FSectionHead('أدوية لسه ماتشترتش (${arabicNumber(meds.length)})'),
                const SizedBox(height: F.s8),
              ],
              for (final m in meds)
                Padding(
                  padding: const EdgeInsets.only(bottom: F.s8),
                  child: Container(
                    key: ValueKey('not-bought-${m.id}'),
                    padding: const EdgeInsets.all(F.s12),
                    decoration: BoxDecoration(
                      color: F.cardGround,
                      borderRadius: BorderRadius.circular(F.radiusCard),
                      border: Border.all(color: F.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          m.name,
                          style: TextStyle(
                            fontSize: F.minBodySize,
                            fontWeight: FontWeight.w700,
                            color: F.ink,
                            fontFamily: F.monoFamily,
                            fontFamilyFallback: F.monoFallback,
                          ),
                        ),
                        const SizedBox(height: F.s8),
                        FSecondaryButton(
                          key: ValueKey('not-bought-done-${m.id}'),
                          label: 'اشتريته',
                          onPressed: () => _bought(m),
                        ),
                      ],
                    ),
                  ),
                ),
              FSecondaryButton(
                key: const ValueKey('not-bought-order'),
                label: 'اطلبها من الصيدلية',
                onPressed: () => orderListFromPharmacy(context, [for (final m in meds) m.name]),
              ),
              const SizedBox(height: F.gap),
            ],
          );
        },
      );
}

/// سطر هادي على «يومك» — بيظهر بس لو القايمة مش فاضية، والدوسة بتفتحها.
class NotBoughtLine extends StatefulWidget {
  const NotBoughtLine({super.key});

  @override
  State<NotBoughtLine> createState() => _NotBoughtLineState();
}

class _NotBoughtLineState extends State<NotBoughtLine> {
  Stream<List<MedicationRow>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _stream ??= NotBoughtRepository(s.db).watch(s.patientId);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MedicationRow>>(
        stream: _stream,
        builder: (context, snap) {
          final meds = snap.data ?? const <MedicationRow>[];
          if (meds.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: F.gap),
            child: Material(
              color: F.railGround,
              borderRadius: BorderRadius.circular(F.radiusCard),
              child: InkWell(
                key: const ValueKey('not-bought-line'),
                borderRadius: BorderRadius.circular(F.radiusCard),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotBoughtScreen())),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: F.minTapTarget),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
                    child: Row(
                      children: [
                        Icon(Icons.shopping_bag_outlined, color: F.mutedDark, size: 24),
                        const SizedBox(width: F.s10),
                        Expanded(
                          child: Text(
                            notBoughtLineText([for (final m in meds) m.name]),
                            style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4),
                          ),
                        ),
                        Text('شوفها', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
                        const SizedBox(width: F.s8),
                        const HelpButton('help_not_bought'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// «Concor لسه ماتشترتش» / «فيه ٣ أدوية لسه ماتشترتش».
String notBoughtLineText(List<String> names) => switch (names.length) {
      1 => '${names.single} لسه ماتشترتش',
      2 => 'فيه دوايين لسه ماتشتروش',
      _ => 'فيه ${arabicNumber(names.length)} أدوية لسه ماتشتروش',
    };

/// القايمة لوحدها — من سطر «يومك».
class NotBoughtScreen extends StatelessWidget {
  const NotBoughtScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: F.pageGround,
        appBar: AppBar(
          backgroundColor: F.pageGround,
          title: Text('أدوية لسه ماتشترتش',
              style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, color: F.ink)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(F.gap),
          children: [
            Text('التذكير شغّال لها في ميعادها — القايمة دي عشان تفتكر تشتريها.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
            const SizedBox(height: F.s12),
            const NotBoughtSection(showHead: false),
          ],
        ),
      );
}
