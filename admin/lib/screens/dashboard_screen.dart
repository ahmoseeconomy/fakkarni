import 'dart:async';

import 'package:flutter/material.dart';

import '../data/admin_models.dart';
import '../data/admin_service.dart';
import '../format/relative_time.dart';
import '../theme/tokens.dart';
import 'widgets/account_panel.dart';
import 'widgets/accounts_cards.dart';
import 'widgets/accounts_sort.dart';
import 'widgets/accounts_table.dart';
import 'widgets/admin_ui.dart';
import 'widgets/counts_strip.dart';
import 'widgets/side_panel.dart';
import 'widgets/skeletons.dart';
import 'widgets/top_bar.dart';

/// كل تحديث بيجيب العدّادات والصفوف مع بعض — نداء واحد للسحابة لكل سحبة.
/// **بيدق كل دقيقة وهو ظاهر وبس**، ووقفة على `paused`/`hidden` — نفس شكل
/// `CaregiverSnapshotHolder` في التطبيق.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.service,
    required this.onSignedOut,
    this.now,
    super.key,
  });

  final AdminService service;
  final VoidCallback onSignedOut;

  /// للاختبارات — الإنتاج بيقرا الساعة الحقيقية كل بناء.
  final DateTime? now;

  static const refreshEvery = Duration(seconds: 60);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  AdminCounts _counts = AdminCounts.empty;
  List<AdminAccount> _accounts = const [];
  AdminException? _error;
  bool _loading = true;

  /// تحديث شغّال ورا الشاشة — الأيقونة بتلفّ، والداتا القديمة فاضلة.
  bool _refreshing = false;
  DateTime? _updatedAt;

  AccountSort _sortBy = AccountSort.pendingEscalations;
  bool _ascending = false;
  String _query = '';

  AdminAccount? _open;
  List<AdminFollower> _followers = const [];
  List<AdminEscalation> _escalations = const [];
  AdminException? _panelError;
  bool _panelLoading = false;

  Timer? _timer;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
      _startPolling();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(DashboardScreen.refreshEvery, (_) => unawaited(refresh()));
  }

  Future<void> refresh() async {
    // أول تحميل بيتعرض كهيكل؛ اللي بعده بيلفّ الأيقونة وبس.
    if (mounted && !_loading && !_refreshing) setState(() => _refreshing = true);
    try {
      final counts = await widget.service.counts();
      final accounts = await widget.service.accounts();
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _accounts = accounts;
        _error = null;
        _loading = false;
        _refreshing = false;
        _updatedAt = _now;
      });
    } on AdminException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _openAccount(AdminAccount account) async {
    setState(() {
      _open = account;
      _followers = const [];
      _escalations = const [];
      _panelError = null;
      _panelLoading = true;
    });
    try {
      final followers = await widget.service.followers(account.patientUuid);
      final escalations = await widget.service.escalations(account.patientUuid);
      if (!mounted || _open?.patientUuid != account.patientUuid) return;
      setState(() {
        _followers = followers;
        _escalations = escalations;
        _panelLoading = false;
      });
    } on AdminException catch (e) {
      if (!mounted || _open?.patientUuid != account.patientUuid) return;
      setState(() {
        _panelError = e;
        _panelLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await widget.service.signOut();
    widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final rows = sortAccounts(
      searchAccounts(_accounts, _query),
      _sortBy,
      ascending: _ascending,
    );
    final open = _open;
    // تحت ده الجدول بيبقى كروت — نفس الصفوف، من غير تمرير أفقي.
    final narrow = MediaQuery.sizeOf(context).width < phoneBreakpoint;
    final withOpenAlerts = _accounts.where((a) => a.pendingEscalations > 0).length;

    final body = ListView(
      padding: const EdgeInsets.all(F.s16),
      children: [
        if (_loading)
          DashboardSkeleton(narrow: narrow)
        else ...[
          CountsStrip(_counts, accountsWithOpenAlerts: withOpenAlerts),
          const SizedBox(height: F.s16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: F.careRowGap,
            runSpacing: F.careRowGap,
            children: [
              SizedBox(
                width: narrow ? double.infinity : 280,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                      fontFamily: F.bodyFamily, fontSize: F.careBodySize, color: F.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: F.fieldGround,
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: F.mutedDark),
                    hintText: 'دوّر بالاسم',
                    hintStyle: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careTextSize,
                        color: F.placeholder),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_updatedAt != null)
                    Text(
                      'آخر تحديث ${timeSince(_now, _updatedAt!)}',
                      style: TextStyle(
                          fontFamily: F.bodyFamily,
                          fontSize: F.careMicroSize,
                          color: F.mutedDark),
                    ),
                  AdminTextAction(
                    label: 'حدّث',
                    icon: Icons.refresh_rounded,
                    busy: _refreshing,
                    onPressed: () => unawaited(refresh()),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: F.careRowGap),
          if (_error != null)
            AdminPanel(
              text: _error!.message,
              action: 'حاول تاني',
              onAction: () => unawaited(refresh()),
            )
          else if (rows.isEmpty)
            AdminPanel(text: _query.trim().isEmpty ? 'مفيش حسابات لسه.' : 'مفيش نتايج.')
          else if (narrow) ...[
            // الكروت مالهاش ترويسات تترتّب منها، فالقايمة هي بديلها.
            AccountsSortBar(
              sortBy: _sortBy,
              ascending: _ascending,
              onSort: (by, asc) => setState(() {
                _sortBy = by;
                _ascending = asc;
              }),
            ),
            const SizedBox(height: F.careRowGap),
            AccountsCards(
              accounts: rows,
              now: _now,
              selected: open?.patientUuid,
              onOpen: (account) => unawaited(_openAccount(account)),
            ),
          ] else
            AccountsTable(
              accounts: rows,
              now: _now,
              sortBy: _sortBy,
              ascending: _ascending,
              selected: open?.patientUuid,
              onSort: (by, asc) => setState(() {
                _sortBy = by;
                _ascending = asc;
              }),
              onOpen: (account) => unawaited(_openAccount(account)),
            ),
        ],
      ],
    );

    final panel = open == null
        ? null
        : AccountPanel(
            key: ValueKey(open.patientUuid),
            account: open,
            now: _now,
            followers: _followers,
            escalations: _escalations,
            loading: _panelLoading,
            error: _panelError,
            onRetry: () => unawaited(_openAccount(open)),
            onClose: () => setState(() => _open = null),
          );

    return Scaffold(
      backgroundColor: F.pageGround,
      appBar: AdminTopBar(
        email: widget.service.currentEmail,
        onSignOut: () => unawaited(_signOut()),
      ),
      // اللوحة بتنزلق من بداية السطر فوق ستارة — على الواسع والضيّق.
      body: SidePanelOverlay(
        panel: panel,
        onDismiss: () => setState(() => _open = null),
        child: body,
      ),
    );
  }
}
