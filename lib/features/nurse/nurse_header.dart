import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../care/caregiver_snapshot_holder.dart';
import 'nurse_emergency_screen.dart';

/// **«بتتابع: {اسم المريض}» — ثابتة فوق كل شاشة في تطبيق الممرض.**
///
/// الممرض ممكن يبقى مسؤول عن أكتر من حد؛ الغلط الوحيد اللي ما ينفعش يحصل
/// هنا إنه يأكّد جرعة لمريض وهو فاكره التاني. فالاسم مكتوب دايماً، ولما
/// يبقى فيه أكتر من مريض، «غيّر» جنبه. «طوارئ» جنبه: كارت المريض الأحمر.
class NurseHeader extends StatelessWidget implements PreferredSizeWidget {
  const NurseHeader({required this.holder, super.key});

  final CaregiverSnapshotHolder holder;

  /// سطر واحد وبس — عنوان أي شاشة مفتوحة بيبقى أول حاجة في جسمها، مش
  /// هنا: عنوان تحت الاسم كان بيفيض على تكبير الخط.
  @override
  Size get preferredSize => const Size.fromHeight(F.minTapTarget + F.s8 * 2);

  Future<void> _switch(BuildContext context) async {
    final uuid = await FSheet.show<String>(
      context,
      title: 'بتتابع مين؟',
      children: [
        for (final p in holder.patients) ...[
          FSecondaryButton(
            key: ValueKey('nurse-patient-${p.uuid}'),
            label: p.uuid == holder.selectedPatientUuid ? '${p.name} ✓' : p.name,
            onPressed: () => Navigator.of(context).pop(p.uuid),
          ),
          const SizedBox(height: F.s8),
        ],
      ],
    );
    if (uuid != null) await holder.selectPatient(uuid);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: holder,
        builder: (context, _) {
          final name = holder.snapshot?.patient.name ??
              holder.patients.where((p) => p.uuid == holder.selectedPatientUuid).firstOrNull?.name;
          final canSwitch = holder.patients.length > 1;
          return Material(
            color: F.pageGround,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.s8),
                child: Row(
                      children: [
                        if (Navigator.of(context).canPop())
                          TextButton.icon(
                            key: const ValueKey('nurse-back'),
                            onPressed: () => Navigator.of(context).maybePop(),
                            style: TextButton.styleFrom(minimumSize: const Size(0, F.minTapTarget)),
                            icon: Icon(Icons.arrow_forward, color: F.green),
                            label: Text('رجوع',
                                style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.green)),
                          ),
                        Expanded(
                          child: Text(
                            name == null ? 'بتتابع…' : 'بتتابع: $name',
                            key: const ValueKey('nurse-following'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: F.subtitleSize,
                              fontWeight: FontWeight.w800,
                              color: F.green,
                            ),
                          ),
                        ),
                        if (canSwitch)
                          TextButton(
                            key: const ValueKey('nurse-switch'),
                            onPressed: () => _switch(context),
                            style: TextButton.styleFrom(minimumSize: const Size(0, F.minTapTarget)),
                            child: Text('غيّر',
                                style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.green)),
                          ),
                        const SizedBox(width: F.s4),
                        OutlinedButton.icon(
                          key: const ValueKey('nurse-emergency'),
                          onPressed: holder.snapshot == null
                              ? null
                              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => NurseEmergencyScreen(holder: holder),
                                  )),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, F.minTapTarget),
                            side: BorderSide(color: F.ink),
                            foregroundColor: F.ink,
                          ),
                          icon: const Icon(Icons.emergency_outlined, size: 20),
                          label: Text('طوارئ', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
              ),
            ),
          );
        },
      );
}

/// عنوان شاشة مفتوحة فوق تبويب — أول سطر في جسمها، تحت «بتتابع».
class NurseScreenTitle extends StatelessWidget {
  const NurseScreenTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s12),
        child: Text(
          text,
          style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, fontWeight: FontWeight.w700, color: F.ink),
        ),
      );
}
