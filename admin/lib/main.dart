import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/admin_service.dart';
import 'data/supabase_admin_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AdminConfig.tryFromEnvironment();
  AdminService? service;
  if (config != null) {
    // نفس الباراميتر اللي التطبيق بيستعمله: `publishableKey`.
    final supabase = await Supabase.initialize(
      url: config.url,
      publishableKey: config.key,
    );
    service = SupabaseAdminService(supabase.client);
  }

  runApp(AdminApp(service: service));
}
