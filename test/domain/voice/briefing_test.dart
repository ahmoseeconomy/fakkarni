import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/briefing.dart';

void main() {
  final morning = DateTime(2026, 9, 25, 7, 30);

  test('مفيش أدوية ولا مواعيد ولا امبارح = مفيش ملخص (ما بنتكلمش عشان نتكلم)', () {
    expect(briefingText(BriefingInput(now: morning, dosesToday: 0)), isNull);
  });

  test('كذا دوا: العدد وأول جرعة بكلام المرساة', () {
    final text = briefingText(BriefingInput(
      now: morning,
      dosesToday: 3,
      firstDoseAt: DateTime(2026, 9, 25, 8),
      firstDoseWording: 'بعد الفطار بنص ساعة',
    ));
    expect(text, 'صباح الخير. النهارده عندك ٣ أدوية، أولها الساعة ٨ الصبح بعد الفطار بنص ساعة.');
  });

  test('دوا واحد بساعة ثابتة: «معادها» ومن غير كلام مرساة', () {
    final text = briefingText(BriefingInput(
      now: DateTime(2026, 9, 25, 19),
      dosesToday: 1,
      firstDoseAt: DateTime(2026, 9, 25, 21),
    ));
    expect(text, 'مساء الخير. النهارده عندك دوا واحد، معادها الساعة ٩ بالليل.');
  });

  test('ميعاد النهارده', () {
    final text = briefingText(BriefingInput(
      now: morning,
      dosesToday: 2,
      firstDoseAt: DateTime(2026, 9, 25, 8),
      firstDoseWording: 'مع الفطار',
      appointments: [BriefingAppointment(kind: 'دكتور', at: DateTime(2026, 9, 25, 11))],
    ));
    expect(text, contains('النهارده عندك دواين، أولها الساعة ٨ الصبح مع الفطار.'));
    expect(text, contains('وعندك ميعاد دكتور الساعة ١١ الصبح.'));
  });

  test('امبارح كامل + عدّ ورا بعض', () {
    final text = briefingText(BriefingInput(
      now: morning,
      dosesToday: 3,
      firstDoseAt: DateTime(2026, 9, 25, 8),
      yesterday: YesterdayOutcome.complete,
      streak: 4,
    ));
    expect(text, endsWith('امبارح خدت كل أدويتك في معادها. برافو، دي رابع يوم ورا بعض.'));
    // يوم واحد بس: «برافو» من غير عدّ
    final one = briefingText(BriefingInput(now: morning, dosesToday: 1, yesterday: YesterdayOutcome.complete, streak: 1));
    expect(one, endsWith('امبارح خدت كل أدويتك في معادها. برافو.'));
  });

  test('امبارح فات حاجة: «يوم جديد» — من غير لوم ولا رقم', () {
    final text = briefingText(BriefingInput(now: morning, dosesToday: 2, yesterday: YesterdayOutcome.missed, streak: 0));
    expect(text, 'صباح الخير. النهارده عندك دواين. النهارده يوم جديد، وأنا معاك.');
    expect(text, isNot(contains('فات')));
  });

  test('الكلمات: الأعداد والترتيب', () {
    expect(dosesWord(2), 'دواين');
    expect(dosesWord(11), '١١ دوا');
    expect(ordinalDay(10), 'عاشر يوم');
    expect(ordinalDay(12), 'يوم ١٢');
  });
}
