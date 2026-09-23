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

  TextStyle get _label => TextStyle(
        fontFamily: F.bodyFamily,
        fontSize: F.careTextSize,
        color: F.mutedDark,
      );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: F.s8,
      runSpacing: F.s4,
      children: [
        Text('ترتيب', style: _label),
        // الحد الأدنى للمس على القايمة نفسها — `DropdownButton` بيطلع
        // أقصر من كده لوحده.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: F.careTapTarget),
          child: DropdownButton<AccountSort>(
            value: sortBy,
            isDense: false,
            borderRadius: BorderRadius.circular(F.radiusChip),
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
        AdminTextAction(
          label: sortDirectionLabel(sortBy, ascending: ascending),
          onPressed: () => onSort(sortBy, !ascending),
        ),
      ],
    );
  }
}
