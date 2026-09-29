import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/medication/stock.dart';
import 'pharmacy_sheet.dart';

export 'pharmacy_sheet.dart' show editPharmacy;

/// بيفتح واتساب على رسالة جاهزة — **المستخدم بيراجعها ويبعتها بنفسه**.
/// متغيّر عشان الاختبار يسجّل الرابط بدل ما يفتح تطبيق.
Future<bool> Function(Uri uri) openWhatsApp = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// «اشتريت علبة جديدة» — كام {وحدة} زيادة، على عجلة. العجلة بتقف على ٣٠
/// والرقم ظاهر قدّامه، و«ضيف» هي اللي بتأكّده. null = قفل من غير حاجة.
///
/// **والشريط** ([StockPack.strip]، طلب المالك ٢٩ سبتمبر ٢٠٢٦): «كام {قرص} في
/// الشريط؟» — بيتسأل كل مرة ومفيش رقم متخزّن، والعجلة **ما بتكتبش حاجة لحد
/// ما تتحرّك** (عدد الشريط بيختلف من دوا لدوا، ورقم مننا = مخزون غلط).
Future<int?> showRestockSheet(BuildContext context,
        {required String name, required String unit, StockPack pack = StockPack.box}) =>
    FSheet.show<int>(
      context,
      title: pack == StockPack.strip ? 'اشتريت شريط' : 'اشتريت علبة جديدة',
      children: [_RestockBody(name: name, unit: unit, pack: pack)],
    );

class _RestockBody extends StatefulWidget {
  const _RestockBody({required this.name, required this.unit, required this.pack});
  final String name;
  final String unit;
  final StockPack pack;

  @override
  State<_RestockBody> createState() => _RestockBodyState();
}

class _RestockBodyState extends State<_RestockBody> {
  /// العلبة زي ما كانت (واقفة على ٣٠)؛ الشريط فاضي لحد ما يتحرّك.
  late int? _added = widget.pack == StockPack.box ? 30 : null;

  @override
  Widget build(BuildContext context) {
    final strip = widget.pack == StockPack.strip;
    final added = _added;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            strip
                ? 'كام ${widget.unit} في الشريط من ${widget.name}؟'
                : 'كام ${widget.unit} في العلبة الجديدة من ${widget.name}؟',
            style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
        const SizedBox(height: F.s8),
        FNumberWheel(
          key: const ValueKey('restock-wheel'),
          value: added,
          rest: strip ? 10 : 30,
          min: 1,
          max: 300,
          unit: widget.unit,
          semanticsLabel: 'الكمية الجديدة',
          onChanged: (v) => setState(() => _added = v),
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('restock-save'),
          label: added == null ? 'حرّك العجلة لعدد الشريط' : 'ضيف',
          onPressed: added == null ? null : () => Navigator.of(context).pop(added),
        ),
      ],
    );
  }
}

/// **«اطلبه من الصيدلية»** — لو «صيدليتي» مش متسجّلة بنسألها الأول، وبعدين
/// كام علبة، والرسالة ظاهرة قبل ما واتساب يفتح. **مفيش إرسال لوحده.**
///
/// [pharmacy] + [edit] (الممرض، 0035): صيدلية المريض من السحابة، والتعديل
/// طلب لموبايله — من غير قراية تفضيلات الموبايل ده.
Future<void> orderFromPharmacy(
  BuildContext context,
  String medicationName, {
  /// الأقراص والكبسولات: «علبة ولا شريط؟» (طلب المالك، ٢٩ سبتمبر ٢٠٢٦).
  bool allowStrip = false,
  ({String? name, String? whatsapp, String? call})? pharmacy,
  Future<({String? name, String? whatsapp, String? call})?> Function()? edit,
}) async {
  final prefs = AppScope.of(context).preferences;
  var pharmacy0 = pharmacy ?? await prefs.pharmacy();
  if (!context.mounted) return;
  if (pharmacy0.whatsapp == null || whatsappNumber(pharmacy0.whatsapp!) == null) {
    if (edit != null) {
      final next = await edit();
      if (next == null || next.whatsapp == null || !context.mounted) return;
      pharmacy0 = next;
    } else {
      final saved = await editPharmacy(context);
      if (saved != true || !context.mounted) return;
      pharmacy0 = await prefs.pharmacy();
      if (!context.mounted) return;
    }
  }
  final pharmacy1 = pharmacy0;
  final order = await FSheet.show<({int count, StockPack pack})>(
    context,
    title: 'اطلبه من ${pharmacy1.name ?? 'الصيدلية'}',
    children: [_OrderBody(name: medicationName, allowStrip: allowStrip)],
  );
  if (order == null) return;
  final number = whatsappNumber(pharmacy1.whatsapp!)!;
  await openWhatsApp(Uri.https(
      'wa.me', '/$number', {'text': pharmacyOrderMessage(medicationName, order.count, pack: order.pack)}));
}

