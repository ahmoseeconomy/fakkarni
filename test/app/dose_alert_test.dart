import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/notifications/notification_service.dart';

/// **تذكير الجرعة بيرن بنغمتنا، وبيفضل يرن — والباقي زي ما هو.**
///
/// كل حاجة هنا بتقع في صمت لو غلطت: ملف صوت أطول من ٣٠ ثانية iOS
/// بيتجاهله ويرجع للدقّة الافتراضية، ملف مش في Copy Bundle Resources
/// مش بيوصل الجهاز أصلاً، وentitlement ناقص بيحوّل Time Sensitive لإشعار
/// عادي. مفيش خطأ في أي مكان في التلاتة — فالاختبار هو الصوت.
void main() {
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  /// جسم دالة static من أول اسمها لحد الـstatic اللي بعدها.
  String member(String source, String name) {
    final start = source.indexOf(name);
    if (start < 0) throw StateError('مفيش «$name» في الخدمة');
    final end = source.indexOf('\n  static ', start + name.length);
    return source.substring(start, end < 0 ? source.length : end);
  }

  final service = code('lib/core/notifications/notification_service.dart');

  group('١ — ملف النغمة', () {
    test('iOS: CAF في الحزمة، قناة واحدة، وأقل من ٣٠ ثانية — مقروء من الملف نفسه', () {
      final file = File('ios/Runner/${NotificationService.doseSoundFile}');
      expect(file.existsSync(), isTrue, reason: file.path);
      final bytes = file.readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'caff');

      // الأقسام: [نوع ٤ بايت][طول ٨ بايت big-endian][المحتوى]
      var offset = 8;
      double? sampleRate;
      int? bytesPerPacket, framesPerPacket, channels;
      String? format;
      int? dataBytes;
      while (offset + 12 <= bytes.length) {
        final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final size = data.getInt64(offset + 4);
        final body = offset + 12;
        if (type == 'desc') {
          sampleRate = data.getFloat64(body);
          format = String.fromCharCodes(bytes.sublist(body + 8, body + 12));
          bytesPerPacket = data.getUint32(body + 16);
          framesPerPacket = data.getUint32(body + 20);
          channels = data.getUint32(body + 24);
        } else if (type == 'data') {
          dataBytes = (size < 0 ? bytes.length - body : size) - 4; // أول ٤ بايت edit count
        }
        if (size < 0) break;
        offset = body + size;
      }
      expect(format, anyOf('ima4', 'lpcm'), reason: 'iOS بيقبل PCM أو IMA4 في CAF');
      expect(channels, 1);
      expect(dataBytes, isNotNull);
      final packets = dataBytes! ~/ bytesPerPacket!;
      final seconds = packets * framesPerPacket! / sampleRate!;
      expect(seconds, lessThan(30), reason: 'أطول من ٣٠ ثانية = iOS بيرجع للنغمة الافتراضية في صمت');
      expect(seconds, greaterThan(15), reason: 'دقّة قصيرة هي بالظبط اللي «مش بترن»');
    });

    test('أندرويد: ملف واحد بنفس الاسم في res/raw', () {
      final raw = Directory('android/app/src/main/res/raw')
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.split('.').first == NotificationService.doseSoundResource)
          .toList();
      expect(raw, hasLength(1), reason: 'الاسم بيتقرا من غير امتداد — اتنين بنفس الاسم غموض');
    });

    test('المولّد في الريبو — النغمة بتاعتنا، مش عيّنة من حد', () {
      expect(File('tool/make_dose_chime.py').existsSync(), isTrue);
    });
  });

  group('٢ — Xcode', () {
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    test('النغمة في Copy Bundle Resources', () {
      expect(pbx, contains('${NotificationService.doseSoundFile} in Resources'));
      final phase = pbx.substring(pbx.indexOf('/* Begin PBXResourcesBuildPhase section */'),
          pbx.indexOf('/* End PBXResourcesBuildPhase section */'));
      expect(phase, contains(NotificationService.doseSoundFile));
    });

    test('entitlements موجودة بالمفتاح، ومربوطة في التلات إعدادات', () {
      final ent = File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(ent, contains('<key>com.apple.developer.usernotifications.time-sensitive</key>'));
      expect(ent.replaceAll(RegExp(r'\s'), ''),
          contains('time-sensitive</key><true/>'));
      expect('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'.allMatches(pbx).length, 3,
          reason: 'Debug وRelease وProfile — الناقصة بتشحن من غير Time Sensitive في صمت');
    });
  });

  group('٣ — الجرعات بس', () {
    String dose() => member(service, 'static Future<void> scheduleDose(');

    test('تذكير الجرعة بياخد النغمة على المنصّتين وTime Sensitive', () {
      expect(dose(), contains('sound: doseSoundFile'));
      expect(dose(), contains('RawResourceAndroidNotificationSound(doseSoundResource)'));
      expect(dose(), contains('InterruptionLevel.timeSensitive'));
    });

    test('والعلم المُلحّ على أندرويد — للجرعات بس', () {
      expect(NotificationService.androidFlagInsistent, 0x4, reason: 'Notification.FLAG_INSISTENT');
      expect(dose(), contains('additionalFlags: Int32List.fromList([androidFlagInsistent])'));
    });

    test('المواعيد والصيام والسلامة زي ما هم: لا نغمة ولا إلحاح', () {
      for (final name in [
        'static Future<void> scheduleCheckup(',
        'static Future<void> scheduleAppointment(',
        'static Future<void> showNow(',
      ]) {
        final body = member(service, name);
        for (final banned in ['doseSoundFile', 'doseSoundResource', 'additionalFlags', 'androidFlagInsistent']) {
          expect(body.contains(banned), isFalse, reason: '$name فيها $banned');
        }
      }
    });

    test('القناة الجديدة بالنغمة، والقديمة بتتمسح — نغمة القناة بتتثبّت وقت إنشائها', () {
      expect(NotificationService.retiredChannelIds, containsAll(['fakkarni_doses', 'fakkarni_escalation']));
      expect(NotificationService.retiredChannelIds, isNot(contains(NotificationService.doseChannelId)));
      expect(NotificationService.retiredChannelIds, isNot(contains(NotificationService.escalationChannelId)));
      final init = member(service, 'static Future<NotificationResponse?> init(');
      expect(init, contains('deleteNotificationChannel(channelId: retired)'));
      final doseChannel = member(service, 'static const _doseChannel');
      expect(doseChannel, contains('sound: RawResourceAndroidNotificationSound(doseSoundResource)'));
    });

    test('ولا fullScreenIntent، ولا الأذونات الممنوعة', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
      expect(manifest, isNot(contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')));
      expect(manifest, isNot(contains('USE_FULL_SCREEN_INTENT')));
      expect(service, isNot(contains('fullScreenIntent: true')));
    });
  });
}
