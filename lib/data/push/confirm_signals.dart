/// **إشارة «اتأكّدت»** (0035) — رسالة دفع صامتة من السيرفر للناحية التانية:
/// المريض أكّد على موبايله → ممرضينه يلغوا تذكيرهم؛ ممرض أكّد نيابةً →
/// موبايل المريض يسحب التأكيد (وده اللي بيلغي سلّمه — القاعدة ٥) والممرضين
/// التانيين يلغوا بتوعهم.
///
/// دارت نقية: القراية من `data` بتاعة FCM. اللي ما وصلوش الإشارة بيتظبط في
/// المقارنة الجاية (سحبة / إعادة جدولة) — الإشارة بتسرّع، ما بتقرّرش.
library;



/// العلم: التطبيق بيسمع لإشارات الدفع (أندرويد بـFCM النهارده؛ iOS لما
/// APNs تتظبط — الكود جاهز والمصدر بيرجّع null هناك، فمفيش سماع).
const bool confirmPushEnabled = bool.fromEnvironment('CONFIRM_PUSH', defaultValue: true);

enum ConfirmSource { patient, proxy }

class ConfirmSignal {
  const ConfirmSignal({required this.patientUuid, required this.doseEventUuid, required this.source});

  final String patientUuid;
  final String doseEventUuid;
  final ConfirmSource source;

  /// null = مش إشارة تأكيد (تنبيه تصعيد مثلاً).
  static ConfirmSignal? fromData(Map<String, dynamic> data) {
    if (data['type'] != 'confirm') return null;
    final patient = data['patient_uuid'];
    final event = data['dose_event_uuid'];
    if (patient is! String || event is! String || patient.isEmpty || event.isEmpty) return null;
    return ConfirmSignal(
      patientUuid: patient,
      doseEventUuid: event,
      source: data['source'] == 'proxy' ? ConfirmSource.proxy : ConfirmSource.patient,
    );
  }

  Map<String, String> toData() => {
        'type': 'confirm',
        'patient_uuid': patientUuid,
        'dose_event_uuid': doseEventUuid,
        'source': source.name,
      };
}

/// مصدر رسايل الدفع (data messages) — Firebase في الحقيقي، فيك في الاختبار.
abstract interface class PushMessages {
  Stream<Map<String, dynamic>> get data;
}
