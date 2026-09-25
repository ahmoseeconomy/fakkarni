import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/care/circle_departure.dart';
import 'circle_departures.dart';

/// أقصى عدد سطور بيتقري — الصفوف نفسها بتتمسح بعد ٣٠ يوم على السيرفر.
const departuresLimit = 20;

/// الاستعلام الواحد — المريض والمتابع بيقروا منه. جدول مش موجود (قبل 0033)
/// = مفيش سطور، مش عطل.
Future<List<CircleDeparture>> fetchDepartures(SupabaseClient supabase, String patientUuid) async {
  try {
    final rows = await supabase
        .from('circle_departures')
        .select('uuid, display_name, relation, role, left_at')
        .eq('patient_uuid', patientUuid)
        .order('left_at', ascending: false)
        .limit(departuresLimit);
    return [for (final r in rows) CircleDeparture.fromRow(r)];
  } on PostgrestException catch (e) {
    if (e.code == 'PGRST205' || e.code == '42P01') return const [];
    rethrow;
  }
}

class SupabaseCircleDepartures implements CircleDepartureRemote {
  SupabaseCircleDepartures(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<List<CircleDeparture>> forPatient(String patientUuid) =>
      fetchDepartures(_supabase, patientUuid);
}
