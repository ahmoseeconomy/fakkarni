import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../format/arabic_time.dart';
import '../../format/relative_time.dart';
import '../../theme/tokens.dart';
import 'status_cues.dart';

/// الأعمدة اللي ينفع نرتّب بيها. الترتيب **دالة نقية** فوق القايمة —
/// بتتختبر من غير ما نرسم جدول.
enum AccountSort { lastSync, missedDoses, pendingEscalations }

List<AdminAccount> sortAccounts(
  List<AdminAccount> accounts,
  AccountSort by, {
  required bool ascending,
}) {
  int compare(AdminAccount a, AdminAccount b) => switch (by) {
        // الساكت الأول: null معناها عمره ما بعت، وده أسبق من أي تاريخ.
        AccountSort.lastSync => switch ((a.lastSyncAt, b.lastSyncAt)) {
            (null, null) => 0,
            (null, _) => -1,
            (_, null) => 1,
            (final x?, final y?) => x.compareTo(y),
          },
        AccountSort.missedDoses => a.missedDoses24h.compareTo(b.missedDoses24h),
        AccountSort.pendingEscalations =>
          a.pendingEscalations.compareTo(b.pendingEscalations),
      };
  final out = [...accounts]..sort(compare);
  return ascending ? out : out.reversed.toList();
}

/// اسم العمود — **نفس كلمة ترويسة الجدول بالحرف**، فالموبايل والمكتب
/// بيقولوا نفس الحاجة على نفس الرقم.
String sortFieldLabel(AccountSort by) => switch (by) {
      AccountSort.lastSync => 'آخر مزامنة',
      AccountSort.missedDoses => 'ما اتأكدتش ٢٤ س',
      AccountSort.pendingEscalations => 'تنبيهات مفتوحة',
    };

/// **الاتجاه اللي بيوري الوحش الأول** لكل عمود.
///
/// «الأكتر» في التنبيهات والجرعات، و«الأقدم» في المزامنة — والساكت
/// (`lastSyncAt == null`) بيطلع قبل أي تاريخ، فهو أول اللي بيتشاف.
/// الاختيار ده هو اللي بيخلّي «رتّب بالمزامنة» يجاوب على السؤال اللي
/// الواحد بيسأله فعلاً: مين ساكت؟
bool defaultAscendingFor(AccountSort by) => switch (by) {
      AccountSort.lastSync => true,
      AccountSort.missedDoses => false,
      AccountSort.pendingEscalations => false,
    };

/// وصف الاتجاه بالكلام — بيختلف مع العمود عشان يتقري لوحده.
///
/// «الأقل الأول» على عمود أرقام و«الأحدث الأول» على عمود وقت؛ كلمة واحدة
/// لكل الأعمدة («تصاعدي») كانت هتخلّي الواحد يترجم في دماغه.
String sortDirectionLabel(AccountSort by, {required bool ascending}) =>
    switch (by) {
      AccountSort.lastSync => ascending ? 'الأقدم الأول' : 'الأحدث الأول',
      _ => ascending ? 'الأقل الأول' : 'الأكتر الأول',
    };

/// بحث بالاسم — على الصفوف اللي راجعة خلاص، من غير رحلة تانية للسيرفر
/// (`admin_accounts()` بترجّع الأسطول كله، وده كفاية على الحجم الحالي).
List<AdminAccount> searchAccounts(List<AdminAccount> accounts, String query) {
  final needle = query.trim();
  if (needle.isEmpty) return accounts;
  return [
    for (final a in accounts)
      if (a.patientName.contains(needle)) a,
  ];
}

String batteryWord(String? state) => switch (state) {
      'restricted' => 'مقيّدة',
      'unrestricted' => 'مفكوكة',
      'unknown' => 'مش معروفة',
      _ => 'مفيش خبر',
    };

