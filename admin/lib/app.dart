import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/admin_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'theme/tokens.dart';
import 'widgets_missing_config.dart';

/// جذر اللوحة — عربي RTL، ونهاري بس (مفيش وضع ليلي هنا: شاشة مكتب بتتفتح
/// في النهار، و`F.darkMode` بيفضل على قيمته الافتراضية).
class AdminApp extends StatefulWidget {
  const AdminApp({required this.service, super.key});

  /// null = الإعداد ناقص (`--dart-define`) — الشاشة بتقول ده بالنص.
  final AdminService? service;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _signedIn = widget.service?.currentEmail != null;
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return MaterialApp(
      title: 'لوحة فكرني',
      debugShowCheckedModeBanner: false,
      theme: F.light,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: service == null
          ? const MissingConfigScreen()
          : _signedIn
              ? DashboardScreen(
                  service: service,
                  onSignedOut: () => setState(() => _signedIn = false),
                )
              : LoginScreen(
                  service: service,
                  onSignedIn: () => setState(() => _signedIn = true),
                ),
    );
  }
}
