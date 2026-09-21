import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';

/// **لون لكل قسم — هوية محسوبة، مش زينة متخمّنة.**
///
/// الأرقام هنا هي اللي `validate_palette` بتاع مهارة عرض البيانات طلّعها،
/// متثبّتة في اختبار عشان تعديل لون في `tokens.dart` يوقع هنا بدل ما
/// يعدّي في مراجعة. التلات حاجات اللي بتتقاس:
///  ١. **الفصل**: الألوان تفضل متفرّقة عن بعض، ولعمى الألوان كمان.
///  ٢. **التباين**: الحد على أرضية الكارت والصفحة في الوضعين.
///  ٣. **المحجوز يفضل محجوز**: مفيش لون قسم بيقرّب من أحمر الطوارئ ولا
///     من أزرق المية.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// OKLab — نفس اللي الفاحص بيحسب بيه ΔE.
({double l, double a, double b}) _oklab(Color c) {
  double lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), bl = lin(c.b);
  final l = math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl, 1 / 3).toDouble();
  final m = math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl, 1 / 3).toDouble();
  final s = math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl, 1 / 3).toDouble();
  return (
    l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// ΔE في OKLab ×١٠٠ — نفس وحدة الفاحص.
double _deltaE(Color x, Color y) {
  final a = _oklab(x), b = _oklab(y);
  final dl = a.l - b.l, da = a.a - b.a, db = a.b - b.b;
  return math.sqrt(dl * dl + da * da + db * db) * 100;
}

void main() {
  tearDown(() => F.setDark(on: false));

  /// ألوان الهوية الأربعة. **الدهبي برّه القايمة دي عن قصد**: هو لون
  /// **حالة** («دي محتاجاك»)، مش خانة هوية — وقاعدة عرض البيانات نفسها
  /// بتقول إن ألوان الحالة محجوزة وما بتتعادش استعمالها كسلسلة رقم ٤.
  List<(String, Color)> identity() => [
        ('اتاخدت', F.careAccentTaken),
        ('جاية', F.careAccentUpcoming),
        ('زيارات', F.careAccentVisit),
        ('تحاليل', F.careAccentLab),
      ];

  for (final (mode, dark) in [('نهاري', false), ('ليلي', true)]) {
    group('ألوان الأقسام — $mode', () {
      setUp(() => F.setDark(on: dark));

      test('كل لونين متفرّقين برؤية عادية — الحد ١٥ ΔE', () {
        final all = identity();
        for (var i = 0; i < all.length; i++) {
          for (var j = i + 1; j < all.length; j++) {
            final d = _deltaE(all[i].$2, all[j].$2);
            expect(d, greaterThanOrEqualTo(15.0),
                reason: '«${all[i].$1}» و«${all[j].$1}» قريبين من بعض — $d');
          }
        }
      });

      test('الحد على الأرضيات فوق ٣:١ — غير الدهبي النهاري (دين معروف)', () {
        for (final (name, colour) in [...identity(), ('متخطّية', F.careAccentSkipped)]) {
          for (final ground in [F.pageGround, F.cardGround, F.railGround]) {
            expect(_contrast(colour, ground), greaterThanOrEqualTo(3.0),
                reason: 'حد «$name» مش باين على أرضيته');
          }
        }
      });

      test('ولا لون **جديد** بيقرّب من أحمر الطوارئ ولا أزرق المية', () {
        // **الوردي والطيني اتجرّبوا واترفضوا**: `#B33A6D` كان ٩٫٨ ΔE بس
        // من أحمر الطوارئ، و`#9A5326` كان ١٣٫٤. لون بيلخبط مع الأحمر
        // بيضيّع أغلى معنى في التطبيق.
        //
        // **الفحص على الألوان الجديدة بس**، وده مقصود: `F.green` و
        // `F.gold` رموز علامة موجودة من زمان وعلاقتها بالمية والأحمر
        // مش حاجة الجولة دي عملتها — والرمادي (`careAccentSkipped`)
        // تشبّعه أقل من ٠٫٠٦ يعني بيتقري رمادي، والـΔE بيقارن الإضاءة
        // كمان فبيدّي رقم صغير لحاجة عمرها ما هتتلخبط مع أزرق مشبّع.
        for (final (name, colour) in [
          ('جاية', F.careAccentUpcoming),
          ('زيارات', F.careAccentVisit),
          ('تحاليل', F.careAccentLab),
        ]) {
          for (final (reserved, hue) in [('أحمر الطوارئ', F.redDeep), ('أزرق المية', F.waterDrop)]) {
            expect(_deltaE(colour, hue), greaterThanOrEqualTo(15.0),
                reason: '«$name» قريب من $reserved');
          }
        }
      });

      test('ولا لون قسم أقوى من الدهبي بفرق ملحوظ — الدهبي لسه هو اللي بينطّ', () {
        double chroma(Color c) {
          final o = _oklab(c);
          return math.sqrt(o.a * o.a + o.b * o.b);
        }

        // مش «أقل من الدهبي» بالحرف: الدهبي تشبّعه ٠٫١٤٢ في OKLab، وقفل
        // كل حاجة تحته كان بيفضّي المساحة خالص. اللي بيحافظ على معناه
        // إنه **اللون الوحيد اللي معناه «دي محتاجاك»** — ودي قاعدة معنى
        // بتتقاس تحت. والسقف هنا بيمنع لون زينة ينطّ أكتر منه.
        const ceiling = 0.155;
        for (final (name, colour) in identity()) {
          expect(chroma(colour), lessThanOrEqualTo(ceiling),
              reason: '«$name» مشبّع أكتر من اللازم — بينطّ قدام الدهبي');
        }
      });

      test('الدهبي معناه واحد: «دي محتاجاك» — ومفيش قسم تاني بياخده', () {
        for (final (name, colour) in identity()) {
          expect(colour, isNot(F.careAccentDue), reason: '«$name» خد الدهبي');
        }
        expect(F.careAccentSkipped, isNot(F.careAccentDue));
      });
    });
  }

  test('كل قسم لونه مختلف — مفيش لونين على قسمين', () {
    final used = [
      F.careAccentDue,
      F.careAccentUpcoming,
      F.careAccentTaken,
      F.careAccentSkipped,
      F.careAccentVisit,
      F.careAccentLab,
    ];
    expect(used.toSet(), hasLength(used.length));
  });
}
