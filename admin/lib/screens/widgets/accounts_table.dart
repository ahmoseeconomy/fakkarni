import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../format/arabic_time.dart';
import '../../format/grouped.dart';
import '../../format/relative_time.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'motion_widgets.dart';
import 'status_cues.dart';
import 'tone_filter_chips.dart';

/// الأعمدة اللي ينفع نرتّب بيها. الترتيب **دالة نقية** فوق القايمة —
/// بتتختبر من غير ما نرسم جدول.
enum AccountSort { severity, lastSync, missedDoses, pendingEscalations }

/// حالة قايمة الحسابات — بحث وفلتر وترتيب وصفحة. أي تغيير غير الصفحة
/// بيرجّع لأول صفحة (`copyWith` بيعمل ده لوحده).
class AccountsFilter {
  const AccountsFilter({
    this.query = '',
    this.tone = ToneFilter.all,
    this.sortBy = AccountSort.severity,
    this.ascending = true,
    this.page = 0,
  });

  final String query;
  final ToneFilter tone;
  final AccountSort sortBy;
  final bool ascending;
  final int page;

  AccountsFilter copyWith({
    String? query,
    ToneFilter? tone,
    AccountSort? sortBy,
    bool? ascending,
    int? page,
  }) {
    final changed = (query != null && query != this.query) ||
        (tone != null && tone != this.tone) ||
        (sortBy != null && sortBy != this.sortBy) ||
        (ascending != null && ascending != this.ascending);
    return AccountsFilter(
      query: query ?? this.query,
      tone: tone ?? this.tone,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      page: changed ? 0 : (page ?? this.page),
    );
  }
}

