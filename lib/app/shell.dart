import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/fa_mark.dart';
import '../core/widgets/f_sheet.dart';
import '../core/widgets/primitives.dart';
import '../data/repositories/preferences_repository.dart';
import '../domain/scheduling/day_routine.dart';
import '../features/care/caregiver_health_screen.dart';
import '../features/care/caregiver_screen.dart';
import '../features/care/caregiver_snapshot_holder.dart';
import '../features/care/caregiver_settings_screen.dart';
import '../features/elder/elder_home_screen.dart';
import '../features/emergency/emergency_card_screen.dart';
import '../features/link/sign_in_screen.dart';
import '../features/medication/add_medication_screen.dart';
import '../features/medication/medications_screen.dart';
import '../features/health/glucose_screen.dart';
import '../features/health/scan_lab_screen.dart';
import '../features/records/manual_entry_screen.dart';
import '../features/scan/scan_prescription_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/today/today_screen.dart';
import 'app_scope.dart';

/// هيكل التطبيق: شريط علوي + أربع تبويبات + زرار «ضيف» في النص.
///
/// التبويبات: اليوم · الأدوية · العائلة · الإعدادات. «الملف» بتاع التصميم
/// مش موجود لأنه مالوش باك إند — مكانه «الإعدادات». زرار «طوارئ» فوق
/// (D3.4) بيفتح البطاقة بلمسة، بحدّ حبر مش أحمر.
///
/// كل زرار هنا بكلمة — حتى الـ«+». القاعدة: مفيش زرار أيقونة من غير كلمة.
/// الشريط العلوي علامة ف بس.
///
/// **نمط كبار السن** (D3.3، المخطط 18): تبويبتين بس — «الرئيسية» (كارت جرعة
/// واحد) و«الإعدادات» — ومن غير «ضيف». التبويب التاني هو الإعدادات عشان
/// ده الطريق الوحيد للخروج من النمط؛ «📞 اتصل» بتاع التصميم مش مبني.
class AppShell extends StatefulWidget {
  const AppShell({required this.routine, this.now, super.key});

  final DayRoutine routine;

  /// للاختبارات.
  final DateTime? now;

