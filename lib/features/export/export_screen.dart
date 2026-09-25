import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../records/record_kinds.dart';
import 'export_actions.dart';
import 'export_document.dart';
import 'export_pdf.dart';
import 'export_preview_screen.dart';

/// «استخراج الملف» (المخطط ٣٠): الفترة، وكل قسم 👁 «هيظهر» / 🙈 «مخفي».
///
/// تحكّم **واحد** لكل قسم — التصميم فيه مفتاح و«👁 مرئي» لنفس المعنى، واتنين
/// بنفس المعنى بيلخبطوا. **الإخفاء بيتفرض وقت التوليد:** القسم المخفي ما
/// بيتقراش من القاعدة أصلاً (`collectExport`)، فمش موجود في الملف — مش
/// مستخبي فيه. الطوارئ مخفية من الأول، وأرقام جهات الاتصال عمرها ما بتدخل.
class ExportScreen extends StatefulWidget {
  const ExportScreen({this.actions = const DeviceExportActions(), this.fonts, this.now, super.key});

  final ExportActions actions;

  /// للاختبارات — التطبيق بيحمّلها من الأصول.
  final PdfFonts? fonts;
  final DateTime Function()? now;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late RecordPeriod _period = ExportOptions.defaults().period;
  late final Set<ExportSection> _visible = {...ExportOptions.defaults().visible};
  bool _busy = false;

  /// **switch شامل مش خريطة**: قسم جديد في [ExportSection] من غير سطر هنا
  /// كان بيوقّع الشاشة وقت التشغيل (`_hints[s]!`) — دلوقتي بيبقى خطأ بناء.
  static String _hint(ExportSection s) => switch (s) {
        ExportSection.medications => 'الأدوية الشغّالة دلوقتي',
        ExportSection.labs => 'النتايج اللي اتأكدت',
        ExportSection.imaging => 'تقارير الأشعة',
        ExportSection.prescriptions => 'الروشتات المتسجّلة',
        ExportSection.glucose => 'ملخص وأرقام',
        ExportSection.vitals => 'آخر ضغط ونبض ووزن وأكسجين وحرارة',
        ExportSection.visits => 'الزيارات والحجوزات',
        ExportSection.emergency => 'فصيلة الدم والحساسية — من غير أرقام جهات الاتصال',
      };

  Future<void> _preview() async {
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final now = widget.now?.call() ?? DateTime.now();
    final doc = await collectExport(
      services.db,
      patientId: services.patientId,
      options: ExportOptions(period: _period, visible: {..._visible}),
      now: now,
    );
    final bytes = await buildExportPdf(doc, widget.fonts ?? await PdfFonts.fromAssets());
    if (!mounted) return;
    setState(() => _busy = false);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => ExportPreviewScreen(
        pdf: bytes,
        document: doc,
        filename: 'fakkarni-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf',
        actions: widget.actions,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استخراج الملف')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          Text(
            'اختار الفترة، واخفي اللي مش عايز تشاركه. المخفي مش بيتكتب في الملف أصلاً.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.gap),
          const SectionHead('الفترة'),
          const SizedBox(height: F.s8),
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              for (final p in RecordPeriod.values)
                AnchorChip(
                  key: ValueKey('export-period-${p.name}'),
                  label: p.label,
                  selected: _period == p,
                  onTap: () => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: F.gap),
          const SectionHead('الأقسام'),
          const SizedBox(height: F.s8),
          FCard(
            child: Column(
              children: [
                for (final s in ExportSection.values) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.label, style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                            Text(_hint(s), style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
                          ],
                        ),
                      ),
                      const SizedBox(width: F.s8),
                      AnchorChip(
                        key: ValueKey('export-${s.name}'),
                        label: _visible.contains(s) ? '👁 هيظهر' : '🙈 مخفي',
                        selected: _visible.contains(s),
                        onTap: () => setState(() => _visible.contains(s) ? _visible.remove(s) : _visible.add(s)),
                      ),
                    ],
                  ),
                  if (s != ExportSection.values.last) Divider(color: F.lineSoft, height: F.s18),
                ],
              ],
            ),
          ),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('export-preview'),
            label: _busy ? 'بيجهّز الملف…' : 'عاين الملف',
            onPressed: _busy || _visible.isEmpty ? null : _preview,
          ),
          if (_visible.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: F.s6),
              child: Text('كل الأقسام مخفية — مفيش حاجة تتكتب.', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
            ),
        ],
      ),
    );
  }
}
