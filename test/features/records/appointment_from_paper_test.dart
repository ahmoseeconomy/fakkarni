// «ميعاد جديد» → «عندي روشتة/تقرير — ابدأ منها» → صورة: **اسم الدكتور
// والميعاد الجاي وبس** (طلب المدير، ٤ أكتوبر ٢٠٢٦). ولا دوا بيتضاف، والورقة
// اللي مفيهاش ميعاد جاي بتقول كده بجملة واحدة.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/appointment_paper_reader.dart';
import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';
import 'package:fakkarni/features/scan/scan_prescription_screen.dart' show PickImage;

import '../scan/scan_test_support.dart';

class _FakeReader implements AppointmentPaperReader {
  _FakeReader(this.reading);
  AppointmentPaperReading reading;
  int calls = 0;
  @override
  Future<AppointmentPaperReading> read(Uint8List image, {String mimeType = 'image/jpeg'}) async {
    calls++;
    return reading;
  }
}

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final sep15 = DateTime(2026, 9, 15, 10);
  late PickImage originalPick;
  setUp(() {
    originalPick = pickAppointmentPaper;
    pickAppointmentPaper = (_) async => Uint8List.fromList([1, 2, 3]);
  });
  tearDown(() => pickAppointmentPaper = originalPick);

  Future<void> open(WidgetTester tester, _FakeReader reader, String kind) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    h.services = AppServices(
      db: h.services.db,
      patients: h.services.patients,
      medications: h.services.medications,
      events: h.services.events,
      scheduler: h.services.scheduler,
      patientId: h.services.patientId,
      appointmentPaperReader: reader,
    );
    await h.pump(tester, HealthFileScreen(today: sep15));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('new-appointment')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('new-appt-$kind')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('start-follow-$kind')));
    await settle(tester);
  }

  screenTest('روشتة فيها ميعاد: الورقة بتتفتح متعبّية، والحفظ ميعاد وبس — ولا دوا', (tester) async {
    final reader = _FakeReader(AppointmentPaperReading(
      name: 'د. حسام',
      date: DateTime(2026, 9, 22),
      highConfidence: true,
    ));
    await open(tester, reader, 'visit');
    expect(find.byKey(const ValueKey('follow-by-hand')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('follow-from-photo')));
    await settle(tester);

    expect(reader.calls, 1);
    expect(find.text('راجع الميعاد'), findsOneWidget);
    expect(find.text('د. حسام'), findsOneWidget, reason: 'الاسم في خانته');
    // مفيش «عندي روشتة» تاني جوّه نفسها
    expect(find.byKey(const ValueKey('start-follow-visit')), findsNothing);
    // ولا حاجة اتكتبت قبل دوسة الإنسان
    expect(await RecordsRepository(h.db).all(h.services.patientId), isEmpty);

    await tester.tap(find.byKey(const ValueKey('new-appt-save')));
    await settle(tester);

    final rows = await RecordsRepository(h.db).all(h.services.patientId);
    final follow = rows.single;
    expect(CheckupService.kindOf(follow), FollowKind.visit);
    expect(follow.doctorVisitAt, isNotNull);
    expect(DateTime(follow.doctorVisitAt!.year, follow.doctorVisitAt!.month, follow.doctorVisitAt!.day),
        DateTime(2026, 9, 22));
    expect(await h.db.select(h.db.medications).get(), isEmpty, reason: 'الورقة دي ما بتضيفش أدوية');
  });

  screenTest('روشتة من غير ميعاد جاي: جملة المدير بالحرف، و«ضيفه بإيدك»', (tester) async {
    final reader = _FakeReader(const AppointmentPaperReading(name: 'د. حسام', highConfidence: false));
    await open(tester, reader, 'visit');
    await tester.tap(find.byKey(const ValueKey('follow-from-gallery')));
    await settle(tester);

    expect(find.text('مفيش في الروشتة ميعاد أو حجز قادم للدكتور — ضيفه بإيدك'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paper-add-by-hand')));
    await settle(tester);
    expect(find.byKey(const ValueKey('new-appt-save')), findsOneWidget);
    expect(await RecordsRepository(h.db).all(h.services.patientId), isEmpty);
  });

  screenTest('ميعاد فات = مفيش ميعاد جاي', (tester) async {
    final reader = _FakeReader(AppointmentPaperReading(date: DateTime(2026, 9, 1), highConfidence: true));
    await open(tester, reader, 'lab');
    await tester.tap(find.byKey(const ValueKey('follow-from-photo')));
    await settle(tester);
    expect(find.text('مفيش في التقرير ميعاد أو حجز قادم للمعمل — ضيفه بإيدك'), findsOneWidget);
  });

  screenTest('من غير مفتاح القراية مفيش زرار تصوير', (tester) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, HealthFileScreen(today: sep15));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('new-appointment')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('start-follow-visit')));
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-from-photo')), findsNothing);
    expect(find.byKey(const ValueKey('follow-from-file')), findsOneWidget);
  });

  group('القارئ', () {
    test('الـschema مالهاش خانة دوا — أي حقل زيادة ما بيوصلش', () {
      final props = (appointmentPaperSchema['properties'] as Map).keys.toSet();
      expect(props, {'name', 'place', 'appointment_date', 'appointment_time', 'confidence'});
      final r = AppointmentPaperReading.fromJson({
        'name': 'د. حسام',
        'appointment_date': '2026-09-22',
        'appointment_time': '17:30',
        'confidence': 'high',
        'medicines': ['Concor 5mg'],
      });
      expect(r.date, DateTime(2026, 9, 22));
      expect(r.time?.minutes, 17 * 60 + 30);
    });

    test('تاريخ مش صحيح أو ساعة مش صحيحة = null، مش تخمين', () {
      final r = AppointmentPaperReading.fromJson({
        'appointment_date': '2026-02-31',
        'appointment_time': '5',
        'confidence': 'high',
      });
      expect(r.date, isNull);
      expect(r.time, isNull);
      expect(r.hasUpcoming(DateTime(2026, 1, 1)), isFalse);
    });

    test('ثقة واطية = مفيش ميعاد، حتى لو فيه تاريخ', () {
      final r = AppointmentPaperReading(date: DateTime(2026, 9, 22));
      expect(r.hasUpcoming(DateTime(2026, 9, 15)), isFalse);
    });

    test('البرومبت بيمنع الأدوية والتواريخ النسبية وتاريخ الورقة', () {
      expect(GeminiAppointmentPaperReader.systemInstruction, contains('Do NOT read medicines'));
      expect(GeminiAppointmentPaperReader.prompt, contains('is NOT a date'));
      expect(GeminiAppointmentPaperReader.prompt, contains('The date the paper was written is NOT an appointment'));
    });

    test('نفس النقل: المفتاح في x-goog-api-key والجسم فيه الـschema بتاعته', () async {
      http.Request? sent;
      final client = MockClient((req) async {
        sent = req;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'name': 'د. منى',
                        'place': null,
                        'appointment_date': '2026-10-10',
                        'appointment_time': null,
                        'confidence': 'high',
                      })
                    }
                  ]
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final config = GeminiConfig(apiKey: 'test-key');
      final reader = GeminiAppointmentPaperReader(
        config,
        transport: GeminiPrescriptionReader(config, client: client),
      );
      final r = await reader.read(Uint8List.fromList([1, 2, 3]));
      expect(r.name, 'د. منى');
      expect(r.date, DateTime(2026, 10, 10));
      expect(sent!.headers['x-goog-api-key'], 'test-key');
      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      expect(jsonEncode(body['generationConfig']['responseSchema']), contains('appointment_date'));
      expect(jsonEncode(body['generationConfig']['responseSchema']), isNot(contains('medic')));
    });
  });
}
