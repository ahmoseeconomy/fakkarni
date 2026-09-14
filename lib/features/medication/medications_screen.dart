import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/medication_repository.dart';
import '../today/widgets/medication_list.dart';
import 'edit_medication_screen.dart';

/// تبويب «الأدوية» — الحد الأدنى في D1: نفس قايمة «أدويتك».
/// التجميع بالمرساة (المخطط 09) في D2.10.
class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return StreamBuilder<List<MedicationSummary>>(
      stream: services.medications.watchActiveSummaries(services.patientId),
      builder: (context, snap) {
        final items = snap.data ?? const <MedicationSummary>[];
        return ListView(
          padding: const EdgeInsets.all(F.gap),
          children: [
            if (snap.hasData && items.isEmpty)
              const Text(
                'لسه مفيش أدوية. دوس «ضيف» تحت.',
                style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.6),
              )
            else
              MedicationList(
                items: items,
                onTap: (m) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EditMedicationScreen(medicationId: m.medication.id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
