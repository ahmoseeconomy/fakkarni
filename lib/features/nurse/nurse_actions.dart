import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../data/places/places.dart';
import '../../domain/care/medication_change.dart';
import '../../domain/health/vitals.dart';
import '../../domain/medication/stock.dart' show stockUnitOf;
import '../medication/medication_draft.dart';
import '../medication/nurse_draft.dart' show pickTimingsAsNurse;
import '../medication/pharmacy_sheet.dart';
import '../medication/refill_actions.dart' show orderFromPharmacy;
import '../nearby/nearby_screen.dart';
import '../records/health_file_screen.dart' show NewAppointmentBody, NewAppointmentResult;
import 'nurse_controller.dart';

/// **أفعال الممرض اللي بقت زي المريض** (0035) — كل واحدة طلب بيتبعت لموبايل
/// المريض ويتطبّق هناك بسكّته، وبيقول «اتبعت» أو «هيوصل … أول ما يفتح النت».
/// مفيش سطر هنا بيكتب في قاعدة الموبايل ده.
extension NurseActions on NurseController {
  /// «ضيف دوا» من مسوّدة (بالإيد / صورة العلبة / سطر روشتة).
  Future<bool> addFromDraft(MedicationDraft d) => submit(
        kind: MedicationChangeKind.add,
        payload: MedicationChangePayload(
          name: d.name,
          timings: d.timings,
          amountLabel: d.amountLabel,
          durationDays: d.durationDays,
          purpose: d.purpose,
          instructions: d.instructions,
          alertMode: d.alertMode,
          startDate: d.startDate,
          mealRelation: d.mealRelation?.storageName,
        ),
      );

  Future<bool> removeMedication(CaregiverMedication med) => submit(
        kind: MedicationChangeKind.remove,
        payload: const MedicationChangePayload(),
        medicationUuid: med.uuid,
        medicationName: med.name,
      );

  Future<bool> resumeMedication(CaregiverMedication med) => submit(
        kind: MedicationChangeKind.resume,
        payload: const MedicationChangePayload(),
        medicationUuid: med.uuid,
        medicationName: med.name,
      );

  Future<bool> setStock(CaregiverMedication med, double quantity, {int? warnDays}) => submit(
        kind: MedicationChangeKind.stockSet,
        payload: MedicationChangePayload(quantity: quantity, warnDays: warnDays),
        medicationUuid: med.uuid,
        medicationName: med.name,
      );

  Future<bool> addVital(VitalEntry entry, DateTime at) => submit(
        kind: MedicationChangeKind.vital,
        payload: MedicationChangePayload(
          name: entry.kind.label,
          vitalKind: entry.kind.name,
          value: entry.value,
          value2: entry.value2,
          pulse: entry.pulse,
          measuredAt: at,
        ),
      );

  Future<bool> setPharmacy(SavedPharmacy p) => submit(
        kind: MedicationChangeKind.pharmacy,
        payload: MedicationChangePayload(pharmacyName: p.name, pharmacyCall: p.call, pharmacyWhatsapp: p.whatsapp),
      );

  Future<bool> bookAppointment(NewAppointmentResult r) => submit(
        kind: MedicationChangeKind.appointment,
        payload: MedicationChangePayload(name: r.title, followKind: r.kind.name, day: r.day),
      );

  /// صيدلية المريض زي ما موبايله رفعها (0035) — null قبل الهجرة أو لو ما اتسجّلتش.
  SavedPharmacy? get patientPharmacy {
    final p = snapshot?.patient;
    if (p == null) return null;
    if (p.pharmacyName == null && p.pharmacyCall == null && p.pharmacyWhatsapp == null) return null;
    return (name: p.pharmacyName, whatsapp: p.pharmacyWhatsapp, call: p.pharmacyCall);
  }
}

/// «صيدليتي» بتاعة المريض من موبايل الممرض — نفس الورقة، والحفظ طلب.
Future<SavedPharmacy?> editPatientPharmacy(BuildContext context, NurseController c, {PharmacyPrefill? prefill}) async {
  SavedPharmacy? saved;
  final ok = await editPharmacyWith(
    context,
    current: c.patientPharmacy ?? (name: null, whatsapp: null, call: null),
    prefill: prefill,
    pickNearby: (ctx) => Navigator.of(ctx).push<Place>(MaterialPageRoute(
      builder: (nc) => NearbyScreen(
        initialKind: PlaceKind.pharmacy,
        onPickPharmacy: (place) => Navigator.of(nc).pop(place),
        onBookPlace: (place) => bookFromNearby(nc, c, place),
      ),
    )),
    onSave: (p) async {
      if (await c.setPharmacy(p)) saved = p;
    },
  );
  return ok == true ? saved : null;
}

