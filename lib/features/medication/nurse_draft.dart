import 'package:flutter/material.dart';

import 'add_medication_screen.dart';
import 'medication_draft.dart';

/// فورم «ضيف دوا» بتاع الأب في وضع المسوّدة — للممرض (المرحلة ب).
///
/// عايش هنا مش في `features/care/` عن قصد: جانب الابن **ما بيستوردش
/// الجدولة** (حارس `no_scheduling_imports_test`). الممرض بيختار ساعات
/// والمسوّدة بتشيلها زي ما هي، وموبايل المريض هو اللي بيكتبها.
Future<MedicationDraft?> draftMedicationAsNurse(BuildContext context, {DateTime? today}) =>
    Navigator.of(context).push<MedicationDraft>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(today: today, draft: true),
      ),
    );
