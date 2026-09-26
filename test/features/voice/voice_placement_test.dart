// كل جملة في الكتالوج ليها مكان، وكل «ساعدني» على جملة موجودة، وكل جملة في
// المكان اللي معناها بيقوله. الخريطة تحت هي جدول المراجعة (٢٦ سبتمبر ٢٠٢٦):
// نقل جملة لمكان تاني = تعديل هنا بالعين، مش سهو.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/voice_catalog.dart';

/// الرقم → الملفات اللي بتقوله (زرار «ساعدني» أو بعد فعل أو لوحدها في
/// البداية). intro_01…05 بتتقال من `introSequence`، مش بالاسم.
const placement = <String, Set<String>>{
    'intro_yes': {'features/voice/voice_intro_screen.dart'},
    'intro_no': {'features/voice/voice_intro_screen.dart'},
    'help_routine': {'features/routine/edit_routine_screen.dart'},
    'help_routine_skip': {'features/onboarding/routine_onboarding_screen.dart'},
    'help_today': {'features/elder/elder_home_screen.dart', 'features/today/today_screen.dart'},
    'help_next_dose': {'features/elder/elder_home_screen.dart', 'features/today/today_screen.dart'},
    'help_confirm_done': {'features/reminder/reminder_screen.dart', 'features/today/dose_actions.dart'},
    // «كلّمني» بيعدّي من confirmGroup نفسها — الجملة بتتقال من dose_actions
    'help_later': {'features/today/dose_actions.dart'},
    'help_progress': {'features/adherence/adherence_card.dart'},
    'help_progress_missed': {'features/adherence/adherence_card.dart'},
    'help_tip': {'features/today/widgets/tip_card.dart'},
    'help_appointments': {'features/records/health_file_screen.dart', 'features/today/today_screen.dart'},
    'help_stock_low': {'features/today/widgets/refill_lines.dart'},
    'help_not_bought': {'features/medication/not_bought.dart'},
    'help_add_med': {'features/medication/add_sheet.dart'},
    'help_scan': {'features/medication/scan_package_screen.dart', 'features/scan/scan_prescription_screen.dart'},
    'help_review': {'features/scan/review_prescription_screen.dart'},
    'help_bought': {'features/scan/review_prescription_screen.dart'},
    'help_purpose': {'features/medication/add_medication_screen.dart'},
    'help_pattern': {'features/medication/add_medication_screen.dart'},
    'help_timing': {'features/medication/add_medication_screen.dart'},
    'help_start_date': {'features/medication/add_medication_screen.dart'},
    'help_alert_mode': {'features/medication/add_medication_screen.dart'},
    'help_photo': {'features/medication/med_photo.dart'},
    'help_instructions': {'features/medication/edit_medication_screen.dart'},
    'help_papers': {'features/records/health_file_screen.dart'},
    'help_doctor': {'features/doctor/doctor_page_screen.dart', 'features/records/health_file_screen.dart'},
    'help_vitals': {'features/health/vitals/vital_history_screen.dart', 'features/records/health_file_screen.dart'},
    'help_vitals_add': {'features/health/vitals/vital_entry_sheet.dart'},
    'help_family': {'features/settings/settings_screen.dart'},
    'help_invite_code': {'features/link/link_code_screen.dart'},
    'help_nurse': {'features/link/link_code_screen.dart'},
    'help_family_plan': {'features/billing/family_plan_screen.dart'},
    'help_emergency': {'features/emergency/emergency_card_screen.dart'},
    'help_settings_voice': {'features/voice/voice_settings_screen.dart'},
    'help_elder_mode': {'features/settings/settings_screen.dart'},
    'gen_no_medical': {'features/health/vitals/vital_history.dart', 'features/voice/command_flow.dart'},
    'gen_saved': {'features/health/vitals/vital_entry_sheet.dart', 'features/medication/add_medication_screen.dart', 'features/medication/edit_medication_screen.dart'},
    'gen_try_hands': {'features/medication/scan_package_screen.dart', 'features/scan/scan_prescription_screen.dart', 'features/voice/command_flow.dart'},
    'gen_goodbye': {'features/voice/voice_settings_screen.dart'},
    'lis_intro': {'features/voice/listen_button.dart'},
    'lis_listening': {'features/voice/listen_flow.dart', 'features/voice/command_flow.dart'},
    'lis_not_understood': {'features/voice/listen_flow.dart', 'features/voice/command_flow.dart'},
    'lis_confirm': {'features/voice/listen_flow.dart', 'features/voice/command_flow.dart'},
    'lis_mic_permission': {'features/voice/listen_flow.dart', 'features/voice/command_flow.dart'},
    'lis_mic_denied': {'features/voice/listen_flow.dart', 'features/voice/command_flow.dart'},
    // «كلّمني» — كل جمل الأوامر في الدورة الواحدة
    'cmd_hint': {'features/voice/command_flow.dart'},
    'cmd_thinking': {'features/voice/command_flow.dart'},
    'cmd_cancelled': {'features/voice/command_flow.dart'},
    'cmd_done': {'features/voice/command_flow.dart'},
    'cmd_limit': {'features/voice/command_flow.dart'},
    'onb_entry': {'features/entry/entry_screen.dart'},
    'onb_name': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_gender': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_age': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_wake': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_breakfast': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_lunch': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_dinner': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_sleep': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_routine_skip': {'features/onboarding/routine_onboarding_screen.dart'},
    'onb_routine_done': {'features/onboarding/routine_onboarding_screen.dart'},
};

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('voice_catalog.dart'))
      .toList();
  String rel(File f) => f.path.replaceFirst(RegExp(r'^lib/'), '');
  final src = {for (final f in files) rel(f): f.readAsStringSync()};
  final literal = RegExp(r"'((?:help|gen|intro|onb)_[a-z_0-9]+)'");

  test('كل رقم في الكتالوج بيتقال من مكان — ومفيش رقم من غير مكان', () {
    final unused = <String>[];
    for (final id in voiceLines.keys) {
      if (introSequence.contains(id)) continue;
      if (!src.values.any((s) => s.contains("'$id'"))) unused.add(id);
    }
    expect(unused, isEmpty, reason: 'جمل مسجّلة ومحدش بيقولها');
    expect(src.values.where((s) => s.contains('introSequence')), isNotEmpty, reason: 'المقدمة بتتقال');
    // المقدمة أول شاشة في تنزيلة جديدة (الجذر) — مش جوّه أسئلة البداية
    expect(src['app/root.dart'], contains('VoiceIntroScreen('));
    expect(src['features/onboarding/routine_onboarding_screen.dart'], isNot(contains('VoiceIntroScreen')));
  });

  test('كل «ساعدني» وكل speakLine على رقم موجود في الكتالوج', () {
    final missing = <String>[];
    for (final e in src.entries) {
      for (final m in literal.allMatches(e.value)) {
        if (!voiceLines.containsKey(m.group(1))) missing.add('${e.key}: ${m.group(1)}');
      }
    }
    expect(missing, isEmpty, reason: 'زرار بيدوّر على جملة مش موجودة = زرار ساكت');
  });

  test('كل جملة في مكانها بالظبط — زي جدول المراجعة', () {
    expect(placement.keys.toSet(), {...voiceLines.keys}.difference(introSequence.toSet()));
    for (final entry in placement.entries) {
      final actual = {
        for (final e in src.entries)
          if (e.value.contains("'${entry.key}'")) e.key,
      };
      expect(actual, entry.value, reason: '${entry.key} اتنقل أو اتضاف في مكان تاني');
    }
  });

  test('برّه البداية مفيش حاجة بتتقال لوحدها', () {
    final users = [
      for (final e in src.entries)
        if (e.value.contains('OnboardingVoice(')) e.key,
    ];
    expect(users.every((f) => f.startsWith('features/onboarding/') || f.startsWith('features/entry/')), isTrue,
        reason: users.join(', '));
    for (final e in src.entries) {
      if (e.key.startsWith('features/onboarding/') || e.key.startsWith('features/entry/')) continue;
      expect(e.value.contains("'onb_"), isFalse, reason: '${e.key} بيقول جملة بداية');
    }
  });
}
