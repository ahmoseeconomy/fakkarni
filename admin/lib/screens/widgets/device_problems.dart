import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../data/device_codes.dart';
import '../../format/arabic_time.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'motion_widgets.dart';

/// الأجهزة اللي فيها مشكلة — **نفس القايمة على «نظرة عامة» و«صحة الأجهزة»
/// وجوّه لوحة الحساب**، فمفيش تلات تعريفات لـ«فيه مشكلة» تقدر تختلف.
///
/// كل صف: اسم المريض والجهاز، سطر آخر فحص (أو «ماوصلش منه حاجة من …»)،
/// وكل كود ككلمة عربية للأدمن ([deviceCodeLabel]). الجهاز الساكت بيظهر
/// حتى لو أكواده فاضية — الغياب هو الكود.
class DeviceProblemsList extends StatelessWidget {
  const DeviceProblemsList({
    required this.devices,
    required this.now,
    this.limit,
    this.onOpen,
    this.emptyText = 'مفيش جهاز فيه مشكلة دلوقتي — كل النبضات وصلت من غير أكواد.',
    super.key,
  });

  /// كل الأجهزة — الودجت هي اللي بتصفّي وبترتّب.
  final List<AdminDevice> devices;
  final DateTime now;
  final int? limit;
  final void Function(AdminDevice device)? onOpen;
  final String emptyText;

  /// الأجهزة اللي فيها مشكلة، الساكت الأول، وبعدين الأكتر أكواداً.
  static List<AdminDevice> problems(List<AdminDevice> devices, DateTime now) => [
        for (final d in devices)
          if (deviceHasProblem(d, now)) d,
      ]..sort((a, b) {
          final sa = deviceIsSilent(a, now) ? 0 : 1;
          final sb = deviceIsSilent(b, now) ? 0 : 1;
          if (sa != sb) return sa.compareTo(sb);
          return b.failingCodes.length.compareTo(a.failingCodes.length);
        });

  @override
  Widget build(BuildContext context) {
    final all = problems(devices, now);
    final shown = limit == null ? all : all.take(limit!).toList();
    if (all.isEmpty) return AdminPanel(text: emptyText);
    return Container(
      decoration: BoxDecoration(
        color: F.cardGround,
        border: Border.all(color: F.line),
        borderRadius: BorderRadius.circular(F.careRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, d) in shown.indexed)
            FadeSlideIn(
              delay: staggerDelay(context, i),
              child: DeviceProblemRow(
                device: d,
                now: now,
                last: i == shown.length - 1 && all.length <= shown.length,
                onTap: onOpen == null ? null : () => onOpen!(d),
              ),
            ),
          if (all.length > shown.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
              child: Text(
                'وكمان ${arabicNumber(all.length - shown.length)} جهاز — افتحهم من «صحة الأجهزة».',
                style: TextStyle(
                    fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.mutedDark),
              ),
            ),
        ],
      ),
    );
  }
}

/// صف جهاز واحد بأكواده.
class DeviceProblemRow extends StatelessWidget {
  const DeviceProblemRow({
    required this.device,
    required this.now,
    this.last = false,
    this.onTap,
    this.showName = true,
    super.key,
  });

  final AdminDevice device;
  final DateTime now;
  final bool last;
  final VoidCallback? onTap;

  /// جوّه لوحة الحساب الاسم مكتوب فوق — ما يتكرّرش.
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final silent = deviceIsSilent(device, now);
    final platform = switch (device.platform) {
      'ios' => 'آيفون',
      'android' => 'أندرويد',
      _ => 'جهاز',
    };
    final version = device.appVersion == null ? '' : ' ${device.appVersion}';
    return InkWell(
      onTap: onTap,
      hoverColor: F.greenTint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: F.lineSoft)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showName)
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: device.patientName.isEmpty ? 'من غير اسم' : device.patientName,
                      style: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careTextSize,
                        fontWeight: FontWeight.w600,
                        color: F.ink,
                      ),
                    ),
                    TextSpan(
                      text: ' — $platform$version',
                      style: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careMicroSize,
                        color: F.mutedDark,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                '$platform$version',
                style: TextStyle(
                    fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.mutedDark),
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  silent ? Icons.signal_wifi_off_rounded : Icons.schedule_rounded,
                  size: 14,
                  color: silent ? F.outOfRangeInk : F.mutedDark,
                ),
                const SizedBox(width: F.s6),
                Flexible(
                  child: Text(
                    deviceCheckedLine(device, now),
                    style: TextStyle(
                      fontFamily: F.bodyFamily,
                      fontSize: F.careMicroSize,
                      color: silent ? F.outOfRangeInk : F.mutedDark,
                      fontWeight: silent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
            if (device.failingCodes.isNotEmpty) ...[
              const SizedBox(height: F.s6),
              Wrap(
                spacing: F.s6,
                runSpacing: F.s6,
                children: [
                  for (final code in device.failingCodes)
                    _CodeChip(deviceCodeLabel(code, device: device, now: now)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: F.s8, vertical: 3),
        decoration: BoxDecoration(
          color: F.railGround,
          border: Border.all(color: F.gold, width: 1.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.ink),
        ),
      );
}
