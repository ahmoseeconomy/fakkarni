import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:path_provider/path_provider.dart';

/// السابقة اللي بيتفلتر عليها في Console.app — **نفسها في سويفت ودارت**،
/// عشان فلتر واحد يجيب السكّة كلها من أول ما النظام يشغّل العملية.
const diagPrefix = 'FKDIAG ';

/// الملف اللي الناحيتين بيكتبوا فيه — في مجلد Documents بتاع التطبيق،
/// وهو نفسه اللي `getApplicationDocumentsDirectory()` بترجّعه على iOS.
const diagFileName = 'fkdiag.log';

/// أحدث [diagMaxLines] سطر — الأقدم بيتشال لما الملف يعدّي [_trimAtBytes].
const diagMaxLines = 200;
const _trimAtBytes = 32 * 1024;

File? _sink;
bool _resolved = false;

/// مسار الملف من غير أي إضافة — `HOME` على iOS هو جذر حاوية التطبيق.
///
/// الطريق ده مقصود: `diag` بتتنده من isolate صحوة شاشة القفل، واللحظة
/// دي مش وقت نداء قناة ممكن يعلّق. لو `HOME` ما نفعش (أندرويد مثلاً)
/// بنفضل من غير ملف لحد ما [diagResolveDirectory] تتنده من الواجهة.
///
/// **مقفول على iOS عن قصد**: الحيلة دي حقيقة عن حاوية iOS، وعلى جهاز
/// المطوّر `$HOME/Documents` موجود فعلاً — يعني `flutter test` كان
/// هيكتب في مجلد المستندات بتاع صاحب الجهاز.
File? _resolveSink() {
  if (_resolved) return _sink;
  _resolved = true;
  try {
    // سويفت بتحط المسار في البيئة عند الإطلاق (AppDelegate) — الأكيد
    final docs = Platform.environment['FAKKARNI_DOCS'];
    if (docs != null && docs.isNotEmpty) {
      _sink = File('$docs/$diagFileName');
      return _sink;
    }
    if (!Platform.isIOS) return null;
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final docs = Directory('$home/Documents');
      if (docs.existsSync()) _sink = File('${docs.path}/$diagFileName');
    }
  } catch (_) {
    // تشخيص فاشل عمره ما يوقّع اللي بيشخّصه
  }
  return _sink;
}

/// بديل بيمرّ على `path_provider` — **من الواجهة بس**، مش من الـisolate.
///
/// بتتنده قبل قراية السجل. على iOS غالباً [_resolveSink] تكون سبقتها؛
/// على أندرويد دي هي اللي بتلاقي المجلد، فالسطور اللي قبل أول فتحة
/// للشاشة بتضيع هناك — والسكّة اللي بندوّر عليها iOS أصلاً.
Future<File?> diagResolveDirectory() async {
  final existing = _resolveSink();
  if (existing != null) return existing;
  try {
    final dir = await getApplicationDocumentsDirectory();
    _sink = File('${dir.path}/$diagFileName');
  } catch (_) {}
  return _sink;
}

String _stamp(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
      '.${now.millisecond.toString().padLeft(3, '0')}';
}

