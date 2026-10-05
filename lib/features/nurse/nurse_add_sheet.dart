import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/billing/family_plan.dart';
import '../billing/feature_gate.dart';
import '../health/vitals/vital_entry_sheet.dart';
import '../medication/add_medication_screen.dart';
import '../medication/add_sheet.dart' show addSheetTitle, addSheetLabels;
import '../medication/medication_draft.dart';
import '../medication/scan_package_screen.dart';
import '../scan/scan_prescription_screen.dart';
import 'nurse_actions.dart';
import 'nurse_controller.dart';

/// «ضيف» عند الممرض — نفس شيت المريض بنفس المداخل، بس كل مدخل بيطلّع
/// **مسوّدة** (الفورم في وضع المسوّدة / القراية بتسلّم السطور) وبيبعتها
/// لموبايل المريض. الصورة بتروح لـGemini من هنا زي ما بتروح عند المريض، ومن
/// غير ما تتخزّن. «صوّر تقرير تحليل» مش هنا: التقرير بيتحفظ بصورته على موبايل
/// المريض، والصورة ما بتعدّيش من الممرض.
Future<void> showNurseAddSheet(BuildContext context, NurseController c, {DateTime? today}) {
  final services = AppScope.of(context);
  final navigator = Navigator.of(context);

  Future<void> hand(MedicationDraft? d) async {
    if (d != null) await c.addFromDraft(d);
  }

  Future<void> open(Widget screen) async {
    navigator.pop();
    final d = await navigator.push<Object?>(MaterialPageRoute(builder: (_) => screen));
    if (d is MedicationDraft) await hand(d);
  }

  Future<void> openScan(Widget screen) async {
    navigator.pop();
    if (await ensureFamilyFeature(context, AppFeature.scans) && context.mounted) {
      final d = await navigator.push<Object?>(MaterialPageRoute(builder: (_) => screen));
      if (d is MedicationDraft) await hand(d);
    }
  }

  return FSheet.show<void>(
    context,
    title: addSheetTitle,
    children: [
      FPrimaryButton(
        key: const ValueKey('nurse-add-package'),
        label: addSheetLabels[0],
        onPressed: () => openScan(ScanPackageScreen(reader: services.packageReader, today: today, draft: true, voiceInput: false)),
      ),
      FSecondaryButton(
        key: const ValueKey('nurse-add-prescription'),
        label: addSheetLabels[1],
        onPressed: () => openScan(ScanPrescriptionScreen(
          voiceInput: false,
          reader: services.prescriptionReader,
          today: today,
          onDrafts: (drafts) async {
            for (final d in drafts) {
              await c.addFromDraft(d);
            }
          },
        )),
      ),
      FSecondaryButton(
        key: const ValueKey('nurse-add-manual'),
        label: addSheetLabels[2],
        onPressed: () => open(AddMedicationScreen(today: today, draft: true, voiceInput: false)),
      ),
      FSecondaryButton(
        key: const ValueKey('nurse-add-vital'),
        label: addSheetLabels[3],
        onPressed: () async {
          navigator.pop();
          if (!context.mounted) return;
          await showVitalEntrySheet(context, now: today, onSave: (entry, at) => c.addVital(entry, at));
        },
      ),
    ],
  );
}
