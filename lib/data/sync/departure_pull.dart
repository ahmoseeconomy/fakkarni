import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../domain/care/circle_departure.dart';
import '../care/circle_departures.dart';
import '../repositories/routine_repository.dart';
import 'medication_change_pull.dart';

/// على موبايل المريض: سطور «خرج من الدايرة» الجديدة بتنزل على «يومك» —
/// نفس كارت «سارة ضافت دوا» ونفس «تمام».
///
/// مجاملة زي باقي السحبات: بتسجّل وما بترميش.
class CircleDeparturePuller {
  CircleDeparturePuller({required this.remote, required this.routines, required this.patientId});

  final CircleDepartureRemote remote;
  final RoutineRepository routines;
  final int patientId;

  static const seenKey = 'circle.departuresSeen';

  /// بيرجّع عدد السطور الجديدة.
  Future<int> pull() async {
    try {
      final patient = await routines.getPatient(patientId);
      if (patient == null) return 0;
      final rows = await remote.forPatient(patient.uuid);
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(seenKey) ?? const []).toSet();
      final fresh = [for (final d in rows) if (!seen.contains(d.uuid)) d];
      // المحفوظ = اللي لسه على السيرفر بس، فالقايمة ما بتكبرش للأبد
      await prefs.setStringList(seenKey, [for (final d in rows) d.uuid]);
      if (fresh.isEmpty) return 0;
      await MedicationChangePuller.remember([for (final d in fresh) departureLine(d)]);
      return fresh.length;
    } catch (error) {
      diag('Circle: سحب «خرج من الدايرة» وقع ($error)');
      return 0;
    }
  }
}
