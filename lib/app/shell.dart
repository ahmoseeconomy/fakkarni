import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/fa_mark.dart';
import '../core/widgets/f_sheet.dart';
import '../core/widgets/primitives.dart';
import '../domain/scheduling/day_routine.dart';
import '../features/link/sign_in_screen.dart';
import '../features/medication/add_medication_screen.dart';
import '../features/medication/medications_screen.dart';
import '../features/scan/scan_prescription_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/today/today_screen.dart';
import 'app_scope.dart';

/// هيكل التطبيق: شريط علوي + أربع تبويبات + زرار «ضيف» في النص.
///
/// التبويبات: اليوم · الأدوية · العائلة · الإعدادات. «الملف» بتاع التصميم
/// مش موجود لأنه مالوش باك إند — مكانه «الإعدادات». ومفيش شريحة «طوارئ»
/// حمرا: الأحمر للطوارئ، ومفيش طوارئ دلوقتي.
///
/// كل زرار هنا بكلمة — حتى الـ«+». القاعدة: مفيش زرار أيقونة من غير كلمة.
/// الشريط العلوي علامة ف بس.
class AppShell extends StatefulWidget {
  const AppShell({required this.routine, this.now, super.key});

  final DayRoutine routine;

  /// للاختبارات.
  final DateTime? now;

  static const tabs = ['اليوم', 'الأدوية', 'العائلة', 'الإعدادات'];

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(routine: widget.routine, now: widget.now),
      const MedicationsScreen(),
      const _FamilyTab(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: F.gap,
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
      ),
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: _AddButton(onPressed: _openAdd),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _TabBar(
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
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
  const _TabBar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  static const _icons = [
    Icons.today_outlined,
    Icons.medication_outlined,
    Icons.people_outline,
    Icons.settings_outlined,
  ];

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
              for (var i = 0; i < AppShell.tabs.length; i++) ...[
                // فجوة في النص لزرار «ضيف»
                if (i == 2) const SizedBox(width: 108),
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_icons[i], size: 26, color: i == current ? F.green : F.mutedLight),
                        const SizedBox(height: F.s4),
                        Text(
                          AppShell.tabs[i],
                          style: TextStyle(
                            fontSize: F.minTextSize,
                            fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                            color: i == current ? F.green : F.muted,
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
