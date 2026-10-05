import '../../data/care/caregiver_remote.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../data/services/appointment_card.dart';
import '../../domain/adherence/weekly_summary.dart';
import '../../domain/health/follow_display.dart';
import '../care/caregiver_status.dart' show careFollowUps, careUpcoming;
import 'adherence_sources.dart';

/// **ملخص الأسبوع من الصورة** — الابن والممرض. نفس الحساب بتاع المريض، من
/// اللي وصل السحابة: الجرعات (آخر ٨ أيام بتتسحب، فالـ٧ الكاملة كلها موجودة)،
/// الأدوية اللي «قرب يخلص» عندها، وأقرب ميعاد متابعة.
WeeklySummary summaryFromSnapshot(CaregiverSnapshot s, DateTime now, {DateTime? from, DateTime? to}) => weeklySummary(
      doses: dosesFromSnapshot(s),
      today: DateTime(now.year, now.month, now.day),
      from: from,
      to: to,
      lowStock: [
        for (final m in s.medications)
          if (!m.stopped && m.stockLow) LowStockItem(m.name, m.stockDaysLeft),
      ],
      upcoming: [
        for (final f in careUpcoming(careFollowUps(s, now), now))
          UpcomingItem(followDisplayTitle(f.kind, f.record.title), f.stageDate!),
      ],
    );

/// **ملخص الأسبوع على موبايل المريض** («ملفّي») — من القاعدة المحلية.
WeeklySummary summaryFromLocal({
  required List<DoseEventView> week,
  required List<MedicationStockView> stock,
  required List<RecordRow> records,
  required DateTime today,
  required DateTime now,
  DateTime? from,
  DateTime? to,
}) =>
    weeklySummary(
      doses: dosesFromViews(week),
      today: today,
      from: from,
      to: to,
      lowStock: [for (final v in stock) if (v.isLow) LowStockItem(v.name, v.daysLeft)],
      upcoming: [for (final a in upcomingAppointments(records, now: now)) UpcomingItem(a.displayTitle, a.at)],
    );
