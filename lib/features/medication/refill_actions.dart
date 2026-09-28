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
Future<int?> showRestockSheet(BuildContext context, {required String name, required String unit}) =>
    FSheet.show<int>(
      context,
      title: 'اشتريت علبة جديدة',
      children: [_RestockBody(name: name, unit: unit)],
    );

class _RestockBody extends StatefulWidget {
  const _RestockBody({required this.name, required this.unit});
  final String name;
  final String unit;

  @override
  State<_RestockBody> createState() => _RestockBodyState();
}

class _RestockBodyState extends State<_RestockBody> {
  int _added = 30;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كام ${widget.unit} في العلبة الجديدة من ${widget.name}؟',
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
          const SizedBox(height: F.s8),
          FNumberWheel(
            key: const ValueKey('restock-wheel'),
            value: _added,
            min: 1,
            max: 300,
            unit: widget.unit,
            semanticsLabel: 'الكمية الجديدة',
            onChanged: (v) => setState(() => _added = v),
          ),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('restock-save'),
            label: 'ضيف',
            onPressed: () => Navigator.of(context).pop(_added),
          ),
        ],
      );
}

/// **«اطلبه من الصيدلية»** — لو «صيدليتي» مش متسجّلة بنسألها الأول، وبعدين
/// كام علبة، والرسالة ظاهرة قبل ما واتساب يفتح. **مفيش إرسال لوحده.**
Future<void> orderFromPharmacy(BuildContext context, String medicationName) async {
  final prefs = AppScope.of(context).preferences;
  var pharmacy = await prefs.pharmacy();
  if (!context.mounted) return;
  if (pharmacy.whatsapp == null || whatsappNumber(pharmacy.whatsapp!) == null) {
    final saved = await editPharmacy(context);
    if (saved != true || !context.mounted) return;
    pharmacy = await prefs.pharmacy();
    if (!context.mounted) return;
  }
  final boxes = await FSheet.show<int>(
    context,
    title: 'اطلبه من ${pharmacy.name ?? 'الصيدلية'}',
    children: [_OrderBody(name: medicationName)],
  );
  if (boxes == null) return;
  final number = whatsappNumber(pharmacy.whatsapp!)!;
  await openWhatsApp(Uri.https('wa.me', '/$number', {'text': pharmacyOrderMessage(medicationName, boxes)}));
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
  const _OrderBody({required this.name});
  final String name;

  @override
  State<_OrderBody> createState() => _OrderBodyState();
}

class _OrderBodyState extends State<_OrderBody> {
  int _boxes = 1;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كام علبة؟', style: TextStyle(fontSize: F.minBodySize, color: F.ink)),
          FNumberWheel(
            key: const ValueKey('order-boxes'),
            value: _boxes,
            min: 1,
            max: 10,
            unit: 'علبة',
            semanticsLabel: 'عدد العلب',
            onChanged: (v) => setState(() => _boxes = v),
          ),
          const SizedBox(height: F.s10),
          Text('الرسالة:', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
          Text(pharmacyOrderMessage(widget.name, _boxes),
              key: const ValueKey('order-message'), style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
          const SizedBox(height: F.s6),
          Text('واتساب هيفتح والرسالة جاهزة — إنت اللي بتدوس «إرسال».',
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('order-open'),
            label: 'افتح واتساب',
            onPressed: () => Navigator.of(context).pop(_boxes),
          ),
        ],
      );
}
