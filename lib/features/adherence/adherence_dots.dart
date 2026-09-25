import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/adherence/adherence.dart';

/// سبع نقط الأسبوع (سبت ← جمعة). **من غير أحمر ومن غير لوم**: اليوم
/// الكامل أخضر بعلامة ✓، اليوم اللي فيه جرعة ما اتأكدتش نقطة رمادي هادية،
/// المحايد حلقة خفيفة، واللي لسه جاي حلقة متقطّعة الشكل (فاضية). وكل نقطة
/// ليها اسم يومها تحتها ووصف بالكلام للقارئ الصوتي.
class AdherenceDots extends StatelessWidget {
  const AdherenceDots({
    required this.week,
    required this.today,
    this.dotSize = 28,
    this.labelSize = F.minTextSize,
    super.key,
  });

  final List<WeekDay> week;
  final DateTime today;
  final double dotSize;
  final double labelSize;

  @override
  Widget build(BuildContext context) => Row(
        key: const ValueKey('adherence-dots'),
        children: [
          for (final (i, d) in week.indexed)
            Expanded(
              child: Semantics(
                label: '${weekDayLetters[d.day.weekday]} — ${dayMarkWord(d.mark)}',
                excludeSemantics: true,
                child: Column(
                  children: [
                    _Dot(key: ValueKey('adherence-dot-$i-${d.mark.name}'), mark: d.mark, size: dotSize,
                        isToday: DateUtils.isSameDay(d.day, today)),
                    const SizedBox(height: F.s4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        weekDayLetters[d.day.weekday]!,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: labelSize,
                          color: DateUtils.isSameDay(d.day, today) ? F.ink : F.mutedDark,
                          fontWeight: DateUtils.isSameDay(d.day, today) ? FontWeight.w800 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.mark, required this.size, required this.isToday, super.key});
  final DayMark mark;
  final double size;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final (Color? fill, Color edge, double width) = switch (mark) {
      DayMark.complete => (F.green, F.green, 2.0),
      // فيه جرعة ما اتأكدتش: رمادي هادي — لا أحمر ولا دهبي.
      DayMark.missed => (F.line, F.line, 2.0),
      DayMark.neutral => (null, F.lineSoft, 1.5),
      DayMark.upcoming => (null, isToday ? F.green : F.line, 2.0),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: edge, width: width),
      ),
      child: mark == DayMark.complete
          ? Icon(Icons.check, size: size * 0.62, color: F.onDark)
          : null,
    );
  }
}
