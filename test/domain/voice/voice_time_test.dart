import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/voice/voice_time.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 9, 25, h, m);

void main() {
  test('أجزاء اليوم المصرية — كل حدّ من الجهتين', () {
    expect(voiceDayPart(3), 'بالليل');
    expect(voiceDayPart(4), 'الصبح');
    expect(voiceDayPart(11), 'الصبح');
    expect(voiceDayPart(12), 'الضهر');
    expect(voiceDayPart(14), 'الضهر');
    expect(voiceDayPart(15), 'العصر');
    expect(voiceDayPart(17), 'العصر');
    expect(voiceDayPart(18), 'المغرب');
    expect(voiceDayPart(19), 'المغرب');
    expect(voiceDayPart(20), 'بالليل');
    expect(voiceDayPart(23), 'بالليل');
    expect(voiceDayPart(0), 'بالليل');
  });

  test('على الساعة: الرقم وجزء اليوم بس', () {
    expect(voiceTime(at(17)), '٥ العصر');
    expect(voiceTime(at(8)), '٨ الصبح');
    expect(voiceTime(at(13)), '١ الضهر');
    expect(voiceTime(at(18)), '٦ المغرب');
    expect(voiceTime(at(21)), '٩ بالليل');
  });

  test('نص الليل والضهر = ١٢', () {
    expect(voiceTime(at(0)), '١٢ بالليل');
    expect(voiceTime(at(12)), '١٢ الضهر');
    expect(voiceTime(at(0, 30)), '١٢ ونص بالليل');
    expect(voiceTime(at(12, 15)), '١٢ وربع الضهر');
  });

  test(':١٥ وربع، :٣٠ ونص، :٤٥ إلا ربع (بالساعة الجاية وجزئها)', () {
    expect(voiceTime(at(17, 15)), '٥ وربع العصر');
    expect(voiceTime(at(17, 30)), '٥ ونص العصر');
    expect(voiceTime(at(17, 45)), '٦ إلا ربع المغرب');
    expect(voiceTime(at(11, 45)), '١٢ إلا ربع الضهر');
    expect(voiceTime(at(23, 45)), '١٢ إلا ربع بالليل');
    expect(voiceTime(at(3, 45)), '٤ إلا ربع الصبح');
  });

  test('باقي الدقايق بالرقم', () {
    expect(voiceTime(at(17, 20)), '٥ و٢٠ دقيقة العصر');
    expect(voiceTime(at(7, 5)), '٧ و٥ دقيقة الصبح');
    expect(voiceTime(at(20, 50)), '٨ و٥٠ دقيقة بالليل');
  });
}