/// «أندرويد ١.٠.٠+١» — أو «مفيش نبضة» لو الموبايل عمره ما بعت.
String deviceWord(AdminAccount account) {
  final platform = switch (account.platform) {
    'android' => 'أندرويد',
    'ios' => 'آيفون',
    final other => other,
  };
  if (platform == null) return 'مفيش نبضة';
  final version = account.appVersion;
  return version == null ? platform : '$platform — ${arabicDigits(version)}';
}

class AccountsTable extends StatelessWidget {
  const AccountsTable({
    required this.accounts,
    required this.now,
    required this.sortBy,
    required this.ascending,
    required this.onSort,
    required this.onOpen,
    this.selected,
    super.key,
  });

  final List<AdminAccount> accounts;
  final DateTime now;
  final AccountSort sortBy;
  final bool ascending;
  final void Function(AccountSort by, bool ascending) onSort;
  final void Function(AdminAccount account) onOpen;
  final String? selected;

  static const _sortable = [
    AccountSort.lastSync,
    AccountSort.missedDoses,
    AccountSort.pendingEscalations,
  ];

  TextStyle get _cell => TextStyle(
        fontFamily: F.bodyFamily,
        fontSize: F.careTextSize,
        color: F.ink,
      );

  DataColumn _column(String label, {AccountSort? sort}) => DataColumn(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: F.bodyFamily,
            fontSize: F.careTextSize,
            fontWeight: FontWeight.w700,
            color: F.mutedDark,
          ),
        ),
        // عمود جديد بيبدأ من طرفه الوحش، ونفس العمود بيتقلب. قبل كده كل
        // عمود جديد كان بيبدأ تنازلي، يعني «آخر مزامنة» كانت بتبدأ
        // بالأحدث — أهدى صف في الأسطول أول القايمة.
        onSort: sort == null
            ? null
            : (_, asc) => onSort(
                  sort,
                  sort == sortBy ? !ascending : defaultAscendingFor(sort),
                ),
      );

  @override
  Widget build(BuildContext context) {
    final index = _sortable.indexOf(sortBy);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        // الترتيب اتعمل فوق في الحالة — الجدول بيعرض بس.
        sortColumnIndex: index < 0 ? null : index + 4,
        sortAscending: ascending,
        headingRowColor: WidgetStatePropertyAll(F.railGround),
        dividerThickness: 1,
        columns: [
          _column('الاسم'),
          _column('الحالة'),
          _column('الجهاز'),
          _column('البطارية'),
          _column('آخر مزامنة', sort: AccountSort.lastSync),
          _column('ما اتأكدتش ٢٤ س', sort: AccountSort.missedDoses),
          _column('تنبيهات مفتوحة', sort: AccountSort.pendingEscalations),
          _column('تنبيهات ٧ أيام'),
          _column('متابعين'),
          _column('أكواد مستنية'),
        ],
        rows: [
          for (final account in accounts)
            DataRow(
              selected: account.patientUuid == selected,
              onSelectChanged: (_) => onOpen(account),
              cells: [
                DataCell(Text(
                  account.patientName.isEmpty ? 'من غير اسم' : account.patientName,
                  style: _cell.copyWith(fontWeight: FontWeight.w600),
                )),
                DataCell(ToneBadge(rowTone(account, now))),
                DataCell(Text(deviceWord(account), style: _cell)),
                DataCell(Text(batteryWord(account.batteryState), style: _cell)),
                DataCell(Text(
                  account.lastSyncAt == null
                      ? 'مفيش'
                      : timeSince(now, account.lastSyncAt!),
                  style: _cell,
                )),
                DataCell(Text(arabicNumber(account.missedDoses24h), style: _cell)),
                DataCell(Text(arabicNumber(account.pendingEscalations), style: _cell)),
                DataCell(Text(arabicNumber(account.escalations7d), style: _cell)),
                DataCell(Text(arabicNumber(account.followersCount), style: _cell)),
                DataCell(Text(arabicNumber(account.pendingInvites), style: _cell)),
              ],
            ),
        ],
      ),
    );
  }
}