  static const tabs = ['اليوم', 'الأدوية', 'العائلة', 'الإعدادات'];
  static const elderTabs = ['الرئيسية', 'الإعدادات'];

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  int _elderTab = 0;
  Stream<DeviceSettings>? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings ??= AppScope.of(context).preferences.watch();
  }

  void _openAdd() {
    final services = AppScope.of(context);
    FSheet.show<void>(
      context,
      title: 'ضيف دوا',
      children: [
        FPrimaryButton(
          label: 'صوّر روشتة',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ScanPrescriptionScreen(
                  routine: widget.routine,
                  reader: services.prescriptionReader,
                ),
              ),
            );
          },
        ),
        FSecondaryButton(
          label: 'أكتبها بإيدي',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddMedicationScreen(routine: widget.routine),
              ),
            );
          },
        ),
        // سكر الدم وتقارير التحاليل (D3.6)
        FSecondaryButton(
          label: 'قيس السكر',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlucoseScreen()));
          },
        ),
        FSecondaryButton(
          label: 'صوّر تقرير تحليل',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ScanLabScreen(reader: services.labReader)),
            );
          },
        ),
        // الملف الصحي (D3.5) — مش دوا، فمش بيتجدول
        FSecondaryButton(
          label: 'سجّل زيارة أو تحليل أو أشعة',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ManualEntryScreen()),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DeviceSettings>(
        stream: _settings,
        builder: (context, snap) =>
            snap.data?.elderMode ?? false ? _buildElder(context) : _buildNormal(context),
      );

  AppBar _appBar() => AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: F.gap,
        actions: [
          // بطاقة الطوارئ بلمسة واحدة من أي تبويب — بحدّ حبر، **مش أحمر**:
          // الأحمر جوّه شاشتين الطوارئ بس.
          Padding(
            padding: const EdgeInsetsDirectional.only(end: F.gap),
            child: SizedBox(
              height: F.minTapTarget,
              child: OutlinedButton.icon(
                key: const ValueKey('emergency-shortcut'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const EmergencyCardScreen()),
                ),
                icon: const Icon(Icons.medical_information_outlined, size: 24),
                label: const Text('طوارئ'),
                style: OutlinedButton.styleFrom(
                  // الثيم بيدّي الزراير عرض كامل — في الشريط العلوي لأ
                  minimumSize: const Size(0, F.minTapTarget),
                  foregroundColor: F.ink,
                  side: const BorderSide(color: F.ink, width: 1.5),
                  textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
                ),
              ),
            ),
          ),
        ],
        // علامة ف بس. «الإعدادات» تبويب تحت — زرار فوق كان تكرار.
        title: Row(
          children: [
            // على بلاطة خضرا عشان العاجي يبان
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: F.greenDeep,
                borderRadius: BorderRadius.circular(F.radiusTile),
              ),
              alignment: Alignment.center,
              child: const FaMark(size: 24, breathing: true),
            ),
          ],
        ),
      );

  Widget _buildElder(BuildContext context) => Scaffold(
        appBar: _appBar(),
        body: IndexedStack(
          index: _elderTab,
          children: [
            ElderHomeScreen(routine: widget.routine, now: widget.now),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: _TabBar(
          labels: AppShell.elderTabs,
          icons: const [Icons.home_outlined, Icons.settings_outlined],
          gapForAdd: false,
          labelSize: F.elderTextSize,
          current: _elderTab,
          onSelect: (i) => setState(() => _elderTab = i),
        ),
      );

  Widget _buildNormal(BuildContext context) {
    final pages = [
      TodayScreen(routine: widget.routine, now: widget.now),
      const MedicationsScreen(),
      const _FamilyTab(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: _appBar(),
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: _AddButton(onPressed: _openAdd),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _TabBar(
        labels: AppShell.tabs,
        icons: const [
          Icons.today_outlined,
          Icons.medication_outlined,
          Icons.people_outline,
          Icons.settings_outlined,
        ],
        gapForAdd: true,
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
      ),
    );
  }
}

/// هيكل تطبيق الابن (D4): تبويبين بس — «متابعة» و«الإعدادات».
///
/// **الابن مش مريض**: مفيش «يومك» ولا «ضيف» ولا محرر جرعة ولا رمضان ولا
/// اختصار «طوارئ» (بيانات طوارئ الأب محلية على موبايل الأب، وهنا كانت هتفتح
/// على شاشة فاضية). المتابعة للقراية بس — أي زرار بيغيّر بيانات الأب مش
/// موجود هنا خالص (`caregiver_shell_test` بيمشي على الشجرة ويثبت ده).
class CaregiverShell extends StatefulWidget {
  const CaregiverShell({required this.onNotLinked, this.now, super.key});

  /// السحابة قالت «مفيش مريض مربوط» → الجذر يرجّع لشاشة البداية.
  final VoidCallback onNotLinked;

  /// للاختبارات.
  final DateTime? now;

  static const tabs = ['متابعة', 'الملف الصحي', 'الإعدادات'];

  /// تبويبات البيانات — السؤال الدوري شغّال وواحد منهم ظاهر.
  static const dataTabs = {0, 1};

  @override
  State<CaregiverShell> createState() => _CaregiverShellState();
}

class _CaregiverShellState extends State<CaregiverShell> {
  int _tab = 0;

  /// صورة واحدة للتبويبين (D5.2): سحبة واحدة لكل تحديث، مش سحبة لكل تبويب.
  CaregiverSnapshotHolder? _holder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_holder != null) return;
    final remote = AppScope.of(context).caregiver;
    if (remote == null) {
      // جلسة من غير سحابة مش ممكنة عملياً — بس لو حصلت، مفيش حاجة تتتابع
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onNotLinked());
      return;
    }
    _holder = CaregiverSnapshotHolder(remote, onNotLinked: widget.onNotLinked)
      ..setActive(CaregiverShell.dataTabs.contains(_tab));
  }

  void _select(int i) {
    setState(() => _tab = i);
    final holder = _holder;
    if (holder == null) return;
    final data = CaregiverShell.dataTabs.contains(i);
    // دخول تبويب بيانات = صورة طازة على طول، حتى لو جاي من التبويب التاني
    if (data && holder.active) holder.refresh();
    holder.setActive(data);
  }

  @override
  void dispose() {
    _holder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final holder = _holder;
    if (holder == null) return const Scaffold();
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          CaregiverScreen(
            remote: holder.remote,
            now: widget.now,
            onNotLinked: widget.onNotLinked,
            holder: holder,
          ),
          CaregiverHealthScreen(holder: holder),
          const Scaffold(body: SafeArea(child: CaregiverSettingsScreen())),
        ],
      ),
      bottomNavigationBar: _TabBar(
        labels: CaregiverShell.tabs,
        icons: const [Icons.visibility_outlined, Icons.folder_outlined, Icons.settings_outlined],
        gapForAdd: false,
        current: _tab,
        onSelect: _select,
      ),
    );
  }
}

/// تبويب «العائلة» — باب الهوية الوحيد لسه «اربط ابني». شاشة الدخول
/// ما بتتركّبش هنا عند الفتح (حارس root_test): بتتفتح بالدوسة وبس.
class _FamilyTab extends StatelessWidget {
  const _FamilyTab();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(F.gap),
      children: [
        const SectionHead('العائلة'),
        const SizedBox(height: F.s8),
        const Text(
          'اربط ابنك أو بنتك عشان لو نسيت جرعة، التطبيق يبلّغهم.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(
          label: 'اربط ابني',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SignInScreen(
                auth: services.auth,
                caregiver: services.caregiver,
                push: services.push,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// «+ ضيف» — أخضر، مش كورال. الذهبي هو الوحيد اللي بيبرز.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.primaryButtonHeight,
        child: FloatingActionButton.extended(
          onPressed: onPressed,
          backgroundColor: F.green,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusLarge)),
          icon: const Icon(Icons.add, size: 28),
          label: const Text(
            'ضيف',
            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
          ),
        ),
      );
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.labels,
    required this.icons,
    required this.gapForAdd,
    required this.current,
    required this.onSelect,
    this.labelSize = F.minTextSize,
  });

  /// نمط كبار السن: ٢٤ — حتى في شريط التبويبات.
  final double labelSize;

  final List<String> labels;
  final List<IconData> icons;

  /// فجوة في النص لزرار «ضيف» — نمط كبار السن مالوش «ضيف».
  final bool gapForAdd;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: F.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                // فجوة في النص لزرار «ضيف»
                if (gapForAdd && i == 2) const SizedBox(width: 108),
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icons[i], size: 26, color: i == current ? F.green : F.mutedLight),
                        const SizedBox(height: F.s4),
                        // خط النظام الكبير كان بيلف «الإعدادات» سطرين ويفيض من
                        // الشريط — سطر واحد بيصغر بس لو ما دخلش
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                          labels[i],
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: labelSize,
                            fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                            color: i == current ? F.green : F.muted,
                          ),
                        ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
