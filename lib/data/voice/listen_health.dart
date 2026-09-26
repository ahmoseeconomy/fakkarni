import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';

/// **السماع ما بدأش** — آخر مرة المايك اتداس والمتعرّف ما اشتغلش لسبب مش
/// الإذن (الموبايل مفيهوش تعرّف، اللغة، جلسة الصوت، …). بيتسجّل هنا عشان
/// يطلع للوحة الأدمن مع النبضة (`HealthCode.listenUnavailable`) — **المريض
/// عمره ما يشوف السبب**: هو بيسمع «كمّل بإيدك» مرة، والزرار بيختفي.
///
/// السبب نفسه بيتكتب في سجل التشخيص (`Listen:`)؛ هنا الوقت بس، زي
/// `mediaProblemSince` — النبضة بتبعت أكواد مش كلام.
const listenProblemKey = 'voice.listenFailedAt';

Future<void> recordListenProblem(String reason, {DateTime? at}) async {
  diag('Listen: السماع ما بدأش — $reason');
  try {
    await (await SharedPreferences.getInstance())
        .setString(listenProblemKey, (at ?? DateTime.now()).toIso8601String());
  } catch (_) {}
}

/// سماع اشتغل — المشكلة خلصت.
Future<void> clearListenProblem() async {
  try {
    await (await SharedPreferences.getInstance()).remove(listenProblemKey);
  } catch (_) {}
}

Future<DateTime?> listenProblemSince() async {
  try {
    final s = (await SharedPreferences.getInstance()).getString(listenProblemKey);
    return s == null ? null : DateTime.tryParse(s);
  } catch (_) {
    return null;
  }
}
