// **العلبة بتقول الدوا إيه — مش إمتى.**
//
// القاعدة اللي الملف ده موجود عشانها: الورقة اللي على العلبة ما بتعرفش
// الراجل ده اتقاله ياخد كام ولا امتى — ده كلام الدكتور. فمفيش طريق يوصل
// منه موعد للفورم: مش لأننا بنفلتره، لأن الـschema مالوش خانة أصلاً.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fakkarni/ai/gemini_config.dart';
import 'package:fakkarni/ai/package_reader.dart';
import 'package:fakkarni/ai/package_reading.dart';
import 'package:fakkarni/ai/prescription_reader.dart';

Map<String, dynamic> _field(String? value, double confidence) => {
      'value': value,
      'confidence': confidence,
    };

Map<String, dynamic> _box({
  String? brand = 'Concor',
  double brandConfidence = 0.97,
  String? ingredient = 'Bisoprolol fumarate',
  double ingredientConfidence = 0.94,
  String? strength = '5 mg',
  double strengthConfidence = 0.96,
  String? form = 'tablets',
  String? packSize = '30 tablets',
  Map<String, dynamic> extra = const {},
}) =>
    {
      'brand': _field(brand, brandConfidence),
      'activeIngredient': _field(ingredient, ingredientConfidence),
      'strength': _field(strength, strengthConfidence),
      'form': _field(form, 0.9),
      'packSize': _field(packSize, 0.9),
      ...extra,
    };

