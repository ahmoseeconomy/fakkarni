import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/sync/change_undo.dart';
import '../../../data/sync/medication_change_pull.dart';

/// «سارة ضافت دوا Concor — ٨:٠٠ ص و٨:٠٠ م» — اللي الممرض غيّره واتطبّق على
/// الموبايل ده. كل سطر معاه «تمام»، و«تراجع» لو لسه في الـ٢٤ ساعة (0035):
/// الرجوع بنفس سكّة الكتابة، فالتذكيرات بتتلغي بالجدولة. مفيش حاجة لما مفيش.
class CircleNotices extends StatelessWidget {
  const CircleNotices({this.now, super.key});

  final DateTime? now;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<ChangeNotice>>(
        valueListenable: MedicationChangePuller.notices,
        builder: (context, list, _) {
          if (list.isEmpty) return const SizedBox.shrink();
          final t = now ?? DateTime.now();
          return Padding(
            padding: const EdgeInsets.only(bottom: F.s12),
            child: Container(
              key: const ValueKey('circle-notices'),
              padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
              decoration: BoxDecoration(
                color: F.cardGround,
                borderRadius: BorderRadius.circular(F.radiusCard),
                border: const BorderDirectional(start: BorderSide(color: F.gold, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final n in list) _NoticeRow(notice: n, now: t),
                ],
              ),
            ),
          );
        },
      );
}

class _NoticeRow extends StatefulWidget {
  const _NoticeRow({required this.notice, required this.now});

  final ChangeNotice notice;
  final DateTime now;

  @override
  State<_NoticeRow> createState() => _NoticeRowState();
}

class _NoticeRowState extends State<_NoticeRow> {
  bool _busy = false;
  String? _line;

  Future<void> _undo() async {
    final puller = AppScope.maybeOf(context)?.medChangePull;
    if (puller == null) return;
    setState(() => _busy = true);
    final ok = await puller.undo(widget.notice);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _line = 'مقدرناش نرجّعه — جرّب تاني.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notice;
    final canUndo = n.canUndoAt(widget.now) && AppScope.maybeOf(context)?.medChangePull != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            n.line,
            key: ValueKey('circle-notice-${n.uuid}'),
            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.4),
          ),
          if (_line != null)
            Text(_line!, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
          const SizedBox(height: F.s4),
          Row(
            children: [
              Expanded(
                child: FSecondaryButton(
                  key: ValueKey('circle-notice-ok-${n.uuid}'),
                  label: 'تمام',
                  onPressed: _busy ? null : () => MedicationChangePuller.dismiss(n.uuid),
                ),
              ),
              if (canUndo) ...[
                const SizedBox(width: F.s8),
                Expanded(
                  child: FSecondaryButton(
                    key: ValueKey('circle-notice-undo-${n.uuid}'),
                    label: 'تراجع',
                    onPressed: _busy ? null : _undo,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
