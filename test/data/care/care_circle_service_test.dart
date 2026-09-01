import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/care_circle_service.dart';

/// خدمة وهمية — كل اختبارات الشاشات عليها؛ مفيش شبكة في الاختبارات أبداً.
class FakeCareCircleService implements CareCircleService {
  final upserts = <({String uuid, String name})>[];
  final createdFor = <String>[];
  final redeemed = <String>[];

  CareCircleException? nextFailure;
  int _counter = 0;
  String patientName = 'الحاج أحمد';

  @override
  Future<void> upsertPatient({required String uuid, required String name}) async {
    final failure = nextFailure;
    if (failure != null) throw failure;
    upserts.add((uuid: uuid, name: name));
  }

  @override
  Future<InviteCode> createInvite(String patientUuid) async {
    final failure = nextFailure;
    if (failure != null) throw failure;
    createdFor.add(patientUuid);
    _counter++;
    return InviteCode(
      code: (123450 + _counter).toString(),
      expiresAt: DateTime(2026, 9, 1, 12).add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<String> redeemInvite(String code) async {
    final failure = nextFailure;
    if (failure != null) throw failure;
    redeemed.add(code);
    return patientName;
  }
}

void main() {
  test('كل سبب ليه جملته العربية المتفق عليها — ومفيش حروف إنجليزي', () {
    expect(
      const CareCircleException(CareCircleFailure.invalidOrExpiredCode).message,
      'الكود مش مضبوط أو خلّص وقته',
    );
    expect(
      const CareCircleException(CareCircleFailure.offline).message,
      'مفيش نت. التطبيق شغّال عادي، بس الربط محتاج اتصال.',
    );
    for (final failure in CareCircleFailure.values) {
      final message = CareCircleException(failure).message;
      expect(RegExp('[a-zA-Z]').hasMatch(message), isFalse,
          reason: 'رسالة خام وصلت للشاشة: $message');
    }
  });

  test('السبب التقني محفوظ في cause للوج، مش في الرسالة', () {
    const e = CareCircleException(
      CareCircleFailure.other,
      'PostgrestException(invalid_code)',
    );
    expect(e.message.contains('Postgrest'), isFalse);
    expect(e.cause.toString(), contains('invalid_code'));
  });
}
