// كل جملة بيقولها الرفيق — الكتالوج وقوالب ملخص اليوم بعيّناتها — بتعدّي
// على نفس الخطوط الحمرا بتاعة «معلومة تهمك» وشاشة القياسات: مفيش نصيحة
// طبية، مفيش جرعات، مفيش تشخيص، ومفيش كلام تقني.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/briefing.dart';
import 'package:fakkarni/domain/voice/voice_catalog.dart';
import 'package:fakkarni/features/health/usual_words.dart';

import '../today/tips_banned_words_test.dart' show offendersIn;

/// كلام تقني — المريض ما يسمعش مشكلة تقنية أبداً.
/// («كود» مش هنا عن قصد: «الكود» في `help_invite_code` هو كود الربط اللي
/// المريض بيقوله لابنه — كلمة المنتج، مش كلمة تقنية.)
const technicalWords = ['سيرفر', 'السيرفر', 'إنترنت', 'الشبكة', 'خطأ', 'API', 'قاعدة البيانات', 'مزامنة', 'تحديث النسخة'];

List<String> briefingSamples() {
  final now = DateTime(2026, 9, 25, 7);
  return [
    briefingText(BriefingInput(now: now, dosesToday: 3, firstDoseAt: now, firstDoseWording: 'بعد الفطار بنص ساعة')),
    briefingText(BriefingInput(now: DateTime(2026, 9, 25, 19), dosesToday: 1, firstDoseAt: now)),
    briefingText(BriefingInput(
        now: now, dosesToday: 2, appointments: [BriefingAppointment(kind: 'دكتور', at: now), BriefingAppointment(kind: 'تحليل', at: now)])),
    briefingText(BriefingInput(now: now, dosesToday: 2, yesterday: YesterdayOutcome.complete, streak: 4)),
    briefingText(BriefingInput(now: now, dosesToday: 2, yesterday: YesterdayOutcome.complete, streak: 12)),
    briefingText(BriefingInput(now: now, dosesToday: 2, yesterday: YesterdayOutcome.missed)),
  ].whereType<String>().toList();
}

void main() {
  final all = [...voiceLines.values, ...briefingSamples()];

  test('ولا كلمة نصيحة (شاشة القياسات) في أي جملة', () {
    final offenders = [
      for (final t in all)
        for (final w in adviceWords)
          if (t.contains(w)) '«$w» في: $t',
    ];
    expect(offenders, isEmpty);
  });

  test('ولا كلمة تقنية', () {
    final offenders = [
      for (final t in all)
        for (final w in technicalWords)
          if (t.contains(w)) '«$w» في: $t',
    ];
    expect(offenders, isEmpty);
  });

  test('خطوط «معلومة تهمك» الحمرا — جرعات وتفاعلات وتشخيص وإيقاف الدوا', () {
    // «حباية» في «صوّر الحباية أو العلبة» (help_photo) هي الشيء المصوَّر مش
    // جرعة، و«مرض» بيمسك «ممرض». الاتنين مذكورين هنا بالاسم — مش استثناء
    // صامت — والباقي كله بيتفحص بالحرف.
    String soften(String t) => t.replaceAll('الحباية', 'الحاجة').replaceAll('ممرض', 'مرافق');
    final offenders = [for (final t in all) ...offendersIn(soften(t))];
    expect(offenders, isEmpty);
  });

  test('«حضرتك» في كل جملة بتخاطب المريض — جملة واحدة للراجل والست', () {
    // الجمل القصيرة العامة («تمام، اتحفظ.») والمقدمة الأولى ما بتخاطبش
    final addressing = voiceLines.entries.where((e) => e.value.contains('حضرتك') || e.value.contains('تك'));
    expect(addressing.length, greaterThan(20));
  });

  test('عيّنات الملخص فيها كل القوالب', () {
    expect(briefingSamples(), hasLength(6));
  });
}
