import 'package:drift/drift.dart';

import '../../core/diagnostics.dart';
import '../../domain/medication/stock.dart';
import '../db/app_database.dart';
import '../dose_state.dart';

/// مخزون دوا واحد زي ما بيتعرض — الرقم وحده، والأيام محسوبة من الجدول.
class MedicationStockView {
  const MedicationStockView({
    required this.medicationId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.amount,
    required this.dosesPerDay,
    required this.warnDays,
  });

  final int medicationId;
  final String name;
  final double quantity;
  final String unit;
  final double amount;
  final double dosesPerDay;
  final int warnDays;

  int? get daysLeft => stockDaysLeft(stock: quantity, dosesPerDay: dosesPerDay, amount: amount);
  bool get isLow => stockIsLow(daysLeft: daysLeft, warnDays: warnDays);
}

/// **المخزون بيتغيّر من ٣ حاجات بس**: الإنسان بيكتبه، «اشتريت علبة
/// جديدة»، وتأكيد جرعة (أو إلغاء تأكيدها). عمره ما بيتحسب من الجدول.
class StockRepository {
  StockRepository(this._db);

  final AppDatabase _db;

  Future<StockRow?> rowFor(int medicationId) =>
      (_db.select(_db.medicationStock)..where((t) => t.medicationId.equals(medicationId))).getSingleOrNull();

  /// الرقم اللي الإنسان كتبه — بيحل محل اللي كان.
  Future<void> setQuantity(int medicationId, double quantity, {int? warnDays}) async {
    final existing = await rowFor(medicationId);
    final q = quantity < 0 ? 0.0 : quantity;
    if (existing == null) {
      await _db.into(_db.medicationStock).insert(MedicationStockCompanion.insert(
            medicationId: medicationId,
            quantity: q,
            warnDays: Value(warnDays),
          ));
    } else {
      await (_db.update(_db.medicationStock)..where((t) => t.id.equals(existing.id))).write(MedicationStockCompanion(
        quantity: Value(q),
        warnDays: warnDays == null ? const Value.absent() : Value(warnDays),
      ));
    }
  }

  Future<void> setWarnDays(int medicationId, int days) async {
    final existing = await rowFor(medicationId);
    if (existing == null) return;
    await (_db.update(_db.medicationStock)..where((t) => t.id.equals(existing.id)))
        .write(MedicationStockCompanion(warnDays: Value(days)));
  }

  /// «اشتريت علبة جديدة» — بيزوّد، ومن غير مخزون قبلها بيبدأ منها.
  Future<void> restock(int medicationId, double added) async {
    final existing = await rowFor(medicationId);
    await setQuantity(medicationId, (existing?.quantity ?? 0) + added);
  }

  /// **الانتقال الوحيد اللي بيلمس المخزون**: أي حالة → «اتاخدت» بينقّص
  /// الجرعة، و«اتاخدت» → أي حالة تانية (إلغاء) بيرجّعها. فايتة ومتخطّية
  /// ومتجاهلة من غير «اتاخدت» ما بتلمسش حاجة. دوا مالوش مخزون: ولا حاجة.
  ///
  /// **مجاملة**: المُنادي بيندهها **بعد** ما صف الجرعة اتكتب، وأي فشل هنا
  /// بيتسجّل وبيتساب — التأكيد نفسه هو الوعد، والمخزون مش هو.
  Future<void> onDoseStateChanged(int doseScheduleId, DoseState? before, DoseState after) async {
    final wasTaken = before == DoseState.taken;
    final isTaken = after == DoseState.taken;
    if (wasTaken == isTaken) return;
    try {
      final row = await (_db.select(_db.doseSchedules).join([
        innerJoin(_db.medications, _db.medications.id.equalsExp(_db.doseSchedules.medicationId)),
      ])
            ..where(_db.doseSchedules.id.equals(doseScheduleId)))
          .getSingleOrNull();
      if (row == null) return;
      final med = row.readTable(_db.medications);
      final stock = await rowFor(med.id);
      if (stock == null) return;
      final amount = doseAmountOf(med.amountLabel);
      final next = isTaken ? stockAfterTaken(stock.quantity, amount) : stockAfterUndo(stock.quantity, amount);
      await (_db.update(_db.medicationStock)..where((t) => t.id.equals(stock.id)))
          .write(MedicationStockCompanion(quantity: Value(next)));
    } catch (error) {
      diag('Stock: تعديل المخزون بعد الجرعة وقع — التأكيد نفسه اتكتب ($error)');
    }
  }

  /// كل دوا شغّال عنده مخزون، بأيامه من جدوله الحالي.
  Stream<List<MedicationStockView>> watch(int patientId) {
    final query = _db.select(_db.medicationStock).join([
      innerJoin(_db.medications, _db.medications.id.equalsExp(_db.medicationStock.medicationId)),
    ])
      ..where(_db.medications.patientId.equals(patientId) &
          _db.medications.stoppedAt.isNull() &
          _db.medications.removedAt.isNull());
    return query.watch().asyncMap((rows) async {
      final out = <MedicationStockView>[];
      for (final r in rows) {
        final med = r.readTable(_db.medications);
        final stock = r.readTable(_db.medicationStock);
        out.add(MedicationStockView(
          medicationId: med.id,
          name: med.name,
          quantity: stock.quantity,
          unit: stockUnitOf(med.amountLabel),
          amount: doseAmountOf(med.amountLabel),
          dosesPerDay: await _dosesPerDay(med.id),
          warnDays: stock.warnDays ?? defaultRefillWarnDays,
        ));
      }
      return out;
    });
  }

  Future<List<MedicationStockView>> all(int patientId) => watch(patientId).first;

  /// الجرعات اليومية الشغّالة — جداول `daily` مش موقوفة. «مرة واحدة» مش
  /// جدول يومي، فما بتدخلش في «فاضله كام يوم».
  Future<double> _dosesPerDay(int medicationId) async {
    final schedules =
        await (_db.select(_db.doseSchedules)..where((t) => t.medicationId.equals(medicationId))).get();
    return averageDosesPerDay([for (final s in schedules) (repeat: s.repeat.name, stopped: s.stoppedAt != null)]);
  }

  Future<void> markNotified(int medicationId, DateTime? at) async {
    final existing = await rowFor(medicationId);
    if (existing == null) return;
    await (_db.update(_db.medicationStock)..where((t) => t.id.equals(existing.id)))
        .write(MedicationStockCompanion(notifiedAt: Value(at)));
  }
}
