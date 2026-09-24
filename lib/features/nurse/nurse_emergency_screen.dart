import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../care/caregiver_snapshot_holder.dart';
import '../emergency/emergency_facts_card.dart';
import 'nurse_header.dart';

/// كارت الطوارئ بتاع المريض — نفس الكارت اللي عند الابن (الأحمر مكانه
/// `features/emergency/`). **مفيش أرقام تليفونات**: مش في السحابة أصلاً
/// (٠٠١٢)، وده مكتوب على الشاشة.
class NurseEmergencyScreen extends StatelessWidget {
  const NurseEmergencyScreen({required this.holder, super.key});

  final CaregiverSnapshotHolder holder;

  @override
  Widget build(BuildContext context) {
    final e = holder.snapshot?.emergency;
    return Scaffold(
      appBar: NurseHeader(holder: holder),
      body: ListView(
        padding: const EdgeInsets.all(F.gap),
        children: [
          const NurseScreenTitle('بطاقة الطوارئ'),
          EmergencyFactsCard(bloodType: e?.bloodType, allergies: e?.allergies, chronicConditions: e?.chronicConditions),
          const SizedBox(height: F.gap),
          Text(
            'أرقام التليفونات بتفضل على موبايل المريض بس.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
          ),
        ],
      ),
    );
  }
}
