import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import '../health/glucose_screen.dart';
import '../health/scan_lab_screen.dart';
import '../records/manual_entry_screen.dart';
import '../scan/scan_prescription_screen.dart';
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

  return FSheet.show<void>(
    context,
    title: addSheetTitle,
    children: [
      // **الصورة الأول** (طلب المالك): العلبة في إيده دلوقتي، وده
      // أقصر طريق بين حاجة موجودة قدّامه وحاجة متسجّلة.
      FPrimaryButton(
        label: addSheetLabels[0],
        onPressed: () =>
            open(ScanPackageScreen(routine: routine, reader: services.packageReader)),
      ),
      FSecondaryButton(
        label: addSheetLabels[1],
        onPressed: () => open(ScanPrescriptionScreen(routine: routine, reader: services.prescriptionReader)),
      ),
      FSecondaryButton(
        label: addSheetLabels[2],
        onPressed: () => open(AddMedicationScreen(routine: routine)),
      ),
      // سكر الدم وتقارير التحاليل (D3.6)
      FSecondaryButton(label: addSheetLabels[3], onPressed: () => open(const GlucoseScreen())),
      FSecondaryButton(
        label: addSheetLabels[4],
        onPressed: () => open(ScanLabScreen(reader: services.labReader)),
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
  'قيس السكر',
  'صوّر تقرير تحليل',
  'سجّل زيارة أو تحليل أو أشعة',
];
