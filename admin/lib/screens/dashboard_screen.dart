import 'dart:async';

import 'package:flutter/material.dart';

import '../data/admin_models.dart';
import '../data/admin_service.dart';
import '../theme/tokens.dart';
import 'accounts_screen.dart';
import 'devices_screen.dart';
import 'overview_screen.dart';
import 'widgets/account_panel.dart';
import 'widgets/accounts_table.dart';
import 'widgets/admin_ui.dart';
import 'widgets/device_problems.dart';
import 'widgets/screen_header.dart';
import 'widgets/side_panel.dart';
import 'widgets/sidebar.dart';
import 'widgets/skeletons.dart';
import 'widgets/tone_filter_chips.dart';
import 'widgets/top_bar.dart';

/// هيكل اللوحة: الشريط الجانبي + المحتوى، وفوقهم اللوحة الجانبية.
///
/// كل تحديث بيجيب العدّادات والصفوف مع بعض — نداء واحد للسحابة لكل سحبة.
/// **بيدق كل دقيقة وهو ظاهر وبس**، ووقفة على `paused`/`hidden`.
///
/// الاسم فاضل `DashboardScreen` — الملف هو نفس نقطة الدخول، اللي اتغيّر إنه
/// بقى بيوزّع على تلات شاشات بدل ما يرسم واحدة.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.service,
    required this.onSignedOut,
    this.now,
    this.initialScreen = AdminScreen.overview,
    super.key,
  });

  final AdminService service;
  final VoidCallback onSignedOut;

  /// للاختبارات — الإنتاج بيقرا الساعة الحقيقية كل بناء.
  final DateTime? now;
  final AdminScreen initialScreen;

  static const refreshEvery = Duration(seconds: 60);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  AdminCounts _counts = AdminCounts.empty;
  List<AdminAccount> _accounts = const [];
  List<AdminDevice> _devices = const [];
  AdminException? _error;
  bool _loading = true;
  bool _refreshing = false;
  DateTime? _updatedAt;

  late AdminScreen _screen = widget.initialScreen;
  AccountsFilter _filter = const AccountsFilter();

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
    if (mounted && !_loading && !_refreshing) setState(() => _refreshing = true);
    try {
      final counts = await widget.service.counts();
      final accounts = await widget.service.accounts();
      final devices = await widget.service.devices();
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _accounts = accounts;
        _devices = devices;
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

  void _navigate(AdminScreen screen, {ToneFilter? tone}) {
    setState(() {
      _screen = screen;
      _open = null;
      if (tone != null) _filter = _filter.copyWith(tone: tone, sortBy: AccountSort.severity, ascending: true);
    });
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

  /// دوسة على جهاز بتفتح حسابه — الجهاز مش أوضة لوحده.
  void _openDevice(AdminDevice device) {
    final account = _accounts.where((a) => a.patientUuid == device.patientUuid).firstOrNull;
    if (account != null) unawaited(_openAccount(account));
  }

  Future<void> _signOut() async {
    await widget.service.signOut();
    widget.onSignedOut();
  }

  Map<AdminScreen, int> get _badges => {
        AdminScreen.accounts: _accounts.length,
        AdminScreen.devices: DeviceProblemsList.problems(_devices, _now).length,
      };

  Widget _content(bool narrow) {
    final Widget screen = switch (_screen) {
      AdminScreen.overview => OverviewScreen(
          counts: _counts,
          accounts: _accounts,
          now: _now,
          onNavigate: _navigate,
          onOpen: (a) => unawaited(_openAccount(a)),
          devices: _devices,
          onOpenDevice: _openDevice,
        ),
      AdminScreen.accounts => AccountsScreen(
          accounts: _accounts,
          now: _now,
          filter: _filter,
          onFilter: (f) => setState(() => _filter = f),
          onOpen: (a) => unawaited(_openAccount(a)),
          selected: _open?.patientUuid,
          narrow: narrow,
        ),
      AdminScreen.devices => DevicesScreen(
          accounts: _accounts,
          now: _now,
          onOpen: (a) => unawaited(_openAccount(a)),
          onNavigate: _navigate,
          devices: _devices,
          onOpenDevice: _openDevice,
        ),
    };
    // مفتاح على الشاشة: التبديل بيرجّع التمرير لفوق لوحده.
    return SingleChildScrollView(
      key: ValueKey(_screen),
      padding: EdgeInsets.fromLTRB(
        narrow ? F.s16 : F.s26,
        narrow ? F.s16 : F.s22,
        narrow ? F.s16 : F.s26,
        60,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                screen: _screen,
                now: _now,
                updatedAt: _updatedAt,
                refreshing: _refreshing,
                onRefresh: () => unawaited(refresh()),
              ),
              const SizedBox(height: F.s16),
              if (_error != null) ...[
                ErrorBanner(onRetry: () => unawaited(refresh())),
                const SizedBox(height: F.s8),
                Text(
                  _error!.message,
                  style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.mutedDark),
                ),
                const SizedBox(height: F.s16),
              ],
              if (_loading) DashboardSkeleton(narrow: narrow) else screen,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < phoneBreakpoint;
    final rail = !narrow && width < sidebarBreakpoint;
    final open = _open;
    final email = widget.service.currentEmail;

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
            devices: [for (final d in _devices) if (d.patientUuid == open.patientUuid) d],
          );

    if (narrow) {
      return Scaffold(
        backgroundColor: F.pageGround,
        appBar: AdminTopBar(email: email, onSignOut: () => unawaited(_signOut())),
        body: SidePanelOverlay(
          panel: panel,
          onDismiss: () => setState(() => _open = null),
          child: _content(true),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _screen.index,
          onDestinationSelected: (i) => _navigate(AdminScreen.values[i]),
          backgroundColor: F.cardGround,
          indicatorColor: F.greenTint,
          height: 64,
          destinations: [
            for (final s in AdminScreen.values)
              NavigationDestination(icon: Icon(s.icon), label: s.label),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: F.pageGround,
      body: SidePanelOverlay(
        panel: panel,
        onDismiss: () => setState(() => _open = null),
        // الشريط الأول في الصف = يمين في العربي = بداية السطر.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminSidebar(
              screen: _screen,
              onSelect: _navigate,
              badges: _badges,
              email: email,
              rail: rail,
              onSignOut: () => unawaited(_signOut()),
            ),
            Expanded(child: _content(false)),
          ],
        ),
      ),
    );
  }
}