/// **«اطلبها من الصيدلية»** لأكتر من دوا («أدوية لسه ماتشترتش») — نفس
/// السكّة: «صيدليتي» لو ناقصة، الرسالة ظاهرة، وواتساب بيفتح والمستخدم
/// هو اللي بيبعت.
Future<void> orderListFromPharmacy(BuildContext context, List<String> medicationNames) async {
  if (medicationNames.isEmpty) return;
  final prefs = AppScope.of(context).preferences;
  var pharmacy = await prefs.pharmacy();
  if (!context.mounted) return;
  if (pharmacy.whatsapp == null || whatsappNumber(pharmacy.whatsapp!) == null) {
    final saved = await editPharmacy(context);
    if (saved != true || !context.mounted) return;
    pharmacy = await prefs.pharmacy();
    if (!context.mounted) return;
  }
  final message = pharmacyListMessage(medicationNames);
  final go = await FSheet.show<bool>(
    context,
    title: 'اطلبها من ${pharmacy.name ?? 'الصيدلية'}',
    children: [
      Text('الرسالة:', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
      Text(message, key: const ValueKey('order-list-message'), style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
      const SizedBox(height: F.s6),
      Text('واتساب هيفتح والرسالة جاهزة — إنت اللي بتدوس «إرسال».',
          style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
      const SizedBox(height: F.gap),
      Builder(
        builder: (context) => FPrimaryButton(
          key: const ValueKey('order-list-open'),
          label: 'افتح واتساب',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
    ],
  );
  if (go != true) return;
  final number = whatsappNumber(pharmacy.whatsapp!)!;
  await openWhatsApp(Uri.https('wa.me', '/$number', {'text': message}));
}

class _OrderBody extends StatefulWidget {
  const _OrderBody({required this.name, this.allowStrip = false});
  final String name;
  final bool allowStrip;

  @override
  State<_OrderBody> createState() => _OrderBodyState();
}

class _OrderBodyState extends State<_OrderBody> {
  int _boxes = 1;
  StockPack _pack = StockPack.box;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.allowStrip) ...[
            Text('علبة ولا شريط؟', style: TextStyle(fontSize: F.minBodySize, color: F.ink)),
            const SizedBox(height: F.s8),
            Row(
              children: [
                Expanded(
                  child: AnchorChip(
                    key: const ValueKey('order-pack-box'),
                    label: 'علبة',
                    selected: _pack == StockPack.box,
                    onTap: () => setState(() => _pack = StockPack.box),
                  ),
                ),
                const SizedBox(width: F.s8),
                Expanded(
                  child: AnchorChip(
                    key: const ValueKey('order-pack-strip'),
                    label: 'شريط',
                    selected: _pack == StockPack.strip,
                    onTap: () => setState(() => _pack = StockPack.strip),
                  ),
                ),
              ],
            ),
            const SizedBox(height: F.s10),
          ],
          Text(_pack == StockPack.strip ? 'كام شريط؟' : 'كام علبة؟', style: TextStyle(fontSize: F.minBodySize, color: F.ink)),
          FNumberWheel(
            key: const ValueKey('order-boxes'),
            value: _boxes,
            min: 1,
            max: 10,
            unit: _pack == StockPack.strip ? 'شريط' : 'علبة',
            semanticsLabel: _pack == StockPack.strip ? 'عدد الشرايط' : 'عدد العلب',
            onChanged: (v) => setState(() => _boxes = v),
          ),
          const SizedBox(height: F.s10),
          Text('الرسالة:', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
          Text(pharmacyOrderMessage(widget.name, _boxes, pack: _pack),
              key: const ValueKey('order-message'), style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
          const SizedBox(height: F.s6),
          Text('واتساب هيفتح والرسالة جاهزة — إنت اللي بتدوس «إرسال».',
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('order-open'),
            label: 'افتح واتساب',
            onPressed: () => Navigator.of(context).pop((count: _boxes, pack: _pack)),
          ),
        ],
      );
}
