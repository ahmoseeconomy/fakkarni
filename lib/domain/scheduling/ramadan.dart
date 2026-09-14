/// وضع رمضان — ثمرة المراسي.
///
/// الروشتة بتقول «قبل الفطار»، وفي رمضان الفطار هو المغرب. فبدل ما نعدّل
/// كل دوا لوحده، بنبدّل الروتين مرة واحدة وكل جرعة مرساة بتتحرك معاه.
/// الساعات الثابتة ما بتتلمسش — زي أي تعديل روتين تاني.
///
/// دارت نقية: مفيش هنا تخزين ولا واجهة. اللي بيخزّن الأصل ويرجّعه
/// بالحرف هو المستودع، مش الدالة دي — هي بتحسب بس.
library;

import 'day_routine.dart';

/// الفطار والسحور — بيتحطّوا مرة، ومش بنجيبهم من أي API المرة دي.
class RamadanTimes {
  const RamadanTimes({required this.iftar, required this.suhoor});

  final MinuteOfDay iftar;
  final MinuteOfDay suhoor;

  /// قيم القاهرة التقريبية — نقطة بداية المستخدم بيعدّلها، مش مواقيت.
  static final RamadanTimes cairoDefaults = RamadanTimes(
    iftar: MinuteOfDay.hm(18),
    suhoor: MinuteOfDay.hm(3, 30),
  );

  RamadanTimes copyWith({MinuteOfDay? iftar, MinuteOfDay? suhoor}) =>
      RamadanTimes(iftar: iftar ?? this.iftar, suhoor: suhoor ?? this.suhoor);

  @override
  bool operator ==(Object other) =>
      other is RamadanTimes && other.iftar == iftar && other.suhoor == suhoor;

  @override
  int get hashCode => Object.hash(iftar, suhoor);
}

/// النوم بعد السحور بساعة — عرف تشغيلي بيتعدّل من «عدّل يومك»، مش توجيه.
const int sleepAfterSuhoorMinutes = 60;

/// روتين رمضان من الروتين الأصلي.
///
/// - الفطار → الإفطار (المغرب).
/// - الغدا → الإفطار كمان: مفيش غدا في الصيام، وجرعة «قبل الغدا» لو
///   اتشالت كانت هتختفي في صمت — وده دوا بيقف من غير ما حد يقرّر
///   (القاعدة ٣ بروحها). فبتندمج مع جرعات الفطار في تذكير واحد.
/// - العشا → السحور. بيقع قبل الصحيان بالساعة، فالمحرّك بيحطّه في آخر
///   يوم الروتين (التاريخ اللي بعده) — نفس مسار «النوم الساعة ١».
/// - النوم → بعد السحور بساعة. الصحيان زي ما هو.
///
/// الأصل ما بيتغيّرش — الدالة بترجّع روتين جديد.
DayRoutine ramadanRoutine(DayRoutine original, RamadanTimes times) =>
    DayRoutine(
      wake: original.wake,
      breakfast: times.iftar,
      lunch: times.iftar,
      dinner: times.suhoor,
      sleep: MinuteOfDay(
        (times.suhoor.minutes + sleepAfterSuhoorMinutes) % 1440,
      ),
    );
