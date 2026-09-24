import 'dart:io';

import 'package:fakkarni_admin/data/admin_models.dart';
import 'package:fakkarni_admin/data/device_codes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_admin_service.dart';

/// الأكواد بكلام الأدمن — دارت ساذجة، من غير شاشة.
void main() {
  final now = DateTime(2026, 9, 24, 12);

  test('كل كود ليه كلمة عربية، والمش معروف بيتعرض بالاسم مش بالسكوت', () {
    for (final code in knownDeviceCodes) {
      final label = deviceCodeLabel(code, now: now);
      expect(label, isNot(contains('كود مش معروف')), reason: code);
      expect(label, isNot(contains(code)), reason: 'الكود ما يظهرش بالاسم اللاتيني: $code');
    }
    expect(deviceCodeLabel('somethingNew'), 'كود مش معروف: somethingNew');
  });

  test('الأربعة اللي المالك سمّاهم بالحرف', () {
    expect(deviceCodeLabel('accountMissing'), 'الحساب مش موجود على السيرفر');
    expect(deviceCodeLabel('notificationPermission'), 'الإشعارات مقفولة');
    expect(deviceCodeLabel('pushToken'), 'مفيش توكن');
    final d = device(lastSyncAt: now.subtract(const Duration(hours: 3)));
    expect(deviceCodeLabel('staleSync', device: d, now: now), 'مزامنة واقفة من ٣ ساعات');
    expect(deviceCodeLabel('staleSync', device: device(), now: now), 'مزامنة واقفة — ولا مرة وصلت');
  });

  test('**مرآة قايمة الأكواد بتاعة التطبيق** — كود جديد هناك من غير كلمة هنا بيقع', () {
    // اللوحة ما بتستوردش حزمة التطبيق؛ بتقرا الملف زي مرآة معرّف القناة
    final src = File('../lib/domain/health/health_check.dart').readAsStringSync();
    final start = src.indexOf('enum HealthCode {');
    final body = src.substring(start, src.indexOf('\n}\n', start));
    final appCodes = [
      for (final m in RegExp(r'^\s+([a-zA-Z]+),', multiLine: true).allMatches(body)) m.group(1)!,
    ];
    expect(appCodes, isNotEmpty);
    expect(knownDeviceCodes.toSet(), appCodes.toSet());
  });

  test('ساكت = أقدم من ٢٤ ساعة، والجملة بتقول المدة', () {
    final fresh = device(checkedAt: now.subtract(const Duration(hours: 2)));
    final old = device(checkedAt: now.subtract(const Duration(days: 3)));
    expect(deviceIsSilent(fresh, now), isFalse);
    expect(deviceIsSilent(old, now), isTrue);
    expect(deviceCheckedLine(fresh, now), 'آخر فحص من ساعتين');
    expect(deviceCheckedLine(old, now), 'ماوصلش منه حاجة من ٣ أيام');
    expect(deviceCheckedLine(device(), now), 'ماوصلش منه حاجة خالص');
  });

  test('«فيه مشكلة» = كود أو سكوت — والسليم لأ', () {
    expect(deviceHasProblem(device(checkedAt: now), now), isFalse);
    expect(deviceHasProblem(device(checkedAt: now, codes: ['pushToken']), now), isTrue);
    expect(deviceHasProblem(device(checkedAt: now.subtract(const Duration(days: 2))), now), isTrue);
  });

  test('الصف من السيرفر بيتقرا بأكواده، والأكواد المش نص بتتعدّى', () {
    final d = AdminDevice.fromRow({
      'patient_uuid': 'p1',
      'patient_name': ' الحاج عاشور ',
      'install_id': 'i1',
      'checked_at': '2026-09-24T09:00:00Z',
      'failing_codes': ['staleSync', 7, 'pushToken'],
      'dirty_count': 4,
      'has_token': false,
    });
    expect(d.patientName, 'الحاج عاشور');
    expect(d.failingCodes, ['staleSync', 'pushToken']);
    expect(d.dirtyCount, 4);
    expect(d.hasToken, isFalse);
    expect(d.checkedAt, isNotNull);
  });
}
