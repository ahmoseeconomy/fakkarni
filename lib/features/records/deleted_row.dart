import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/records_repository.dart';

/// صف ممسوح: المحتوى مشطوب وباهت ٤٥٪، وتحته «اتمسح» و«↺ رجّعه» بتباين
/// كامل — الحاجة ما بتختفيش من تحت إيد المستخدم (نفس الجرعة المأخوذة في
/// السكة). الزرار والكلمة مش باهتين: اللي هيدوس لازم يشوف.
class DeletedRecord extends StatelessWidget {
  const DeletedRecord({required this.child, required this.onRestore, super.key});

  final Widget child;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Opacity(
            opacity: 0.45,
            child: DefaultTextStyle.merge(
              style: const TextStyle(decoration: TextDecoration.lineThrough),
              child: child,
            ),
          ),
          const SizedBox(height: F.s8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'اتمسح',
                      style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                    ),
                    Text(
                      'هيتمسح نهائي بعد ${arabicNumber(RecordsRepository.retentionDays)} يوم — تقدر ترجّعه لحد كده',
                      style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: F.s8),
              SizedBox(
                height: F.minTapTarget,
                child: OutlinedButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.undo, size: 22),
                  label: const Text('رجّعه'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, F.minTapTarget),
                    foregroundColor: F.ink,
                    side: const BorderSide(color: F.ink, width: 1.5),
                    textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
}

/// الحالة الفاضية: بهدوء، وبتقول إزاي تضيف.
class RecordsEmpty extends StatelessWidget {
  const RecordsEmpty({required this.how, this.title = 'لسه مفيش حاجة هنا', super.key});

  final String title;
  final String how;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(F.gap),
        decoration: BoxDecoration(color: F.ivoryPale, borderRadius: BorderRadius.circular(F.radiusCard)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
            const SizedBox(height: F.s4),
            Text(how, style: const TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
          ],
        ),
      );
}