List<AdminAccount> sortAccounts(
  List<AdminAccount> accounts,
  AccountSort by, {
  required bool ascending,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  int compare(AdminAccount a, AdminAccount b) => switch (by) {
        // الخطورة: الساكت الأول، وعند التعادل الأكتر تنبيهات، وبعدها الأقدم نبضة.
        AccountSort.severity => _bySeverity(a, b, at),
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

int _bySeverity(AdminAccount a, AdminAccount b, DateTime now) {
  final s = severityIndex(rowTone(a, now)).compareTo(severityIndex(rowTone(b, now)));
  if (s != 0) return s;
  final p = b.pendingEscalations.compareTo(a.pendingEscalations);
  if (p != 0) return p;
  return switch ((a.seenAt, b.seenAt)) {
    (null, null) => 0,
    (null, _) => -1,
    (_, null) => 1,
    (final x?, final y?) => x.compareTo(y),
  };
}

/// بحث بالاسم **أو بأول المعرّف** — على الصفوف اللي راجعة خلاص، من غير
/// رحلة تانية للسيرفر (`admin_accounts()` بترجّع الأسطول كله).
List<AdminAccount> searchAccounts(List<AdminAccount> accounts, String query) {
  final needle = query.trim();
  if (needle.isEmpty) return accounts;
  final lower = needle.toLowerCase();
  return [
    for (final a in accounts)
      if (a.patientName.contains(needle) || a.patientUuid.toLowerCase().startsWith(lower)) a,
  ];
}

List<AdminAccount> filterByTone(List<AdminAccount> accounts, ToneFilter filter, DateTime now) {
  final tone = filter.tone;
  if (tone == null) return accounts;
  return [for (final a in accounts) if (rowTone(a, now) == tone) a];
}

/// عدّ كل حالة على نتيجة البحث الحالية — أرقام الحبّات.
Map<ToneFilter, int> toneCounts(List<AdminAccount> searched, DateTime now) {
  final counts = {for (final f in ToneFilter.values) f: 0};
  counts[ToneFilter.all] = searched.length;
  for (final a in searched) {
    final f = ToneFilter.of(rowTone(a, now));
    counts[f] = counts[f]! + 1;
  }
  return counts;
}

/// اسم العمود — **نفس كلمة ترويسة الجدول بالحرف**.
String sortFieldLabel(AccountSort by) => switch (by) {
      AccountSort.severity => 'الحالة',
      AccountSort.lastSync => 'آخر مزامنة',
      AccountSort.missedDoses => 'ما اتأكدتش ٢٤ س',
      AccountSort.pendingEscalations => 'تنبيهات مفتوحة',
    };

/// **الاتجاه اللي بيوري الوحش الأول** لكل عمود.
bool defaultAscendingFor(AccountSort by) => switch (by) {
      AccountSort.severity => true,
      AccountSort.lastSync => true,
      AccountSort.missedDoses => false,
      AccountSort.pendingEscalations => false,
    };

/// وصف الاتجاه بالكلام — بيختلف مع العمود عشان يتقري لوحده.
String sortDirectionLabel(AccountSort by, {required bool ascending}) =>
    switch (by) {
      AccountSort.severity => ascending ? 'الأخطر الأول' : 'الأهدى الأول',
      AccountSort.lastSync => ascending ? 'الأقدم الأول' : 'الأحدث الأول',
      _ => ascending ? 'الأقل الأول' : 'الأكتر الأول',
    };

String batteryWord(String? state) => switch (state) {
      'restricted' => 'مقيّدة',
      'unrestricted' => 'مفكوكة',
      'unknown' => 'مش معروفة',
      _ => 'مفيش خبر',
    };

/// «أندرويد — ١٫٦٫٠» — من غير رقم البناء؛ «مفيش نبضة» لو الموبايل عمره ما بعت.
String deviceWord(AdminAccount account) {
  final platform = switch (account.platform) {
    'android' => 'أندرويد',
    'ios' => 'آيفون',
    final other => other,
  };
  if (platform == null) return 'مفيش نبضة';
  final version = account.appVersion;
  if (version == null) return platform;
  final short = version.split('+').first;
  return '$platform — ${arabicDigits(short).replaceAll('.', '٫')}';
}

/// أول ٦ حروف من المعرّف — كفاية يتعرف بيها الصف، وبتتقري من الشمال.
String shortId(String uuid) => uuid.length > 6 ? uuid.substring(0, 6) : uuid;

/// ترويسة الصفحة في ذيل الجدول: «بيعرض ١–٢٥ من ٢٬٣٤٧».
String pageRangeLabel(int page, int total) {
  if (total == 0) return 'مفيش صفوف';
  final from = page * pageSize + 1;
  final to = ((page + 1) * pageSize).clamp(1, total);
  return 'بيعرض ${arabicGrouped(from)}–${arabicGrouped(to)} من ${arabicGrouped(total)}';
}

int pageCount(int total) => total == 0 ? 1 : ((total - 1) ~/ pageSize) + 1;

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

  /// صفوف **الصفحة الحالية** بس.
  final List<AdminAccount> accounts;
  final DateTime now;
  final AccountSort sortBy;
  final bool ascending;
  final void Function(AccountSort by, bool ascending) onSort;
  final void Function(AdminAccount account) onOpen;
  final String? selected;

  static const _sortable = {
    1: AccountSort.severity,
    4: AccountSort.lastSync,
    5: AccountSort.missedDoses,
    6: AccountSort.pendingEscalations,
  };

  TextStyle get _cell => TextStyle(
        fontFamily: F.bodyFamily,
        fontSize: F.careTextSize,
        color: F.ink,
      );

  /// **الأصفار باهتة** عشان الأرقام اللي ليها معنى تبان.
  Widget _number(int value, {bool alert = false}) => Text(
        arabicNumber(value),
        style: _cell.copyWith(
          color: value == 0 ? F.muted : (alert ? F.outOfRangeInk : F.ink),
          fontWeight: alert && value > 0 ? FontWeight.w700 : FontWeight.w400,
        ),
      );

  DataColumn _column(String label, {AccountSort? sort}) => DataColumn(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: F.bodyFamily,
            fontSize: F.careMicroSize,
            fontWeight: FontWeight.w700,
            color: sort != null && sort == sortBy ? F.ink : F.mutedDark,
            letterSpacing: 0.2,
          ),
        ),
        // عمود جديد بيبدأ من طرفه الوحش، ونفس العمود بيتقلب.
        onSort: sort == null
            ? null
            : (_, asc) => onSort(
                  sort,
                  sort == sortBy ? !ascending : defaultAscendingFor(sort),
                ),
      );

  List<Widget> _cellsFor(AdminAccount account) => [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              account.patientName.isEmpty ? 'من غير اسم' : account.patientName,
              style: _cell.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: F.s8),
            Text(
              shortId(account.patientUuid),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: F.monoFamily,
                fontFamilyFallback: F.monoFallback,
                fontSize: 11.5,
                color: F.muted,
              ),
            ),
          ],
        ),
        ToneBadge(rowTone(account, now)),
        Text(deviceWord(account), style: _cell),
        Text(
          batteryWord(account.batteryState),
          style: _cell.copyWith(
            color: account.batteryRestricted ? F.ink : F.mutedDark,
            fontWeight: account.batteryRestricted ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          account.lastSyncAt == null ? 'مفيش' : timeSince(now, account.lastSyncAt!),
          style: _cell.copyWith(color: account.lastSyncAt == null ? F.muted : F.ink),
        ),
        _number(account.missedDoses24h),
        _number(account.pendingEscalations, alert: true),
        _number(account.escalations7d),
        _number(account.followersCount),
        _number(account.pendingInvites),
      ];

  @override
  Widget build(BuildContext context) {
    final index = _sortable.entries.where((e) => e.value == sortBy).map((e) => e.key).firstOrNull;
    return Container(
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(color: F.line),
        borderRadius: BorderRadius.circular(F.careRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: index,
          sortAscending: ascending,
          showCheckboxColumn: false,
          headingRowColor: WidgetStatePropertyAll(F.railGround),
          headingRowHeight: 44,
          dataRowMinHeight: rowHeight,
          dataRowMaxHeight: rowHeight,
          dividerThickness: 0.6,
          horizontalMargin: F.s16,
          columnSpacing: F.s20,
          columns: [
            _column('الاسم'),
            _column('الحالة', sort: AccountSort.severity),
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
            for (final (i, account) in accounts.indexed)
              DataRow(
                selected: account.patientUuid == selected,
                onSelectChanged: (_) => onOpen(account),
                // زيبرا: الصف الفردي أغمق شوية. تحت الماوس: تظليل أخضر.
                // المفتوح في اللوحة: دهبي خفيف.
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) return F.greenTint;
                  if (states.contains(WidgetState.selected)) {
                    return F.gold.withValues(alpha: 0.12);
                  }
                  return i.isOdd ? F.railGround : null;
                }),
                cells: [
                  for (final cell in _cellsFor(account))
                    DataCell(FadeSlideIn(delay: staggerDelay(context, i), dy: 0.35, child: cell)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// ذيل الجدول: المدى والصفحة وزرارين. أرقام عربية، وسهم «السابق» لليمين
/// لأن السطر عربي.
class AccountsPager extends StatelessWidget {
  const AccountsPager({
    required this.page,
    required this.total,
    required this.onPage,
    super.key,
  });

  final int page;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = pageCount(total);
    final style = TextStyle(fontFamily: F.bodyFamily, fontSize: 13, color: F.mutedDark);
    Widget button(IconData icon, bool enabled, VoidCallback onTap, String word) {
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Tooltip(
          message: word,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(F.s10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: F.fieldGround,
                border: Border.all(color: F.line),
                borderRadius: BorderRadius.circular(F.s10),
              ),
              child: Icon(icon, size: 18, color: F.ink),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: F.s8,
        children: [
          Text(pageRangeLabel(page, total), style: style),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(Icons.chevron_right_rounded, page > 0, () => onPage(page - 1), 'السابقة'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: F.s10),
                child: Text('صفحة ${arabicNumber(page + 1)} من ${arabicNumber(pages)}', style: style),
              ),
              button(Icons.chevron_left_rounded, page < pages - 1, () => onPage(page + 1), 'اللي بعدها'),
            ],
          ),
        ],
      ),
    );
  }
}
