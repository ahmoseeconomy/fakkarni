import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/places/place_links.dart';
import 'package:fakkarni/domain/places/specialty.dart';

void main() {
  group('واتساب — موبايل مصري بس', () {
    test('٠١٠١٢٣٤٥٦٧٨ → ٢٠١٠١٢٣٤٥٦٧٨ بكل الأشكال', () {
      for (final raw in ['01012345678', '+201012345678', '00201012345678', '201012345678', '010 1234 5678', '٠١٠١٢٣٤٥٦٧٨', '+20 10 1234-5678']) {
        expect(egyptMobileWhatsApp(raw), '201012345678', reason: raw);
      }
      expect(egyptMobileWhatsApp('01112345678'), '201112345678');
      expect(egyptMobileWhatsApp('01212345678'), '201212345678');
      expect(egyptMobileWhatsApp('01512345678'), '201512345678');
    });

    test('أرضي أو مش مصري أو ناقص → null (الزرار ما بيظهرش)', () {
      for (final raw in ['+20 2 1234567', '0223456789', '01312345678', '0101234567', '+966501234567', '', 'مفيش']) {
        expect(egyptMobileWhatsApp(raw), isNull, reason: raw);
      }
    });

    test('الرابط wa.me بالرقم الدولي', () {
      expect(whatsAppUri('201012345678').toString(), 'https://wa.me/201012345678');
    });
  });

  test('«الطريق» — جوجل ماب بالاتجاهات من غير مفتاح، وأبل بديل', () {
    expect(googleDirectionsUri(30.0444, 31.2357).toString(), 'https://www.google.com/maps/dir/?api=1&destination=30.0444,31.2357');
    expect(googleDirectionsUri(30.0444, 31.2357).toString(), isNot(contains('key=')));
    expect(appleDirectionsUri(30.0444, 31.2357).toString(), 'https://maps.apple.com/?daddr=30.0444,31.2357');
  });

  group('التخصص', () {
    test('من وسم OSM (بكذا قيمة) ومن كلمة في الاسم', () {
      expect(specialtiesOf(osmSpeciality: 'ophthalmology'), {Specialty.eyes});
      expect(specialtiesOf(osmSpeciality: 'dentistry;orthodontics'), {Specialty.dental});
      expect(specialtiesOf(name: 'عيادة د. أحمد للعيون'), {Specialty.eyes});
      expect(specialtiesOf(name: 'مركز الأسنان الحديث'), {Specialty.dental});
      expect(specialtiesOf(name: 'Smile Dental Clinic'), {Specialty.dental});
      expect(specialtiesOf(name: 'عيادة الأطفال'), {Specialty.children});
    });

    test('من غير وسم ولا كلمة → مفيش تخصص — ما بنخمّنش', () {
      expect(specialtiesOf(name: 'عيادة د. سامي'), isEmpty);
      expect(specialtiesOf(), isEmpty);
    });

    test('الكلمة المتقالة ← التخصص', () {
      expect(specialtyFromWord('رمد'), Specialty.eyes);
      expect(specialtyFromWord('أسنان'), Specialty.dental);
      expect(specialtyFromWord('باطنة'), Specialty.internal);
      expect(specialtyFromWord('نسا'), Specialty.women);
      expect(specialtyFromWord('مخ'), Specialty.neuro);
      expect(specialtyFromWord('أنف'), Specialty.ent);
      expect(specialtyFromWord('مسالك'), Specialty.urology);
      expect(specialtyFromWord('قلب'), Specialty.heart);
      expect(specialtyFromWord('عظام'), Specialty.bones);
      expect(specialtyFromWord('جلدية'), Specialty.skin);
      expect(specialtyFromWord('صيدلية'), isNull);
    });
  });
}
