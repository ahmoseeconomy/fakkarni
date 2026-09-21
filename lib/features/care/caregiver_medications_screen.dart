import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/care/caregiver_remote.dart';
import 'caregiver_screen.dart' show CaregiverMedicationRow;
import 'caregiver_snapshot_holder.dart';
import 'caregiver_ui.dart';

/// «الأدوية» عند الابن — **تبويب لوحده في الدوك**.
///
/// كانت قسم في آخر «متابعة». القايمة دي **مرجع** («هو بياخد إيه») مش
/// **حالة** («هو كويس النهارده؟»)، وحطّها في آخر شاشة الحالة كان بيخلّي
/// الاتنين يتزاحموا: اللي جاي يطمن بيعدّي عليها، واللي جاي يشوف الدوا
/// بيعدّي على كل حاجة تانية الأول.
///
/// **وباب واحد للأوضة الواحدة** (نفس قاعدة «الملف الصحي» مش صف في
/// الإعدادات): القسم اتشال من «متابعة» خالص، مش اتنسخ.
///
/// للقراية بس — مفيش «عدّل» ولا «وقّف». أي زرار بيغيّر بيانات الأب مش
/// موجود هنا خالص، مش متعطّل.
class CaregiverMedicationsScreen extends StatefulWidget {
  const CaregiverMedicationsScreen({required this.holder, super.key});

  final CaregiverSnapshotHolder holder;

  @override
  State<CaregiverMedicationsScreen> createState() => _CaregiverMedicationsScreenState();
}

class _CaregiverMedicationsScreenState extends State<CaregiverMedicationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.holder.addListener(_changed);
  }

  @override
  void dispose() {
    widget.holder.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.holder.snapshot;
    final meds = snapshot?.medications ?? const <CaregiverMedication>[];
    return Scaffold(
      appBar: careAppBar('أدويته'),
      body: SafeArea(
        child: RefreshIndicator(
          color: F.green,
          onRefresh: widget.holder.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(F.carePad, F.careRowGap, F.carePad,
                F.carePad + MediaQuery.of(context).padding.bottom),
            children: [
              if (widget.holder.error case final error?)
                CarePanel(text: error, action: 'حاول تاني', onAction: widget.holder.refresh),
              if (snapshot == null)
                const CarePanel(text: 'لسه مفيش حاجة وصلت من موبايل والدك.')
              else if (meds.isEmpty)
                const CarePanel(text: 'مفيش أدوية متسجّلة على موبايل والدك لسه.')
              else
                // مفيش عنوان قسم هنا: الشريط العلوي بيقول «أدويته» خلاص،
                // وسطر تاني بنفس الكلمة زحمة على شاشة الهدف منها الكثافة.
                for (final m in meds) CaregiverMedicationRow(medication: m),
            ],
          ),
        ),
      ),
    );
  }
}
