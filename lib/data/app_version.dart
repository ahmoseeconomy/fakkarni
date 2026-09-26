import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:package_info_plus/package_info_plus.dart';

import '../core/diagnostics.dart';
import 'health/health_heartbeat.dart' show appVersion;

/// **النسخة الحقيقية** — من الحزمة نفسها (`version:` في pubspec ← Info.plist
/// على iOS / build.gradle على أندرويد)، مش من `--dart-define=APP_VERSION`.
/// نسخة release اتبنت من غير التعريف ده كانت بتقول «النسخة dev» في
/// الإعدادات (آيفون، ٢٦ سبتمبر ٢٠٢٦). الملف الوحيد اللي بيستورد
/// `package_info_plus`.
abstract final class AppVersion {
  /// «2.0.0 (1)» بعد [load]؛ null قبلها أو لو القراية وقعت.
  static String? current;

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      current = versionLabel(version: info.version, build: info.buildNumber, debug: kDebugMode);
    } catch (e) {
      diag('Version: قراية النسخة وقعت ($e)');
    }
  }

  /// اللي بيتعرض: الحقيقي، وإلا التعريف، و«dev» في debug بس.
  static String get label => current ?? (appVersion != 'dev' ? appVersion : (kDebugMode ? 'dev' : ''));
}

/// «2.0.0 (88)» — والرقم التاني بس لو موجود. من غير نسخة: «dev» في debug،
/// وفاضي في release (عمره ما يتكتب «dev» لمريض).
String versionLabel({String? version, String? build, required bool debug}) {
  final v = version?.trim() ?? '';
  if (v.isEmpty) return debug ? 'dev' : '';
  final b = build?.trim() ?? '';
  return b.isEmpty ? v : '$v ($b)';
}