/// سطر تشخيص للمطوّر — **بيطبع في debug وprofile، وساكت في release**.
///
/// `debugPrint` نفسها **مالهاش أي بوابة**: توثيقها بيقول بالنص إنها
/// «بتطبع على الكونسول حتى في release». فالسطور دي كانت بتشحن جوّه كل
/// IPA وAPK، وفيها أسماء جداول وحالات جرعات ورسايل أخطاء خام.
///
/// والبوابة الغلط هي `kDebugMode`: نسخة الـprofile هي **الوحيدة** اللي
/// تقدر ترد على سؤال صحوة شاشة القفل على iOS — من iOS 14 النظام بيرفض
/// يشغّل تطبيق debug من غير أدوات التطوير، فأول ما `flutter run` يفصل،
/// الـisolate عمره ما هيشتغل. تشخيص متقفل على `kDebugMode` بيسكت بالظبط
/// في النسخة اللي محتاجينه فيها.
///
/// فالقاعدة بقت: **تشخيص بيطبع بس → `!kReleaseMode`؛ تشخيص بيظهر على
/// الشاشة → `kDebugMode`.** لوحة خام قدام مريض في نسخة profile حاجة
/// تانية خالص عن سطر في Console.app.
///
/// **وبيتكتب في ملف كمان**، لأن السؤال ده مالوش مصحّح متوصّل: الـisolate
/// بيصحى والتطبيق مقفول، والسطر اللي بيتطبع في os_log بيروح مع الجلسة.
/// الملف بيفضل، وسويفت بتكتب في نفس الملف — فالترتيب بين الناحيتين بيبان.
///
/// **وفي release فيه باب واحد للمطوّر** (نسخة TestFlight، ٢٦ سبتمبر ٢٠٢٦):
/// لو ملف [diagOptInFileName] موجود جنب السجل، `diag` بتكتب في **الملف
/// بس** — مفيش `debugPrint` في release أبداً. الباب ملف مش
/// `shared_preferences` عن قصد: الـisolate بيشوفه بنفس [_resolveSink]
/// من غير أي نداء قناة، فصحوة شاشة القفل بتتسجّل هي كمان.
void diag(String message) {
  if (kReleaseMode && !_releaseOptIn()) return;
  final line = '$diagPrefix$message';
  if (!kReleaseMode) debugPrint(line);
  _append('${_stamp(DateTime.now())}  $line');
}

/// علامة «باب المطوّر مفتوح» في release — ملف فاضي جنب [diagFileName].
const diagOptInFileName = 'fkdiag.on';

bool? _optIn;

bool _releaseOptIn() {
  if (_optIn case final v?) return v;
  final sink = _resolveSink();
  if (sink == null) return false;
  try {
    _optIn = File('${sink.parent.path}/$diagOptInFileName').existsSync();
  } catch (_) {
    _optIn = false;
  }
  return _optIn!;
}

/// الباب مفتوح؟ — من الواجهة (بتمرّ على `path_provider` لو لزم).
Future<bool> diagReleaseOptIn() async {
  final sink = await diagResolveDirectory();
  if (sink == null) return false;
  try {
    return File('${sink.parent.path}/$diagOptInFileName').existsSync();
  } catch (_) {
    return false;
  }
}

/// بيفتح الباب أو يقفله — بيرجّع الحالة الفعلية بعد الكتابة.
Future<bool> setDiagReleaseOptIn(bool on) async {
  final sink = await diagResolveDirectory();
  if (sink == null) return false;
  try {
    final marker = File('${sink.parent.path}/$diagOptInFileName');
    if (on) {
      marker.writeAsStringSync('', flush: true);
    } else if (marker.existsSync()) {
      marker.deleteSync();
    }
    _optIn = null;
    return marker.existsSync();
  } catch (_) {
    return false;
  }
}

void _append(String line) {
  final file = _resolveSink();
  if (file == null) return;
  try {
    file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    if (file.lengthSync() > _trimAtBytes) _trim(file);
  } catch (_) {}
}

void _trim(File file) {
  try {
    final lines = file.readAsLinesSync();
    if (lines.length <= diagMaxLines) return;
    file.writeAsStringSync(
      '${lines.sublist(lines.length - diagMaxLines).join('\n')}\n',
      flush: true,
    );
  } catch (_) {}
}

/// السجل من الأحدث للأقدم — الشاشة بتعرضه زي ما هو.
Future<List<String>> readDiagLog() async {
  final file = await diagResolveDirectory();
  if (file == null) return const [];
  try {
    if (!file.existsSync()) return const [];
    return file.readAsLinesSync().reversed.toList();
  } catch (_) {
    return const [];
  }
}

Future<void> clearDiagLog() async {
  final file = await diagResolveDirectory();
  if (file == null) return;
  try {
    if (file.existsSync()) file.deleteSync();
  } catch (_) {}
}
