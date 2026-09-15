import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'export_actions.dart';
import 'export_document.dart';

/// «معاينة الملف» (المخطط ٣١): **بالظبط اللي الطرف التاني هيشوفه** — صفحات
/// الـPDF نفسه متحوّلة صور، ونفس البايتات دي اللي بتتحفظ وبتتشارك.
///
/// المشاركة بتحفظ الملف الأول وبتقول مكانه بوضوح، وبعدها بتفتح قايمة
/// المشاركة. لو القايمة ما اتفتحتش، المسار فاضل مكتوب — مفيش زرار ما بيعملش
/// حاجة.
class ExportPreviewScreen extends StatefulWidget {
  const ExportPreviewScreen({
    required this.pdf,
    required this.document,
    required this.filename,
    required this.actions,
    super.key,
  });

  final Uint8List pdf;
  final ExportDocument document;
  final String filename;
  final ExportActions actions;

  @override
  State<ExportPreviewScreen> createState() => _ExportPreviewScreenState();
}

class _ExportPreviewScreenState extends State<ExportPreviewScreen> {
  final List<Uint8List> _pages = [];
  bool _rendering = true;
  String? _savedPath;
  String? _problem;

  @override
  void initState() {
    super.initState();
    widget.actions.rasterize(widget.pdf).listen(
      (page) {
        if (mounted) setState(() => _pages.add(page));
      },
      onDone: () {
        if (mounted) setState(() => _rendering = false);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _rendering = false;
            _problem = 'المعاينة ما اتعرضتش على الموبايل ده — الملف نفسه اتعمل.';
          });
        }
      },
    );
  }

  Future<void> _share() async {
    try {
      final path = await widget.actions.save(widget.pdf, widget.filename);
      if (mounted) setState(() => _savedPath = path);
      final opened = await widget.actions.share(widget.pdf, widget.filename);
      if (!opened && mounted) {
        setState(() => _problem = 'قايمة المشاركة ما اتفتحتش — الملف متحفظ في المكان اللي تحت.');
      }
    } catch (error) {
      if (mounted) setState(() => _problem = 'المشاركة ما اشتغلتش هنا${_savedPath == null ? '' : ' — الملف متحفظ في المكان اللي تحت'}.');
    }
  }

  Future<void> _print() async {
    try {
      await widget.actions.print(widget.pdf, widget.filename);
    } catch (error) {
      if (mounted) setState(() => _problem = 'الطباعة مش متاحة على الموبايل ده.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    return Scaffold(
      appBar: AppBar(title: const Text('معاينة الملف')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          const Text(
            'ده بالظبط اللي هيوصل للي هتشاركه معاه.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.s8),
          Text(
            'فيه: ${[for (final b in doc.blocks) b.section.label].join('، ')}',
            key: const ValueKey('preview-sections'),
            style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
          ),
          const SizedBox(height: F.s12),
          for (final (i, page) in _pages.indexed) ...[
            DecoratedBox(
              // الصفحة شفافة — ورقة بيضا وراها زي ما هتتفتح عند اللي هيستلمها
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: F.line), boxShadow: F.shadowCard),
              child: Image.memory(page, key: ValueKey('preview-page-$i'), gaplessPlayback: true),
            ),
            const SizedBox(height: F.s12),
          ],
          if (_rendering)
            const Padding(
              padding: EdgeInsets.all(F.gap),
              child: Text('بيجهّز الصفحات…', textAlign: TextAlign.center, style: TextStyle(fontSize: F.minBodySize, color: F.mutedDark)),
            ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(bottom: F.s8),
              child: Text(_problem!, style: const TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
            ),
          if (_savedPath != null)
            Container(
              key: const ValueKey('saved-path'),
              padding: const EdgeInsets.all(F.s12),
              margin: const EdgeInsets.only(bottom: F.s8),
              decoration: BoxDecoration(color: F.ivoryWarm, borderRadius: BorderRadius.circular(F.radiusCard)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اتحفظ على الموبايل: تطبيق «الملفات» ← على الآيفون ← فكرني ← exports',
                    style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
                  ),
                  Text(
                    widget.filename,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark, fontFamily: F.monoFamily, fontFamilyFallback: F.monoFallback),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(child: FPrimaryButton(key: const ValueKey('export-share'), label: 'احفظ وشارك', onPressed: _share)),
              const SizedBox(width: F.s10),
              Expanded(
                child: SizedBox(
                  height: F.primaryButtonHeight,
                  child: FSecondaryButton(label: 'طباعة', height: F.primaryButtonHeight, onPressed: _print),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