/// «اطلبه من الصيدلية» على موبايل الممرض — صيدلية المريض، أو يسجّلها له الأول.
Future<void> orderForPatient(BuildContext context, NurseController c, String medicationName) => orderFromPharmacy(
      context,
      medicationName,
      pharmacy: c.patientPharmacy,
      edit: () => editPatientPharmacy(context, c),
    );

/// «احجز ميعاد عنده» من «القريب مني» عند الممرض — طلب ميعاد لموبايل المريض.
Future<void> bookFromNearby(BuildContext context, NurseController c, Place place) async {
  final t = DateTime.now();
  final result = await FSheet.show<NewAppointmentResult>(
    context,
    title: 'ميعاد جديد',
    children: [
      NewAppointmentBody(today: DateTime(t.year, t.month, t.day), allowFromPaper: false, askTime: false, initialName: place.name),
    ],
  );
  if (result == null) return;
  await c.bookAppointment(result);
}

/// «غيّر المواعيد» — البكرة في `features/medication/nurse_draft.dart` (بتلمس
/// أنواع الجدولة، وجانب الممرض ما بيستوردهاش)، والحفظ طلب `timings`.
Future<void> editTimingsAsNurse(BuildContext context, NurseController c, CaregiverMedication med) async {
  final payload = await pickTimingsAsNurse(context, name: med.name, minutes: med.minutes);
  if (payload == null) return;
  await c.submit(kind: MedicationChangeKind.timings, payload: payload, medicationUuid: med.uuid, medicationName: med.name);
}

/// «ظبّط المخزون»: الكمية دلوقتي على بكرة (بتكتب فوق) — عكس «علبة جديدة».
Future<void> setStockAsNurse(BuildContext context, NurseController c, CaregiverMedication med) async {
  final unit = stockUnitOf(med.amountLabel);
  final q = await FSheet.show<int>(
    context,
    title: 'مخزون ${med.name}',
    children: [_StockBody(unit: unit, initial: med.stockQuantity?.round() ?? 0)],
  );
  if (q == null) return;
  await c.setStock(med, q.toDouble(), warnDays: med.stockWarnDays);
}

class _StockBody extends StatefulWidget {
  const _StockBody({required this.unit, required this.initial});
  final String unit;
  final int initial;

  @override
  State<_StockBody> createState() => _StockBodyState();
}

class _StockBodyState extends State<_StockBody> {
  late int _q = widget.initial;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('عنده كام ${widget.unit} دلوقتي؟', style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
          const SizedBox(height: F.s8),
          FNumberWheel(
            key: const ValueKey('nurse-stock-wheel'),
            value: _q,
            min: 0,
            max: 300,
            unit: widget.unit,
            semanticsLabel: 'الكمية',
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('nurse-stock-save'),
            label: 'ابعتها لموبايله',
            onPressed: () => Navigator.of(context).pop(_q),
          ),
        ],
      );
}

/// «شيله خالص» — بيسأل بالاسم، وبيقول إن مفيش رجوع من عنده (المريض عنده
/// «تراجع» ٢٤ ساعة على موبايله).
Future<void> removeAsNurse(BuildContext context, NurseController c, CaregiverMedication med) async {
  final yes = await FSheet.show<bool>(
    context,
    title: 'تشيل ${med.name} خالص؟',
    children: [
      Text('هيتشال من قوايم المريض كلها. لو عايز يوقفه بس مؤقتاً، «وقّفه» أحسن — ده بيرجع.',
          style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
      const SizedBox(height: F.gap),
      FPrimaryButton(key: const ValueKey('nurse-remove-confirm'), label: 'أيوه، شيله', onPressed: () => Navigator.of(context).pop(true)),
      const SizedBox(height: F.s8),
      FSecondaryButton(label: 'لأ، سيبه', onPressed: () => Navigator.of(context).pop(false)),
    ],
  );
  if (yes == true) await c.removeMedication(med);
}
