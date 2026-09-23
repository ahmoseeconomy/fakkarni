import 'dart:async';

import 'package:flutter/material.dart';

import '../data/admin_models.dart';
import '../theme/tokens.dart';
import 'widgets/accounts_cards.dart';
import 'widgets/accounts_sort.dart';
import 'widgets/accounts_table.dart';
import 'widgets/admin_ui.dart';
import 'widgets/tone_filter_chips.dart';

/// الحسابات: بحث وحبّات فلتر، وجدول بصفحات — أو كروت على الموبايل.
///
/// **الترقيم والفلتر على الجهاز**: `admin_accounts()` بترجّع الأسطول كله في
/// نداء واحد، وده كفاية على الحجم الحالي. لما يعدّي الألفين، الترقيم
/// بيتنقل للسيرفر (`0022` المقترحة) والشاشة دي ما بتتغيّرش.
///
/// **مفيش خانات اختيار ولا «صدّر CSV» ولا أفعال جماعية**: الاختيار من غير
/// فعل وراه زينة، والأفعال محتاجة دوال كتابة على السيرفر مش موجودة.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({
    required this.accounts,
    required this.now,
    required this.filter,
    required this.onFilter,
    required this.onOpen,
    required this.narrow,
    this.selected,
    super.key,
  });

  final List<AdminAccount> accounts;
  final DateTime now;
  final AccountsFilter filter;
  final ValueChanged<AccountsFilter> onFilter;
  final void Function(AdminAccount account) onOpen;
  final bool narrow;
  final String? selected;

  static const searchDebounce = Duration(milliseconds: 250);

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late final TextEditingController _search = TextEditingController(text: widget.filter.query);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(AccountsScreen.searchDebounce, () {
      if (mounted) widget.onFilter(widget.filter.copyWith(query: value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    final searched = searchAccounts(widget.accounts, f.query);
    final counts = toneCounts(searched, widget.now);
    final filtered = filterByTone(searched, f.tone, widget.now);
    final sorted = sortAccounts(filtered, f.sortBy, ascending: f.ascending, now: widget.now);
    final pages = pageCount(sorted.length);
    final page = f.page.clamp(0, pages - 1);
    final rows = sorted.skip(page * pageSize).take(pageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: F.s8,
          runSpacing: F.s8,
          children: [
            SizedBox(
              width: widget.narrow ? double.infinity : 300,
              height: 40,
              child: TextField(
                controller: _search,
                onChanged: _onQuery,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careBodySize, color: F.ink),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: F.fieldGround,
                  contentPadding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s10),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: F.mutedDark),
                  hintText: 'دوّر بالاسم أو المعرّف',
                  hintStyle: TextStyle(
                      fontFamily: F.bodyFamily, fontSize: F.careTextSize, color: F.placeholder),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: F.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: F.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: F.gold, width: 1.5),
                  ),
                ),
              ),
            ),
            ToneFilterChips(
              counts: counts,
              selected: f.tone,
              onSelect: (tone) => widget.onFilter(f.copyWith(tone: tone)),
            ),
          ],
        ),
        const SizedBox(height: F.s12),
        if (widget.accounts.isEmpty)
          const _EmptyFleet()
        else if (sorted.isEmpty)
          AdminPanel(
            text: 'مفيش نتايج.',
            action: 'امسح البحث والفلتر',
            onAction: () {
              _search.clear();
              widget.onFilter(const AccountsFilter());
            },
          )
        else if (widget.narrow) ...[
          AccountsSortBar(
            sortBy: f.sortBy,
            ascending: f.ascending,
            onSort: (by, asc) => widget.onFilter(f.copyWith(sortBy: by, ascending: asc)),
          ),
          const SizedBox(height: F.careRowGap),
          AccountsCards(
            accounts: rows,
            now: widget.now,
            selected: widget.selected,
            onOpen: widget.onOpen,
          ),
          AccountsPager(page: page, total: sorted.length, onPage: (p) => widget.onFilter(f.copyWith(page: p))),
        ] else
          Container(
            decoration: BoxDecoration(
              color: F.cardGround,
              border: Border.all(color: F.line),
              borderRadius: BorderRadius.circular(F.careRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountsTable(
                  accounts: rows,
                  now: widget.now,
                  sortBy: f.sortBy,
                  ascending: f.ascending,
                  selected: widget.selected,
                  onSort: (by, asc) => widget.onFilter(f.copyWith(sortBy: by, ascending: asc)),
                  onOpen: widget.onOpen,
                ),
                Divider(height: 1, color: F.line),
                AccountsPager(page: page, total: sorted.length, onPage: (p) => widget.onFilter(f.copyWith(page: p))),
              ],
            ),
          ),
      ],
    );
  }
}

/// أسطول فاضي — مش «مفيش نتايج»: لسه محدش نزّل التطبيق.
class _EmptyFleet extends StatelessWidget {
  const _EmptyFleet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
          color: F.railGround,
          borderRadius: BorderRadius.circular(F.careRadius),
        ),
        child: Column(
          children: [
            Icon(Icons.group_add_rounded, size: 28, color: F.green),
            const SizedBox(height: F.s10),
            Text('مفيش حسابات لسه.',
                style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.careTitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink)),
            const SizedBox(height: F.s6),
            Text(
              'أول ما حد ينزّل التطبيق ويعمل حساب هيظهر هنا، ونبضة موبايله معاه.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careBodySize, color: F.mutedDark),
            ),
          ],
        ),
      ),
    );
  }
}
