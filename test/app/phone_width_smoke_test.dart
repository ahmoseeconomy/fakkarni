import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/data/repositories/emergency_repository.dart';
import 'package:fakkarni/data/repositories/lab_results_repository.dart';
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/visit_questions_repository.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/doctor/doctor_page_screen.dart';
import 'package:fakkarni/features/elder/elder_home_screen.dart';
import 'package:fakkarni/features/emergency/emergency_card_screen.dart';
import 'package:fakkarni/features/emergency/emergency_edit_screen.dart';
import 'package:fakkarni/features/emergency/emergency_info_screen.dart';
import 'package:fakkarni/features/export/export_pdf.dart';
import 'package:fakkarni/features/export/export_screen.dart';
import 'package:fakkarni/features/health/glucose_screen.dart';
import 'package:fakkarni/features/health/scan_lab_screen.dart';
import 'package:fakkarni/features/link/sign_in_screen.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';
import 'package:fakkarni/features/nearby/nearby_screen.dart';
import 'package:fakkarni/features/onboarding/routine_onboarding_screen.dart';
import 'package:fakkarni/features/records/calendar_screen.dart';
import 'package:fakkarni/features/records/checkup_screen.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/records/history_screen.dart';
import 'package:fakkarni/features/records/manual_entry_screen.dart';
import 'package:fakkarni/features/routine/edit_routine_screen.dart';
import 'package:fakkarni/features/routine/ramadan_screen.dart';
import 'package:fakkarni/features/scan/scan_prescription_screen.dart';
import 'package:fakkarni/features/settings/notifications_screen.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../features/scan/scan_test_support.dart';

class _Denied implements LocationSource {
  @override
  Future<LocationFix> current() async => const LocationFix(LocationStatus.denied);
  @override
  Future<void> openSettings() async {}
}

/// كل شاشة على عرض موبايل حقيقي (٣٩٠) — فاضية ومليانة، وبخط النظام ١.٣.
///
/// اختبارات الشاشات بتتبني على ١٠٠٠ بكسل عرض عشان الـListView يبني كل
/// حاجة؛ على العرض ده نص بيتقص أو Row بيفيض عمره ما يبان. Flutter بيرمي
/// على أي «RenderFlex overflowed»، فالاختبار ده بيوقع عليها.
/// الخطوط الحقيقية — من غيرها flutter_test بيرسم كل حرف مربّع بعرض الخط
/// كله، والعربي بيبان أعرض بكتير من الموبايل وبيطلّع فيضان مش حقيقي.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('IBM Plex Sans Arabic', [
    'IBMPlexSansArabic-Regular.ttf',
    'IBMPlexSansArabic-Medium.ttf',
    'IBMPlexSansArabic-SemiBold.ttf',
    'IBMPlexSansArabic-Bold.ttf',
  ]);
  await load('Alexandria', ['Alexandria-Medium.ttf', 'Alexandria-Bold.ttf']);
  await load('IBM Plex Mono', ['IBMPlexMono-Medium.ttf', 'IBMPlexMono-SemiBold.ttf']);
}

