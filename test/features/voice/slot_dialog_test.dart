// E2: «كلّمني» بيسأل عن الناقص واحد واحد — ومفيش ساعة مننا.
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/medication/medication_purpose.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/domain/voice/nlu/nlu.dart';
import 'package:fakkarni/features/voice/dialog/slot_dialog.dart';

void main() {
  final now = DateTime(2026, 10, 4, 10); // الحد

  MedDialog med(String said) => MedDialog.fromNlu(understandUtterance(said, now: now));

  group('ضيف دوا', () {
    test('«ضيف دوا» لوحدها → الاسم، وبعدين كام مرة، وبعدين كل جرعة — مفيش ٩ و٩ مننا', () {
      final d = med('ضيف دوا');
      expect(d.question!.id, 'dlg_med_name');
      expect(d.answer('كونكور', now: now), isTrue);
      expect(d.name, isNotNull);
      expect(d.question!.id, 'dlg_med_times');
      expect(d.answer('مرتين', now: now), isTrue);
      expect(d.question!.text, 'الجرعة رقم ١ الساعة كام؟');
      expect(d.answer('تسعة الصبح', now: now), isTrue);
      expect(d.question!.text, 'الجرعة رقم ٢ الساعة كام؟');
      expect(d.answer('تسعة بالليل', now: now), isTrue);
      // وبعد الساعات: النوع والغرض — اختياريين، «عدّي» بتعدّيهم (٥ أكتوبر)
      expect(d.question!.id, 'dlg_med_form');
      expect(d.answer('عدّي', now: now), isTrue);
      expect(d.question!.id, 'dlg_med_purpose');
      expect(d.answer('عدّي', now: now), isTrue);
      expect(d.complete, isTrue);
      expect(d.form, isNull, reason: '«عدّي» = الخانة فاضية، مش تخمين');
      expect(d.purpose, isNull);
      expect(d.minutes.map((m) => m.minutes), [9 * 60, 21 * 60]);
    });

    test('«نوعه إيه؟» و«الدوا ده لإيه؟» — بيتجاوبوا، والسكوت بيعدّي، والمش مفهومة مرتين بتعدّي بخانة فاضية', () {
      final d = med('ضيف دوا كونكور الساعة ٩ بالليل');
      expect(d.question!.id, 'dlg_med_form');
      expect(d.answer('حباية', now: now), isTrue);
      expect(d.form, MedicineForm.tablet);
      expect(d.question!.id, 'dlg_med_purpose');
      expect(d.answer('للضغط', now: now), isTrue);
      expect(d.purpose, MedicationPurpose.pressure);
      expect(d.complete, isTrue);
      expect(d.summary(), contains('قرص'));
      expect(d.summary(), contains('للضغط'));

      // السكوت بيعدّي (الـflow بينده skipOptional على text == null)
      final q = med('ضيف دوا كونكور الساعة ٩ بالليل');
      expect(q.question!.id, 'dlg_med_form');
      expect(q.skipOptional(), isTrue);
      expect(q.question!.id, 'dlg_med_purpose');
      expect(q.skipOptional(), isTrue);
      expect(q.complete, isTrue);
      // وعلى سؤال أساسي السكوت **مش** بيعدّي
      final r = med('ضيف دوا');
      expect(r.skipOptional(), isFalse, reason: 'الاسم مش اختياري');

      // مش مفهومة مرتين على الاختياري = عدّي بخانة فاضية — مش الفورم
      final w = med('ضيف دوا كونكور الساعة ٩ بالليل');
      expect(w.answer('أبيض', now: now), isFalse);
      expect(w.answer('أبيض', now: now), isTrue, reason: 'التانية بتعدّي');
      expect(w.form, isNull);
      expect(w.question!.id, 'dlg_med_purpose');
    });

    test('«الساعة ٩» من غير الصبح/بالليل → «الصبح ولا بالليل؟» — مش تخمين', () {
      final d = med('ضيف دوا كونكور');
      d.answer('مرة واحدة', now: now);
      expect(d.answer('٩', now: now), isTrue);
      expect(d.question!.id, 'dlg_part_of_day');
      expect(d.question!.text, 'الساعة ٩ الصبح ولا بالليل؟');
      expect(d.answer('بالليل', now: now), isTrue);
      expect(d.minutes.single.minutes, 21 * 60);
    });

    test('«كل ١٢ ساعة» → أول جرعة بس، والباقي بالفاصل زي الفورم', () {
      final d = med('ضيف دوا أوجمنتين كل ١٢ ساعة');
      expect(d.question!.text, 'أول جرعة الساعة كام؟');
      expect(d.answer('٨ الصبح', now: now), isTrue);
      expect(d.minutes.map((m) => m.minutes), [8 * 60, 20 * 60]);
    });

    test('إجابة مش مفهومة بتتعدّ، ونفس الساعة مرتين مش مقبولة', () {
      final d = med('ضيف دوا كونكور مرتين');
      expect(d.answer('مش عارف', now: now), isFalse);
      expect(d.tries, 1);
      d.answer('٩ الصبح', now: now);
      expect(d.answer('٩ الصبح', now: now), isFalse, reason: 'نفس الساعة');
      expect(d.tries, 1);
      expect(d.answer('٩ بالليل', now: now), isTrue);
      expect(d.tries, 0);
    });

    test('«لا» عمرها ما تبقى اسم دوا', () {
      final d = med('ضيف دوا');
      expect(d.answer('لا', now: now), isFalse);
      expect(d.name, isNull);
    });

    test('الجملة كاملة من الأول → مفيش أسئلة، والملخص بالكلام', () {
      // النوع والغرض في الجملة = ولا سؤال عليهم (قرار المالك، ٥ أكتوبر)
      final d = med('ضيف دوا كونكور قرص للضغط الساعة ٩ بالليل بعد الأكل');
      expect(d.complete, isTrue);
      expect(d.form, MedicineForm.tablet);
      expect(d.purpose, MedicationPurpose.pressure);
      expect(d.summary(), contains('٩:٠٠ م'));
      expect(d.summary(), contains('بعد الأكل'));
      expect(d.summary(duplicateOf: 'Concor'), contains('Concor عندك خلاص'));
    });
  });

  group('احجز ميعاد', () {
    test('من غير يوم → «يوم إيه؟»، وبعدين الساعة، و«من غير ساعة» مقبولة', () {
      final b = BookingDialog(lab: false, title: 'د. حسام', doctor: 'د. حسام');
      expect(b.question!.id, 'dlg_appt_day');
      expect(b.answer('يوم الخميس', now: now), isTrue);
      expect(b.day!.weekday, DateTime.thursday);
      expect(b.question!.id, 'dlg_appt_time');
      expect(b.answer('من غير ساعة', now: now), isTrue);
      expect(b.complete, isTrue);
      expect(b.time, isNull);
    });

    test('«الساعة ٥» → «الصبح ولا بالليل؟»', () {
      final b = BookingDialog(lab: true, title: 'تحليل', day: DateTime(2026, 10, 6));
      expect(b.answer('٥', now: now), isTrue);
      expect(b.question!.id, 'dlg_part_of_day');
      expect(b.answer('العصر', now: now), isTrue);
      expect(b.time, 17 * 60);
    });

    test('يوم فات مش ميعاد', () {
      final b = BookingDialog(lab: false, title: 'زيارة دكتور');
      expect(b.answer('امبارح', now: now), isFalse);
    });
  });
}
