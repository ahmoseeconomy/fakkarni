import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/scheduling/dose_schedule.dart';

/// جرعة واحدة في قايمة: القاعدة والوقت المحسوب، «عدّل»، و«شيل» لو مسموح.
///
/// بتاخد [DoseTiming] مش صف محفوظ، عشان الشاشتين يستعملوها: تعديل دوا موجود
/// (جرعاته في القاعدة) و«ضيف دوا» (جرعات لسه في الذاكرة).
///
/// **null في أي من الزرارين معناه الزرار مش موجود خالص** — مش متعطّل. ودي
/// الأرضية: الدوا لازم له جرعة واحدة على الأقل، فآخر صف ما بيتشالش. زرار
/// رمادي على آخر جرعة كان هيخلّي المستخدم يدوس ويستنى حاجة تحصل.
///
/// القاعدة والوقت: القاعدة هي اللي بتتحفظ، والساعة للعرض بس (بتتحرك مع
/// مواعيد اليوم). الاتنين بكلمة على الزرار — مفيش زرار أيقونة من غير كلمة.
class DoseRow extends StatelessWidget {
  const DoseRow({
    required this.timing,
    required this.time,
    this.onEdit,
    this.onRemove,
    super.key,
  });

  final DoseTiming timing;

  /// الساعة المحسوبة على مواعيد اليوم — عرض بس، عمرها ما بتتخزّن.
  final String time;

  /// null = مفيش «عدّل» على الصف ده. في «ضيف دوا» التوقيت بيتراجع في
  /// محرّره بعد «كمّل»، فزرار تاني هنا كان هيبقى طريقين لنفس الحاجة.
  final VoidCallback? onEdit;

  /// null = الصف ده ما بيتشالش (آخر جرعة، أو شاشة ما بتشيلش).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s8),
          decoration: BoxDecoration(
            color: F.cardGround,
            borderRadius: BorderRadius.circular(F.radiusCard),
            border: Border.all(color: F.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${timing.ruleLabel} — $time',
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink),
                ),
              ),
              if (onEdit != null)
                _SmallButton(icon: Icons.edit_outlined, label: 'عدّل', onPressed: onEdit),
              if (onRemove != null) ...[
                if (onEdit != null) const SizedBox(width: F.s8),
                _SmallButton(
                  icon: Icons.remove_circle_outline,
                  label: 'شيل',
                  onPressed: onRemove,
                ),
              ],
            ],
          ),
        ),
      );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: F.ink,
            minimumSize: const Size(0, F.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.s12),
            side: BorderSide(color: F.line, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusTile)),
          ),
          icon: Icon(icon, size: 22),
          label: Text(label, style: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700)),
        ),
      );
}
