/// «خرج من الدايرة» (0033) — قراية بس. الـSDK في
/// `supabase_circle_departures.dart`.
library;

import '../../domain/care/circle_departure.dart';

abstract interface class CircleDepartureRemote {
  /// آخر سطور الخروج عن المريض ده، الأحدث الأول. فاضية لو 0033 لسه
  /// ما اتشغّلتش.
  Future<List<CircleDeparture>> forPatient(String patientUuid);
}
