import '../../core/format/arabic_time.dart';
import '../../data/services/appointment_card.dart';
import '../../domain/adherence/weekly_summary.dart';
import '../../domain/health/doctor_match.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/voice/voice_time.dart';
import 'command_parser.dart' show AppointmentKind, MedInfoAspect;

/// **ردود «كلّمني» من بياناته** (E1، طلب المدير ٤ أكتوبر ٢٠٢٦) — دارت نقية.
///
/// كل جملة هنا بتقول **اللي متسجّل** وبس: لو مش متسجّل بنقول كده
/// («مش متسجّل عندي»)، ولو السؤال طبي ده مش مكانه. المطابقة على أسامي
/// أدويته ودكاترته بتحصل قبل ما نوصل هنا — الجمل دي عمرها ما بتتكلم عن
/// حاجة مش عنده.

/// اللي محتاجينه عن دوا واحد — من صفه وجداوله، مش من تخمين.
class MedFact {
  const MedFact({required this.name, this.amountLabel, this.purposeLabel, this.minutes = const [], this.mealLabel});

  final String name;
  final String? amountLabel;

  /// «الدوا ده لإيه؟» زي ما **هو** اختاره — null = ما قالش.
  final String? purposeLabel;

  /// ساعات جرعاته الشغّالة (دقيقة اليوم).
  final List<int> minutes;
  final String? mealLabel;
}

/// «الكونكور ده لإيه؟» / «باخده إمتى؟» / «جرعته كام؟».
String medInfoText(MedFact m, MedInfoAspect aspect) {
  switch (aspect) {
    case MedInfoAspect.purpose:
      final p = m.purposeLabel;
      // مش متسجّل = مش بنخمّن ولا بنشرح — ده سؤال للدكتور
      return p == null
          ? 'مش متسجّل عندي ${m.name} لإيه — ده سؤال للدكتور أو الصيدلي.'
          // الكلمة بقت بـ«لل» («للضغط»)؛ التلاتة اللي فضلوا أسامي بياخدوا «لـ»
          : 'إنت كاتب إن ${m.name} ${p.startsWith('لل') ? p : 'لـ$p'}.';
    case MedInfoAspect.times:
      if (m.minutes.isEmpty) return 'مفيش مواعيد شغّالة لـ${m.name} دلوقتي.';
      final sorted = [...m.minutes]..sort();
      final times = [for (final x in sorted) voiceTime(DateTime(2026, 1, 1, 0, x))].join(' و');
      return 'بتاخد ${m.name} الساعة $times${m.mealLabel == null ? '' : ' — ${m.mealLabel}'}.';
    case MedInfoAspect.amount:
      final a = m.amountLabel?.trim();
      return a == null || a.isEmpty
          ? 'جرعة ${m.name} مش متسجّلة — اسأل الصيدلي واكتبها من صفحة الدوا.'
          : 'جرعة ${m.name}: $a.';
  }
}

/// «مين دكاترتي؟» — الأسامي اللي في ملفه وبس.
String doctorsText(List<String> doctors) {
  if (doctors.isEmpty) return 'مفيش دكاترة متسجّلين في ملفك لسه.';
  return 'دكاترتك: ${doctors.join('، ')}.';
}

/// «التحليل إمتى؟» / «ميعاد د. حسام إمتى؟» — من المواعيد الجاية، بالفلتر.
/// [doctorOf] اسم الدكتور اللي على صف الميعاد (لو متسجّل).
String filteredUpcomingText(
  List<UpcomingAppointment> soon, {
  AppointmentKind? kind,
  String? withWhom,
  String? Function(UpcomingAppointment a)? doctorOf,
}) {
  var list = soon;
  if (kind == AppointmentKind.lab) list = [for (final a in list) if (a.kind == FollowKind.lab) a];
  if (kind == AppointmentKind.doctor) list = [for (final a in list) if (a.kind == FollowKind.visit) a];
  if (withWhom != null) {
    list = [
      for (final a in list)
        if (matchDoctors(withWhom, [?doctorOf?.call(a), a.title]).isNotEmpty) a,
    ];
    if (list.isEmpty) return 'مفيش ميعاد جاي مع $withWhom متسجّل عندك.';
  }
  if (list.isEmpty) {
    return switch (kind) {
      AppointmentKind.lab => 'مفيش ميعاد معمل جاي متسجّل.',
      AppointmentKind.doctor => 'مفيش زيارة دكتور جاية متسجّلة.',
      _ => 'مفيش مواعيد جاية متسجّلة.',
    };
  }
  final a = list.first;
  final first = '${a.headline} ${a.displayTitle} يوم ${arabicDate(a.at)}';
  return list.length == 1 ? 'أقرب ميعاد: $first.' : 'أقرب ميعاد: $first — وبعده ${arabicNumber(list.length - 1)} كمان.';
}

/// «ملخص الأسبوع» بالكلام — نفس سطور الكارت (Phase D).
String weeklySummaryText(WeeklySummary s) => [
      '${s.title}.',
      '${s.dosesLine}.',
      if (s.missedLine.isNotEmpty) '${s.missedLine}.',
      '${s.lowStockLine}.',
      '${s.appointmentLine}.',
    ].join('\n');