/// رد Gemini كامل حوالين الـJSON بتاعنا.
http.Client _client(Map<String, dynamic> body, {void Function(String)? onRequest}) =>
    MockClient((request) async {
      onRequest?.call(request.body);
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': jsonEncode(body)},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

GeminiPackageReader _reader(http.Client client) => GeminiPackageReader(
      const GeminiConfig(apiKey: 'k'),
      transport: GeminiPrescriptionReader(const GeminiConfig(apiKey: 'k'), client: client),
    );

final _image = Uint8List.fromList([1, 2, 3]);

void main() {
  group('اللي بيتقرا من العلبة', () {
    test('الاسم والتركيز بيتلزقوا في خانة واحدة زي ما الفورم بيتوقع', () async {
      final reading = await _reader(_client(_box())).read(_image);
      expect(reading.nameField, 'Concor 5 mg');
      expect(reading.ingredientField, 'Bisoprolol fumarate');
      expect(reading.formField, 'tablets');
      expect(reading.packSizeField, '30 tablets');
      expect(reading.nothingClear, isFalse);
    });

    test('تركيز مش واضح = الاسم لوحده، مش اسم بتركيز مخترع', () async {
      final reading =
          await _reader(_client(_box(strength: '5 mg', strengthConfidence: 0.4))).read(_image);
      expect(reading.nameField, 'Concor');
      expect(reading.unclear, contains('التركيز'));
    });
  });

  group('**ولا جدول جرعات من علبة** (القاعدة ٤)', () {
    test('الموديل بعت مواعيد ومدة → اتاكلوا، ومفيش حقل بيشيلهم', () async {
      final reading = await _reader(_client(_box(extra: {
        // الشكل اللي موديل ممكن يرجّعه لو اتحمّس — كل ده بيتساب.
        'dose': _field('1 tablet', 0.99),
        'frequency': _field('twice daily', 0.99),
        'timings': [
          {'anchor': 'breakfast', 'offsetMinutes': -30},
        ],
        'durationDays': _field('14 days', 0.99),
        'instructions': _field('قرص كل ١٢ ساعة', 0.99),
      }))).read(_image);

      // القراية فيها الحقول الخمسة وبس — مفيش عضو تاني في الكلاس أصلاً.
      expect(reading.nameField, 'Concor 5 mg');
      expect(reading.ingredientField, 'Bisoprolol fumarate');
      expect(reading.formField, 'tablets');
      expect(reading.packSizeField, '30 tablets');
      // وولا واحدة من القيم دي وصلت أي حقل بيتعرض.
      for (final leaked in ['1 tablet', 'twice daily', '14 days', 'قرص كل ١٢ ساعة']) {
        for (final field in [
          reading.nameField,
          reading.ingredientField,
          reading.formField,
          reading.packSizeField,
        ]) {
          expect(field, isNot(contains(leaked)), reason: 'تسريب موعد: $leaked');
        }
      }
    });

    test('والـschema نفسه مفيهوش أي خانة لجرعة ولا موعد', () {
      final properties = (packageSchema['properties']! as Map).keys.toSet();
      expect(properties, {'brand', 'activeIngredient', 'strength', 'form', 'packSize'});
      final json = jsonEncode(packageSchema).toLowerCase();
      for (final banned in [
        'dose',
        'timing',
        'frequency',
        'schedule',
        'duration',
        'instruction',
        'anchor',
      ]) {
        expect(json.contains(banned), isFalse, reason: 'الـschema فيه «$banned»');
      }
    });

    test('والتعليمات مكتوبة للموديل نفسه — مش اعتماد على الفلترة', () {
      final system = GeminiPackageReader.systemInstruction;
      expect(system, contains('NEVER return a dose, a frequency, a schedule'));
      expect(system, contains('only their doctor knows'));
      expect(system, contains('If the box prints dosing directions, ignore them completely'));
      // ومفيش نصيحة ولا تشخيص (القاعدة ٦)
      expect(system, contains('Do NOT interpret, diagnose, recommend or advise'));
    });
  });

  group('الثقة الواطية = فراغ، مش تخمين', () {
    test('اسم مش واضح → مفيش اسم، والشاشة بتقول صوّر تاني', () async {
      final reading =
          await _reader(_client(_box(brand: 'Conc…', brandConfidence: 0.5))).read(_image);
      expect(reading.nameField, isNull);
      expect(reading.nothingClear, isTrue,
          reason: 'نص اسم بثقة عالية هو بالظبط الغلط اللي بيوصل قايمة أدوية');
    });

    test('ومادة فعّالة مش واضحة بتتساب فاضية — والاسم بيفضل', () async {
      final reading = await _reader(
              _client(_box(ingredient: 'Bisopr…', ingredientConfidence: 0.3)))
          .read(_image);
      expect(reading.nameField, 'Concor 5 mg');
      expect(reading.ingredientField, isNull);
      expect(reading.unclear, contains('المادة الفعّالة'));
    });

    test('وحقل مش مطبوع خالص بيرجع null من غير ما يكسر القراية', () async {
      final reading = await _reader(_client(_box(
        ingredient: null,
        ingredientConfidence: 0,
        packSize: null,
      ))).read(_image);
      expect(reading.nameField, 'Concor 5 mg');
      expect(reading.ingredientField, isNull);
      expect(reading.packSizeField, isNull);
    });
  });

  group('الشريط ليه فقرته', () {
    test('البرومبت بيطلب الضهر وبيمنع تكملة الاسم الناقص', () {
      final prompt = GeminiPackageReader.prompt;
      expect(prompt, contains('blister strip'));
      expect(prompt, contains('reflective foil'));
      expect(prompt, contains('return null rather than completing it'));
      expect(prompt, contains('Partial text is a reason for low confidence, not for inference'));
    });
  });

  group('نفس النقل بالحرف', () {
    test('المفتاح في x-goog-api-key، والصورة inline، والـschema مبعوت', () async {
      String? sent;
      Map<String, String>? headers;
      final client = MockClient((request) async {
        sent = request.body;
        headers = request.headers;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': jsonEncode(_box())},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await _reader(client).read(_image);

      expect(headers!.keys.map((k) => k.toLowerCase()), contains('x-goog-api-key'));
      expect(headers!.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      final body = jsonDecode(sent!) as Map<String, dynamic>;
      expect(jsonEncode(body), contains('inline_data'));
      expect(jsonEncode(body), contains('brand'));
    });

    test('ورسالة العطل بتاعة العلبة، مش بتاعة الروشتة', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      await expectLater(
        () => _reader(client).read(_image),
        throwsA(isA<PrescriptionReadException>()
            .having((e) => e.message, 'message', contains('العلبة'))),
      );
    });
  });
}
