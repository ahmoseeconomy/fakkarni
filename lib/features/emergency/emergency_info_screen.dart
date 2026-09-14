import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'emergency_edit_screen.dart';
import 'emergency_widgets.dart';

/// «معلومات الطوارئ» (المخطط ١٩) — أرضية حمرا `F.redDeep`.
///
/// ده وبطاقة الطوارئ **المكانين الوحيدين** في التطبيق اللي فيهم أحمر.
///
/// كل حقل بيقول اللي اتكتب بالظبط، أو «لسه ما اتملاش». الأدوية الحالية من
/// medications مباشرة. «ملاحظة للمسعف» بتاعة التصميم مش مبنية (مش في
/// الخطة). الزرار الأساسي الوحيد الإسعاف، وقبله تأكيد صريح.
class EmergencyInfoScreen extends StatefulWidget {
  const EmergencyInfoScreen({super.key});

  @override
  State<EmergencyInfoScreen> createState() => _EmergencyInfoScreenState();
}

class _EmergencyInfoScreenState extends State<EmergencyInfoScreen>
    with EmergencyData {
  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
      fontSize: F.minTextSize,
      fontWeight: FontWeight.w600,
      color: F.onRedMuted,
    );
    const value = TextStyle(
      fontSize: F.subtitleSize,
      fontWeight: FontWeight.w700,
      color: F.onRed,
      height: 1.4,
    );
    const empty = TextStyle(
      fontSize: F.minBodySize,
      fontWeight: FontWeight.w500,
      color: F.onRedMuted,
      height: 1.4,
    );

    return Scaffold(
      backgroundColor: F.redDeep,
      appBar: AppBar(
        backgroundColor: F.redDeep,
        foregroundColor: F.onRed,
        automaticallyImplyLeading: false,
        toolbarHeight: 64,
        titleSpacing: F.gap,
        title: const Text(
          'معلومات الطوارئ',
          style: TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.screenTitleSize,
            fontWeight: FontWeight.w700,
            color: F.onRed,
          ),
        ),
        actions: [
          _BarButton(
            label: 'عدّل',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EmergencyEditScreen(),
              ),
            ),
          ),
          _BarButton(
            label: 'إغلاق',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: F.s8),
        ],
      ),
      body: Builder(
        builder: (context) {
          final data = snapshot;
          if (data == null) return const SizedBox.shrink();
          final info = data.info;
          return ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // فصيلة الدم على بلاطة بيضا — أكبر رقم في الشاشة
                  Container(
                    width: 120,
                    constraints: const BoxConstraints(minHeight: 120),
                    padding: const EdgeInsets.all(F.s12),
                    decoration: BoxDecoration(
                      color: F.onRed,
                      borderRadius: BorderRadius.circular(F.radiusLarge),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'فصيلة الدم',
                          style: TextStyle(
                            fontSize: F.minTextSize,
                            color: F.mutedDark,
                          ),
                        ),
                        FieldValue(
                          info.bloodType,
                          style: const TextStyle(
                            fontSize: F.display2,
                            fontWeight: FontWeight.w700,
                            color: F.redDeep,
                            fontFamily: F.monoFamily,
                            fontFamilyFallback: F.monoFallback,
                          ),
                          emptyStyle: const TextStyle(
                            fontSize: F.minTextSize,
                            color: F.mutedDark,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(
                    child: _Panel(
                      dark: true,
                      label: 'الحساسية',
                      child: FieldValue(
                        info.allergies,
                        style: value,
                        emptyStyle: empty,
                      ),
                    ),
                  ),
                ],
              ),
              _Panel(
                label: 'الاسم والسن',
                child: FieldValue(
                  data.nameAndAge,
                  style: value,
                  emptyStyle: empty,
                ),
              ),
              _Panel(
                label: 'الأمراض المزمنة',
                child: FieldValue(
                  info.chronicConditions,
                  style: value,
                  emptyStyle: empty,
                ),
              ),
              _Panel(
                label: 'الأدوية الحالية',
                child: data.medications.isEmpty
                    ? const Text('مفيش أدوية متسجّلة', style: empty)
                    : Text(
                        data.medicationsLine,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                        style: value.copyWith(
                          fontFamily: F.monoFamily,
                          fontFamilyFallback: F.monoFallback,
                        ),
                      ),
              ),
              _Panel(
                dark: true,
                label: 'جهات الاتصال',
                child: info.contacts.isEmpty
                    ? const Text(notFilled, style: empty)
                    : Column(
                        children: [
                          for (final c in info.contacts) ContactRow(contact: c),
                        ],
                      ),
              ),
              const SizedBox(height: F.s8),
              const Text('بياناتك دي على الموبايل ده بس.', style: label),
            ],
          );
        },
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s12),
          child: AmbulanceButton(),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.label, required this.child, this.dark = false});

  final String label;
  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: F.s10),
    padding: const EdgeInsets.all(F.s14),
    decoration: BoxDecoration(
      color: dark ? F.redPanel : F.onRed.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(F.radiusCard),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: F.minTextSize,
            fontWeight: FontWeight.w600,
            color: F.onRedMuted,
          ),
        ),
        const SizedBox(height: F.s4),
        child,
      ],
    ),
  );
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: F.minTapTarget,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: F.onRed,
        textStyle: const TextStyle(
          fontSize: F.minBodySize,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(label),
    ),
  );
}
