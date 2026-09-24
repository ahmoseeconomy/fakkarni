import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../domain/billing/family_plan.dart';
import 'family_plan_screen.dart';

/// **البوابة الواحدة** للمزايا العائلية: مسموح → true؛ مش مسموح → شاشة
/// «اشتراك العيلة» وترجع false. من غير سحابة (مفيش خدمة) كل حاجة مسموحة.
/// الميزة المجانية بترجع true دايماً — مهما كانت الحالة.
Future<bool> ensureFamilyFeature(BuildContext context, AppFeature feature) async {
  final services = AppScope.maybeOf(context);
  final service = services?.subscription;
  if (services == null || service == null || service.allowed(feature)) return true;
  final patient = await services.routines.getPatient(services.patientId);
  if (!context.mounted) return false;
  var names = const <String>[];
  try {
    final uuid = patient?.uuid;
    if (uuid != null) {
      final followers = await services.careAdmin?.followersWithPermissions(uuid);
      names = [for (final f in followers ?? const []) f.displayName];
    }
  } catch (_) {}
  if (!context.mounted) return false;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => FamilyPlanScreen(
      service: service,
      patientName: patient?.name.trim().isNotEmpty == true ? patient!.name : 'أنا',
      coveredNames: names,
    ),
  ));
  return service.allowed(feature);
}
