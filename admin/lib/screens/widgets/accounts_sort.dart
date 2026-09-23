import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'accounts_table.dart';
import 'admin_ui.dart';

/// **ترتيب الكروت على الموبايل** — بديل ترويسات الجدول، اللي مش موجودة
/// لما الصفوف بتبقى كروت.
///
/// من غيره الموبايل كان بيعرض ترتيب واحد ثابت (التنبيهات المفتوحة الأول)
/// ومفيش طريقة تغيّره — يعني المكتب يقدر يسأل تلات أسئلة والموبايل سؤال
/// واحد، على نفس الداتا.
///
/// **قايمة بالعمود، وزرار بالاتجاه** — الاتنين بكلامهم، مفيش أيقونة
/// لوحدها. والقايمة تلات مداخل بس (نفس أعمدة الجدول اللي بتترتّب)، مش
/// ستة بالاتجاهين: ست سطور على شاشة بصة سريعة قراية مش اختيار.
class AccountsSortBar extends StatelessWidget {
  const AccountsSortBar({
    required this.sortBy,
    required this.ascending,
    required this.onSort,
    super.key,
  });

  final AccountSort sortBy;
  final bool ascending;
  final void Function(AccountSort by, bool ascending) onSort;

  static const _fields = [
    AccountSort.pendingEscalations,
    AccountSort.missedDoses,
    AccountSort.lastSync,
  ];


  @override
  Widget build(BuildContext context) {
    // سطر واحد: القايمة بتاخد العرض والزرار جنبها. Wrap كان بيكسرهم سطرين
    // على ٣٧٥ بكسل — مية بكسل زيادة فوق قايمة الحسابات على أضيق شاشة.
    return Row(
      children: [
        Icon(Icons.sort_rounded, size: 18, color: F.mutedDark),
        const SizedBox(width: F.s8),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: F.careTapTarget),
            child: DropdownButton<AccountSort>(
              value: sortBy,
              isExpanded: true,
              isDense: false,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(F.radiusChip),
              iconEnabledColor: F.mutedDark,
              dropdownColor: F.cardGround,
              style: TextStyle(
                fontFamily: F.bodyFamily,
                fontSize: F.careBodySize,
                fontWeight: FontWeight.w600,
                color: F.ink,
              ),
              items: [
                for (final field in _fields)
                  DropdownMenuItem<AccountSort>(
                    value: field,
                    child: Text(sortFieldLabel(field)),
                  ),
              ],
              // **عمود جديد بيبدأ من طرفه الوحش** — نفس قاعدة الجدول.
              onChanged: (field) {
                if (field == null || field == sortBy) return;
                onSort(field, defaultAscendingFor(field));
              },
            ),
          ),
        ),
        AdminTextAction(
          label: sortDirectionLabel(sortBy, ascending: ascending),
          icon: ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          onPressed: () => onSort(sortBy, !ascending),
        ),
      ],
    );
  }
}
