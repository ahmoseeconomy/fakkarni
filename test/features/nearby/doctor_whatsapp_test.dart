// الحجز عند دكتور من «القريب مني» ← رسالة جاهزة على واتساب الدكتور (طلب
// المالك، ٢٩ سبتمبر ٢٠٢٦): اليوم والساعة اللي اختارهم، واسم المريض وسنّه —
// والمستخدم هو اللي بيبعت. رقم أرضي أو مفيش = مفيش ورقة ومفيش رقم مخمّن.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/places/places.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/refill_actions.dart' show openWhatsApp;
import 'package:fakkarni/features/nearby/doctor_booking_message.dart';
import 'package:fakkarni/features/nearby/nearby_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  group('الرسالة', () {
    final sunday = DateTime(2026, 10, 4);

    test('اليوم والساعة والاسم والسن', () {
      expect(
        doctorBookingMessage(day: sunday, time: MinuteOfDay.hm(17), patientName: ' الحاج أحمد ', age: 72),
        'السلام عليكم،\n'
        'ممكن أحجز ميعاد كشف يوم الحد ٤ أكتوبر ٢٠٢٦ الساعة ٥:٠٠ م؟\n'
        'الاسم: الحاج أحمد\n'
        'السن: ٧٢ سنة',
      );
    });

    test('اللي مش متسجّل ما بيتكتبش: من غير سن، ومن غير ساعة، و«أنا» مش اسم', () {
      final m = doctorBookingMessage(day: sunday, patientName: 'أنا');
      expect(m, 'السلام عليكم،\nممكن أحجز ميعاد كشف يوم الحد ٤ أكتوبر ٢٠٢٦؟');
      expect(m, isNot(contains('السن')));
      expect(m, isNot(contains('الاسم')));
      expect(m, isNot(contains('الساعة')));
    });

    test('من غير «عايز/عايزة» ومن غير «·»', () {
      final m = doctorBookingMessage(day: sunday, time: MinuteOfDay.hm(9), patientName: 'سعاد', age: 65);
      expect(m, isNot(contains('عايز')));
      expect(m, isNot(contains('·')));
    });
  });

  group('بعد الحجز من «القريب مني»', () {
    final h = Harness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    final today = DateTime(2026, 10, 1);
    late List<Uri> launched;
    final original = openWhatsApp;
    setUp(() {
      launched = [];
      openWhatsApp = (uri) async {
        launched.add(uri);
        return true;
      };
    });
    tearDown(() => openWhatsApp = original);

    Place doctor(String? phone) =>
        Place(id: 'd1', kind: PlaceKind.doctor, lat: 30, lon: 31, name: 'عيادة د. سامي', phone: phone);

    Future<void> book(WidgetTester tester, Place place, {bool lab = false}) async {
      await tester.runAsync(() => h.services.patients.saveProfile(h.services.patientId, name: 'الحاج أحمد', age: 72));
      await h.pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => bookFromPlace(c, place, today),
              child: const Text('احجز'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await settle(tester);
      if (lab) {
        await tester.tap(find.byKey(const ValueKey('new-appt-lab')));
        await settle(tester);
      }
      await tester.ensureVisible(find.byKey(ValueKey('quick-time-${17 * 60}')));
      await tester.tap(find.byKey(ValueKey('quick-time-${17 * 60}')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('new-appt-save')));
      await tester.tap(find.byKey(const ValueKey('new-appt-save')));
      await settle(tester);
    }

    screenTest('موبايل: الورقة بالرسالة، والدوسة بتفتح واتساب الدكتور عليها', (tester) async {
      await book(tester, doctor('010 1234 5678'));
      final expected = doctorBookingMessage(
        day: DateTime(2026, 10, 2), // بكرة — افتراضي «ميعاد جديد»
        time: MinuteOfDay.hm(17),
        patientName: 'الحاج أحمد',
        age: 72,
      );
      expect(find.text(expected), findsOneWidget);
      expect(launched, isEmpty, reason: 'ولا حاجة بتتفتح قبل الدوسة');

      await tester.tap(find.byKey(const ValueKey('send-doctor-whatsapp')));
      await settle(tester);
      expect(launched, hasLength(1));
      expect(launched.single.host, 'wa.me');
      expect(launched.single.path, '/201012345678');
      expect(launched.single.queryParameters['text'], expected);
    });

    screenTest('«مش دلوقتي» = مفيش واتساب، والميعاد متحفظ', (tester) async {
      await book(tester, doctor('01012345678'));
      await tester.tap(find.byKey(const ValueKey('send-doctor-later')));
      await settle(tester);
      expect(launched, isEmpty);
      final rows = (await tester.runAsync(() => h.db.select(h.db.records).get()))!;
      expect(rows, hasLength(1));
    });

    screenTest('رقم أرضي أو مفيش رقم: مفيش ورقة ومفيش رقم مخمّن — الميعاد متحفظ', (tester) async {
      await book(tester, doctor('0223456789'));
      expect(find.byKey(const ValueKey('send-doctor-whatsapp')), findsNothing);
      expect(launched, isEmpty);
      final rows = (await tester.runAsync(() => h.db.select(h.db.records).get()))!;
      expect(rows, hasLength(1));
    });

    screenTest('مفيش رقم خالص: نفس الحاجة', (tester) async {
      await book(tester, doctor(null));
      expect(find.byKey(const ValueKey('send-doctor-whatsapp')), findsNothing);
      expect(launched, isEmpty);
    });

    screenTest('لو غيّرها لمعمل: مفيش رسالة كشف', (tester) async {
      await book(tester, doctor('01012345678'), lab: true);
      expect(find.byKey(const ValueKey('send-doctor-whatsapp')), findsNothing);
    });
  });
}
