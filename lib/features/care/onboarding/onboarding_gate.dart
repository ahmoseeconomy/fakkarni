import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/care/caregiver_preferences.dart';

/// **هل نسأل المتابع الأسئلة الأربعة؟** — قرار نقي، بعيد عن الشاشة.
///
/// تلات حالات، والتالتة هي اللي بتفرق:
///   * `ask` — مفيش صف، وما تخطّاش قبل كده.
///   * `skip` — عنده صف باسمه، أو تخطّى خلاص على الجهاز ده.
///   * `unknown` — **القراءة نفسها فشلت** (أوفلاين، أو جلسة راحت). ساعتها
///     ما بنسألش **وما بنسجّلش تخطّي**: الفشل مش إجابة، وتسجيله كان
///     هيخلّي عطل شبكة لحظي يسكّت السؤال للأبد.
enum OnboardingDecision { ask, skip, unknown }

/// المفتاح المحلي — **لكل مريض على حدة**: ابن بيتابع أبوه وأمه ممكن يكون
/// جاوب عن واحد وما جاوبش عن التاني.
String onboardingSeenKey(String patientUuid) => 'care.onboarding.seen.$patientUuid';

/// بيقرر من الصف اللي في السحابة ومن الذاكرة المحلية.
///
/// [load] بترمي؟ → [OnboardingDecision.unknown]، ونجرّب تاني المرة الجاية.
Future<OnboardingDecision> decideOnboarding({
  required String patientUuid,
  required CaregiverPreferencesService? preferences,
  required Future<bool> Function(String key) seenLocally,
}) async {
  if (preferences == null) return OnboardingDecision.skip;
  final CaregiverPreferences row;
  try {
    row = await preferences.load(patientUuid);
  } catch (_) {
    return OnboardingDecision.unknown;
  }
  // اسم موجود = جاوب خلاص. (الصف ممكن يبقى موجود بقيم افتراضية لو حفظ
  // خطوة وخرج — الاسم هو العلامة اللي المواصفة سمّتها.)
  if ((row.name?.trim().isNotEmpty) ?? false) return OnboardingDecision.skip;
  return await seenLocally(onboardingSeenKey(patientUuid))
      ? OnboardingDecision.skip
      : OnboardingDecision.ask;
}

/// القراءة والكتابة الحقيقية — `shared_preferences`، زي عدّاد المية
/// والوضع الليلي. **مش في الـschema**: ده اختيار على الموبايل ده.
Future<bool> onboardingSeen(String key) async =>
    (await SharedPreferences.getInstance()).getBool(key) ?? false;

Future<void> markOnboardingSeen(String patientUuid) async =>
    (await SharedPreferences.getInstance())
        .setBool(onboardingSeenKey(patientUuid), true);
