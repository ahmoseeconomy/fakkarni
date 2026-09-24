import 'package:flutter/material.dart';

import '../../domain/scheduling/day_routine.dart';
import 'add_medication_screen.dart';
import 'medication_draft.dart';

/// فورم «ضيف دوا» بتاع الأب في وضع المسوّدة — للممرض (المرحلة ب).
///
/// عايش هنا مش في `features/care/` عن قصد: جانب الابن **ما بيستوردش
/// الجدولة** (حارس `no_scheduling_imports_test`). الروتين الافتراضي هنا
/// **للمعاينة في الفورم بس** — الممرض بيختار مراسي («قبل الفطار») والمسوّدة
/// بتشيل المراسي زي ما هي، وموبايل المريض هو اللي بيحلّها بروتينه هو.
Future<MedicationDraft?> draftMedicationAsNurse(BuildContext context, {DateTime? today}) =>
    Navigator.of(context).push<MedicationDraft>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(routine: DayRoutine.fallback, today: today, draft: true),
      ),
    );
