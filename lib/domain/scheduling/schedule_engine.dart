import 'day_routine.dart';
import 'dose_schedule.dart';

/// تذكير واحد — ممكن يشيل أكتر من دوا لو وقتهم واحد.
///
/// تلات أدوية في نفس الدقيقة = تذكير واحد بيقول «٣ أدوية دلوقتي»،
/// مش تلات منبّهات ورا بعض.
class Reminder {
  const Reminder({required this.at, required this.doses});

  final DateTime at;
  final List<DoseSchedule> doses;

  bool get isGrouped => doses.length > 1;

  @override
  String toString() =>
      'Reminder($at → ${doses.map((d) => d.medicationName).join(' + ')})';
}

/// محرك المواعيد.
///
/// دوال نقية بالكامل — من غير قاعدة بيانات ولا واجهة ولا إشعارات.
/// وده مقصود: بيخلي كل المنطق ده يتختبر بـ`flutter test` في أقل من ثانية.
class ScheduleEngine {
  const ScheduleEngine(this.routine);

  final DayRoutine routine;

  /// بيحوّل مرساة + إزاحة لوقت حقيقي في يوم معيّن.
  ///
  /// بنستخدم مُنشئ [DateTime] بدقايق مجمّعة عن قصد: هو بيتعامل مع
  /// تخطّي اليوم (لو الوقت عدّى منتصف الليل) ومع التوقيت الصيفي في مصر
  /// بحساب الساعة كما يراها المستخدم — عكس `add(Duration)` اللي بيضيف
  /// وقتاً مطلقاً وبيغلط عند تغيير التوقيت.
  DateTime resolveTime({
    required DayAnchor anchor,
    required int offsetMinutes,
    required DateTime onDay,
  }) {
    final total = routine.wake.minutes +
        routine.minutesFromDayStart(anchor) +
        offsetMinutes;
    return DateTime(onDay.year, onDay.month, onDay.day, 0, total);
  }

  /// ساعة ثابتة في يوم روتين معيّن.
  ///
  /// نفس قاعدة المراسي: اليوم بيبدأ من الصحيان. ساعة أبكر من الصحيان
  /// (زي ١ ص لواحد بيصحى ٧) بتاعة آخر اليوم، فبتقع في اليوم التقويمي اللي
  /// بعده — مش قبل الصحيان بست ساعات. غير كده الساعة ما بتتحركش خالص لما
  /// الروتين يتغيّر.
  DateTime resolveFixed({
    required MinuteOfDay minuteOfDay,
    required DateTime onDay,
  }) {
    final minutes = minuteOfDay.minutes;
    final total = minutes < routine.wake.minutes ? minutes + 1440 : minutes;
    return DateTime(onDay.year, onDay.month, onDay.day, 0, total);
  }

  DateTime resolve(DoseSchedule schedule, DateTime onDay) =>
      switch (schedule.timing) {
        AnchorTiming(:final anchor, :final offsetMinutes) => resolveTime(
            anchor: anchor,
            offsetMinutes: offsetMinutes,
            onDay: onDay,
          ),
        FixedTiming(:final minuteOfDay) =>
          resolveFixed(minuteOfDay: minuteOfDay, onDay: onDay),
      };

  /// كل تذكيرات يوم روتين واحد، مرتّبة ومجمّعة.
  ///
  /// ملاحظة: «اليوم» هنا هو يوم الروتين اللي بيبدأ من الصحيان — فجرعة
  /// «قبل النوم» لواحد بينام ١ ص هترجع بتاريخ اليوم اللي بعده، وده صح.
  List<Reminder> remindersForDay(
    List<DoseSchedule> schedules,
    DateTime day,
  ) {
    final byTime = <DateTime, List<DoseSchedule>>{};

    for (final s in schedules) {
      if (!s.isActiveOn(day)) continue;
      byTime.putIfAbsent(resolve(s, day), () => <DoseSchedule>[]).add(s);
    }

    final times = byTime.keys.toList()..sort();
    return [
      for (final t in times) Reminder(at: t, doses: byTime[t]!),
    ];
  }

  /// أقرب تذكير جاي بعد [from].
  ///
  /// بيدوّر لقدام [lookaheadDays] يوم وبيرجّع null لو ملقاش — بيحصل
  /// لما كل الأدوية تكون خلصت مدتها.
  Reminder? nextReminder(
    List<DoseSchedule> schedules,
    DateTime from, {
    int lookaheadDays = 14,
  }) {
    // بنبدأ من امبارح: جرعة «قبل النوم» بتاعة امبارح ممكن تكون لسه جاية
    // النهاردة بعد منتصف الليل.
    var day = DateTime(from.year, from.month, from.day)
        .subtract(const Duration(days: 1));

    for (var i = 0; i <= lookaheadDays + 1; i++) {
      for (final r in remindersForDay(schedules, day)) {
        if (r.at.isAfter(from)) return r;
      }
      day = day.add(const Duration(days: 1));
    }
    return null;
  }
}
