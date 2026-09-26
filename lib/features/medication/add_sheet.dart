import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/billing/family_plan.dart';
import '../../domain/scheduling/day_routine.dart';
import '../billing/feature_gate.dart';
import '../health/vitals/vital_entry_sheet.dart';
import '../health/scan_lab_screen.dart';
import '../records/manual_entry_screen.dart';
import '../scan/scan_prescription_screen.dart';
import '../voice/help_button.dart';
import 'add_medication_screen.dart';
import 'scan_package_screen.dart';

/// شيت «ضيف دوا» — **معرّف هنا مرة واحدة**، وبيتفتح من مكانين: «+ ضيف» في
/// الدوك، وكارت «ضيف دوا» فوق جدول الأدوية. مدخل جديد هنا بيظهر في الاتنين
/// لوحده؛ نسخة تانية من الشيت كانت هتتفرّق عن دي مع أول تعديل.
///
/// `test/features/medication/add_sheet_test.dart` بيقرا `lib/` وبيقع لو
/// الشيت اتعرّف في مكان تاني.
Future<void> showAddSheet(BuildContext context, {required DayRoutine routine}) {
  final services = AppScope.of(context);
  final navigator = Navigator.of(context);
  void open(Widget screen) {
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// القراية بالكاميرا ميزة عائلية — الشيت بيتقفل، والبوابة بتقرر.
  Future<void> openScan(Widget screen) async {
    navigator.pop();
    if (await ensureFamilyFeature(context, AppFeature.scans) && context.mounted) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
    }
  }

  return FSheet.show<void>(
    context,
    title: addSheetTitle,
    children: [
      // «ممكن تكتب اسمه، أو تصوّر العلبة أو الروشتة» — بتوصف الشيت ده
      const Align(alignment: AlignmentDirectional.centerEnd, child: HelpButton('help_add_med')),
      // **الصورة الأول** (طلب المالك): العلبة في إيده دلوقتي، وده
      // أقصر طريق بين حاجة موجودة قدّامه وحاجة متسجّلة.
      FPrimaryButton(
        label: addSheetLabels[0],
        onPressed: () =>
            openScan(ScanPackageScreen(routine: routine, reader: services.packageReader)),
      ),
      FSecondaryButton(
        label: addSheetLabels[1],
        onPressed: () => openScan(ScanPrescriptionScreen(routine: routine, reader: services.prescriptionReader)),
      ),
      FSecondaryButton(
        label: addSheetLabels[2],
        onPressed: () => open(AddMedicationScreen(routine: routine)),
      ),
      // القياسات (٢٥ سبتمبر ٢٠٢٦): ضغط/نبض/وزن/أكسجين/حرارة — والسكر شريحة
      // جوّه الورقة بتفتح شاشته زي ما هي. التقارير لوحدها تحت.
      FSecondaryButton(
        key: const ValueKey('add-vital'),
        label: addSheetLabels[3],
        onPressed: () {
          navigator.pop();
          if (context.mounted) showVitalEntrySheet(context);
        },
      ),
      FSecondaryButton(
        label: addSheetLabels[4],
        onPressed: () => openScan(ScanLabScreen(reader: services.labReader)),
      ),
      // الملف الصحي (D3.5) — مش دوا، فمش بيتجدول
      FSecondaryButton(label: addSheetLabels[5], onPressed: () => open(const ManualEntryScreen())),
    ],
  );
}

const addSheetTitle = 'ضيف دوا';

/// مداخل الشيت بالترتيب — الاختبارات بتقارن الدوك والكارت على القايمة دي.
const addSheetLabels = [
  'صوّر العلبة أو الشريط',
  'صوّر روشتة',
  'أكتبها بإيدي',
  'سجّل قياس',
  'صوّر تقرير تحليل',
  'سجّل زيارة أو تحليل أو أشعة',
];
