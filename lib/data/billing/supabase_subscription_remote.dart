import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/diagnostics.dart';
import '../../domain/billing/family_plan.dart';
import 'subscription_remote.dart';

class SupabaseSubscriptionRemote implements SubscriptionRemote {
  SupabaseSubscriptionRemote(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<FamilySubscription?> load(String patientUuid) async {
    final rows = await _supabase
        .from('family_subscriptions')
        .select('status, trial_ends_at, expires_at, store, product_id, last_verified_at')
        .eq('patient_uuid', patientUuid)
        .limit(1);
    if (rows.isEmpty) return null;
    return FamilySubscription.fromJson(rows.first);
  }

  @override
  Future<VerifyOutcome> verify({
    required String patientUuid,
    required String store,
    required String productId,
    required String receipt,
  }) async {
    try {
      final res = await _supabase.functions.invoke('verify-purchase', body: {
        'patient_uuid': patientUuid,
        'store': store,
        'product_id': productId,
        'receipt': receipt,
      });
      final data = res.data;
      final status = data is Map ? data['status'] : null;
      return switch (status) {
        'active' => VerifyOutcome.active,
        'not_configured' => VerifyOutcome.notConfigured,
        'invalid' => VerifyOutcome.invalid,
        _ => VerifyOutcome.failed,
      };
    } catch (error) {
      diag('Billing: verify-purchase وقع ($error)');
      return VerifyOutcome.failed;
    }
  }
}
