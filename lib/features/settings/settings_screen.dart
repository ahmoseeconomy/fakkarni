import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../link/sign_in_screen.dart';
import '../routine/edit_routine_screen.dart';
import '../routine/ramadan_screen.dart';

/// «الإعدادات» — الحد الأدنى في D1: المداخل الموجودة فعلاً كصفوف.
/// الشكل الكامل (المخطط 33) في D2.9.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(F.gap),
      children: [
        const SectionHead('الإعدادات'),
        const SizedBox(height: F.s12),
        StreamBuilder<bool>(
          stream: Stream.fromFuture(
            services.routines.ramadanTimes(services.patientId).then((t) => t != null),
          ),
          builder: (context, snap) {
            final on = snap.data ?? false;
            return _Row(
              label: 'وضع رمضان',
              subtitle: on ? 'شغّال' : 'مقفول',
              attention: on,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RamadanScreen()),
              ),
            );
          },
        ),
        _Row(
          label: 'مواعيد يومك',
          subtitle: 'الصحيان، الأكل، النوم',
          onTap: () async {
            final routine = await services.routines.getRoutine(services.patientId);
            if (routine == null || !context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EditRoutineScreen(routine: routine),
              ),
            );
          },
        ),
        _Row(
          label: 'دائرة الرعاية',
          subtitle: 'اربط ابني',
          onTap: () => Navigator.of(context).push(
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

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.onTap,
    this.subtitle,
    this.attention = false,
  });

  final String label;
  final String? subtitle;
  final bool attention;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s10),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusCard),
            side: BorderSide(color: attention ? F.gold : F.line, width: attention ? 2 : 1),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusCard),
            child: Container(
              constraints: const BoxConstraints(minHeight: F.minTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: F.gap, vertical: F.s12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: F.minBodySize,
                            fontWeight: FontWeight.w700,
                            color: F.ink,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: F.minTextSize,
                              color: attention ? F.gold : F.muted,
                              fontWeight: attention ? FontWeight.w600 : FontWeight.w400,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Text(
                    'افتح',
                    style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.green),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