void main() {
  setUpAll(_loadFonts);
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final now = DateTime(2026, 9, 15, 10);

  Future<void> seed() async {
    final id = h.services.patientId;
    await h.services.routines.saveProfile(id, name: 'عبد الرحمن محمود الشربيني', sex: Sex.m, age: 72);
    await h.meds.addMedication(
      patientId: id,
      name: 'Glucophage XR 1000mg extended release',
      amountLabel: 'قرص واحد بعد الأكل مباشرة',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: DateTime(2026, 9, 1),
    );
    await h.meds.addMedication(
      patientId: id,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.dinner, 0),
      startDate: DateTime(2026, 9, 1),
    );
    final r = ReadingsRepository(h.db);
    for (final (v, d) in [(118, 1), (152, 5), (131, 9), (122, 11), (125, 13), (199, 14)]) {
      await r.add(patientId: id, valueMgDl: v, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 9, d, 7));
    }
    await LabResultsRepository(h.db).saveReport(
      patientId: id,
      happenedAt: DateTime(2026, 9, 12),
      place: 'معمل البرج — فرع مصر الجديدة',
      lines: const [ConfirmedLabLine(testName: 'Glycated Hemoglobin HbA1c', value: 7.6, unit: '%')],
    );
    final records = RecordsRepository(h.db);
    await records.add(
      patientId: id,
      kind: RecordKind.visit,
      title: 'باطنة وغدد صماء وسكر',
      doctor: 'د. هشام محمد عبد العزيز',
      place: 'مستشفى السلام الدولي',
      notes: 'ضبط جرعة Amaryl ومتابعة بعد شهر',
      happenedAt: DateTime(2026, 9, 10),
    );
    await h.services.checkups.start(patientId: id, title: 'صورة دم كاملة CBC', doctor: 'د. هشام', today: now);
    await EmergencyRepository(h.db).save(
      id,
      const EmergencyInfo(
        bloodType: 'AB-',
        allergies: 'بنسلين، سلفا، أسبرين',
        chronicConditions: 'سكر نوع تاني، ضغط مرتفع من ٢٠١٤',
        contacts: [EmergencyContact(name: 'محمد عبد الرحمن', phone: '01001234567', relation: 'ابني الكبير')],
      ),
    );
    await VisitQuestionsRepository(h.db).add(id, 'نقدر نقلّل جرعة Amaryl لو السكر الصايم فضل مستقر الشهر ده؟', now: now);
  }

  final fonts = PdfFonts.fromBytes(
    ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-Regular.ttf').readAsBytesSync()),
    ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-Bold.ttf').readAsBytesSync()),
  );

  final screens = <String, Widget Function()>{
    'shell': () => AppShell(routine: normalDay, now: now),
    'today': () => TodayScreen(routine: normalDay, now: now),
    'medications': () => const MedicationsScreen(),
    'settings': () => const SettingsScreen(),
    'onboarding': () => const RoutineOnboardingScreen(),
    'add medication': () => AddMedicationScreen(routine: normalDay),
    'scan prescription': () => ScanPrescriptionScreen(routine: normalDay, reader: null),
    'scan lab': () => const ScanLabScreen(reader: null),
    'sign in': () => const SignInScreen(auth: null),
    'edit routine': () => EditRoutineScreen(routine: normalDay),
    'ramadan': () => RamadanScreen(today: now),
    'notifications': () => const NotificationsScreen(),
    'elder home': () => ElderHomeScreen(routine: normalDay, now: now),
    'emergency info': () => const EmergencyInfoScreen(),
    'emergency card': () => EmergencyCardScreen(now: () => now),
    'checkup': () => CheckupScreen(recordId: 1, now: () => now),
    'emergency edit': () => const EmergencyEditScreen(),
    'health file': () => HealthFileScreen(today: now),
    'history': () => HistoryScreen(today: now),
    'calendar': () => CalendarScreen(today: now),
    'manual entry': () => ManualEntryScreen(today: now),
    'glucose': () => GlucoseScreen(now: () => now),
    'doctor page': () => DoctorPageScreen(now: () => now),
    'export': () => ExportScreen(fonts: fonts, now: () => now),
    'nearby (denied)': () => NearbyScreen(location: _Denied(), now: () => now),
  };

  for (final scale in [1.0, 1.3]) {
    for (final filled in [false, true]) {
      for (final MapEntry(key: name, value: build) in screens.entries) {
        screenTest('عرض ٣٩٠ · خط ×$scale · ${filled ? 'مليانة' : 'فاضية'} · $name', (tester) async {
          if (filled) await seed();
          tester.view.physicalSize = const Size(390, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            AppScope(
              services: h.services,
              child: MaterialApp(
                theme: F.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: Directionality(textDirection: TextDirection.rtl, child: child!),
                ),
                home: Builder(builder: (_) => build()),
              ),
            ),
          );
          // أي فيضان بيوقّع الاختبار لوحده ومعاه مكان الودجت في الكود
          await settle(tester);
        });
      }
    }
  }
}
