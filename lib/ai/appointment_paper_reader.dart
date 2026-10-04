import 'dart:typed_data';

import '../domain/scheduling/minute_of_day.dart';
import 'gemini_config.dart';
import 'prescription_reader.dart';

/// اللي اتقرا من ورقة دكتور أو معمل عشان **ميعاد** — اسم الدكتور (أو المعمل)
/// والميعاد الجاي المكتوب، وبس.
///
/// **مفيش خانة دوا هنا خالص** (طلب المدير، ٤ أكتوبر ٢٠٢٦): «عندي روشتة —
/// ابدأ منها» من «ميعاد جديد» كانت بتفتح تصوير الروشتة الكامل، فالورقة
/// بتضيف أدوية والراجل كان عايز ميعاد. الـschema نفسها مالهاش خانة أدوية،
/// فمفيش حاجة تتسرّب حتى لو الموديل رجّعها.
class AppointmentPaperReading {
  const AppointmentPaperReading({this.name, this.place, this.date, this.time, this.highConfidence = false});

  /// اسم الدكتور (أو المعمل) زي ما هو مكتوب — null = مش مكتوب أو مش واضح.
  final String? name;
  final String? place;

  /// يوم الميعاد الجاي — **مكتوب بالحرف بس**؛ «بعد أسبوع» ما بيتحسبش.
  final DateTime? date;

  /// الساعة لو مكتوبة بوضوح (ص/م)، وإلا null.
  final MinuteOfDay? time;
  final bool highConfidence;

  /// فيه ميعاد ينفع نعرضه: ثقة عالية، ويوم مكتوب، ومش فات.
  bool hasUpcoming(DateTime today) {
    final d = date;
    if (!highConfidence || d == null) return false;
    final start = DateTime(today.year, today.month, today.day);
    // أبعد من سنة = غالباً غلط في القراية، وأيام «إمتى؟» ما بتوصلش لهناك
    return !d.isBefore(start) && !d.isAfter(DateTime(start.year + 1, start.month, start.day));
  }

  /// صارم: أي شكل غلط = مش موجود.
  factory AppointmentPaperReading.fromJson(Map<String, dynamic> json) {
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    DateTime? day(Object? v) {
      final s = text(v);
      final m = s == null ? null : RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
      if (m == null) return null;
      final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
      if (y < 2000 || y > 2100 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      final out = DateTime(y, mo, d);
      // ٣١ فبراير بيلفّ لمارس — يبقى مش تاريخ
      return out.month == mo ? out : null;
    }

    MinuteOfDay? clock(Object? v) {
      final s = text(v);
      final m = s == null ? null : RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s);
      if (m == null) return null;
      final h = int.parse(m[1]!), mi = int.parse(m[2]!);
      if (h > 23 || mi > 59) return null;
      return MinuteOfDay.hm(h, mi);
    }

    return AppointmentPaperReading(
      name: text(json['name']),
      place: text(json['place']),
      date: day(json['appointment_date']),
      time: clock(json['appointment_time']),
      highConfidence: json['confidence'] == 'high',
    );
  }
}

abstract interface class AppointmentPaperReader {
  Future<AppointmentPaperReading> read(Uint8List image, {String mimeType = 'image/jpeg'});
}

/// **نفس نقل Gemini بتاع الروشتة بالحرف** ([GeminiPrescriptionReader.generate]).
/// ولا الصورة ولا اللي اتقرا بيتسجّل.
class GeminiAppointmentPaperReader implements AppointmentPaperReader {
  GeminiAppointmentPaperReader(GeminiConfig config, {GeminiPrescriptionReader? transport})
      : _transport = transport ?? GeminiPrescriptionReader(config);

  final GeminiPrescriptionReader _transport;

  @override
  Future<AppointmentPaperReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    final result = await _transport.generate(
      image: image,
      mimeType: mimeType,
      prompt: prompt,
      schema: appointmentPaperSchema,
      systemInstruction: systemInstruction,
      failure: appointmentPaperUnreadable,
    );
    return AppointmentPaperReading.fromJson(result.json);
  }

  static const systemInstruction = '''
You read a photo of a doctor's prescription, a clinic card or a lab paper to find ONE thing: the next appointment written on it, and who it is with. Return JSON only.
Do NOT read medicines, doses or test results. They are not part of this task.
Return ONLY what is written. Never invent, compute or guess a date, a time or a name.
''';

  static const prompt = '''
Read the attached paper.
name: the doctor's name (or the lab's name on a lab paper) exactly as written, including a title like «د.» if written; otherwise null.
place: the clinic, hospital or lab name exactly as written, or null.
appointment_date: the date of the NEXT appointment, follow-up visit («الإعادة», «الاستشارة», «ميعاد», «حجز», "follow up", "next visit") as YYYY-MM-DD — only if a full calendar date is written. A relative phrase («بعد أسبوع», "in 2 weeks") is NOT a date: return null. The date the paper was written is NOT an appointment: return null for it.
appointment_time: the appointment clock time as HH:MM (24h) only if written with AM/PM or ص/م or in 24h form; otherwise null.
confidence: "high" only if you could read the appointment date clearly; otherwise "low".
''';
}

/// الجملة لما الورقة ما تتقراش (زحمة أو عطل الشبكة ليهم جملتهم من النقل).
const appointmentPaperUnreadable = 'مقدرتش أقرا الورقة كويس — صوّرها تاني في نور أحسن أو ضيف الميعاد بإيدك';

/// الجملة لما الورقة اتقرت ومفيش فيها ميعاد جاي (نص المدير بالحرف للروشتة).
String noUpcomingAppointment({required bool lab}) => lab
    ? 'مفيش في التقرير ميعاد أو حجز قادم للمعمل — ضيفه بإيدك'
    : 'مفيش في الروشتة ميعاد أو حجز قادم للدكتور — ضيفه بإيدك';

const Map<String, dynamic> appointmentPaperSchema = {
  'type': 'OBJECT',
  'properties': {
    'name': {'type': 'STRING', 'nullable': true},
    'place': {'type': 'STRING', 'nullable': true},
    'appointment_date': {'type': 'STRING', 'nullable': true},
    'appointment_time': {'type': 'STRING', 'nullable': true},
    'confidence': {
      'type': 'STRING',
      'enum': ['high', 'low'],
    },
  },
  'required': ['name', 'place', 'appointment_date', 'appointment_time', 'confidence'],
};
