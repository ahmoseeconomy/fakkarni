import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';

/// «سجل التشخيص» — نافذة على `fkdiag.log`، أحدث سطر فوق.
///
/// موجودة عشان حاجة واحدة: سكّة صحوة شاشة القفل على iOS مالهاش مصحّح
/// متوصّل — التطبيق مقفول والنظام بيصحّيه لوحده. الملف ده هو الشاهد
/// الوحيد، وسويفت ودارت بيكتبوا فيه الاتنين، فالترتيب بينهم بيبان هنا.
///
/// **شاشة مطوّر**: الصف اللي بيفتحها متقفل على `!kReleaseMode` في
/// «الإعدادات»، فهي مش موجودة أصلاً في نسخة المتجر.
class DiagnosticsLogScreen extends StatefulWidget {
  const DiagnosticsLogScreen({super.key});

  @override
  State<DiagnosticsLogScreen> createState() => _DiagnosticsLogScreenState();
}

class _DiagnosticsLogScreenState extends State<DiagnosticsLogScreen> {
  List<String>? _lines;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lines = await readDiagLog();
    if (mounted) setState(() => _lines = lines);
  }

  Future<void> _copy() async {
    final lines = _lines ?? const <String>[];
    // بالترتيب الطبيعي وقت النسخ — الأقدم الأول، زي الملف نفسه، عشان
    // اللي هيقراها جنب Console.app يلاقي نفس السكّة.
    await Clipboard.setData(
        ClipboardData(text: lines.reversed.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اتنسخ السجل')));
    }
  }

  Future<void> _clear() async {
    await clearDiagLog();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return Scaffold(
      appBar: AppBar(title: const Text('سجل التشخيص')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s30 * 2),
        children: [
          Text(
            'سويفت ودارت بيكتبوا في نفس الملف ($diagFileName). '
            'الأحدث فوق، وآخر ${arabicNumber(diagMaxLines)} سطر بيفضلوا.',
            style: TextStyle(
                fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
          const SizedBox(height: F.s12),
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              SizedBox(
                width: 150,
                child: FSecondaryButton(label: 'حدّث', onPressed: _load),
              ),
              SizedBox(
                width: 150,
                child: FSecondaryButton(
                  label: 'انسخ',
                  onPressed: (lines == null || lines.isEmpty) ? null : _copy,
                ),
              ),
              SizedBox(
                width: 150,
                child: FSecondaryButton(
                  label: 'امسح',
                  onPressed: (lines == null || lines.isEmpty) ? null : _clear,
                ),
              ),
            ],
          ),
          const SizedBox(height: F.gap),
          if (lines == null)
            Text('بنقرا…',
                style: TextStyle(fontSize: F.minBodySize, color: F.mutedDark))
          else if (lines.isEmpty)
            Text(
              'لسه مفيش حاجة هنا. السجل بيتكتب في نسخة debug وprofile بس.',
              style: TextStyle(
                  fontSize: F.minBodySize, color: F.mutedDark, height: 1.5),
            )
          else
            for (final line in lines)
              Padding(
                key: const ValueKey('diag-line'),
                padding: const EdgeInsets.only(bottom: F.s8),
                child: SelectableText(
                  line,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: F.monoFamily,
                    // IBM Plex Mono مفيهوش عربي — من غير الاحتياطي الحروف
                    // بتتفصل عن بعضها، والسطور دي فيها عربي كتير.
                    fontFamilyFallback: F.monoFallback,
                    fontSize: F.minTextSize,
                    color: F.ink,
                    height: 1.4,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
