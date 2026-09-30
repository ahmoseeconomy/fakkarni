import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/diagnostics.dart';
import '../../domain/escalation/escalation_ladder.dart' show graceWindow;
import '../../core/notifications/notification_service.dart' show NotificationActions;
import 'notification_actions.dart' show ActionOutcome;

/// الباب اللي بيطبّق دوسة — بيرجّع اللي حصل فعلاً (شوف [ActionOutcome]).
typedef TapDoor = Future<ActionOutcome> Function(String? action, String? payload);

/// **دوسة على زرار الإشعار عمرها ما تضيع.**
///
/// على iOS الإضافة بتسلّم الدوسة لمحرّك خلفي **ممكن ما يقومش** (شوف
/// `PendingActionQueue` في `AppDelegate.swift` والدليل من الجهاز هناك).
/// فسويفت بتكتب كل دوسة ملف صغير في `Documents/pending_actions/` قبل ما
/// تسلّمها للإضافة، ودارت بتقرا المجلد ده وتطبّق اللي فيه:
/// * عند الفتح (`main`، بعد تهيئة الإشعارات وقبل أي حاجة بتستنى الشبكة)،
/// * عند الرجوع للمقدمة،
/// * وفي الـisolate لو اشتغل — وبيشيل ملفه هو.
///
/// التطبيق على نفس باب `handleNotificationAction` (idempotent: تأكيد
/// مرتين = نفس الصف، والإلغاء بالرقم). **التأجيل القديم ما بيتطبّقش**:
/// «فكّرني بعدين» اتداست الصبح وبتتقرا بالليل كانت هتجدول تذكير غلط —
/// أقدم من [staleSnoozeAfter] بيتشال. التأكيد بيتطبّق مهما كان عمره:
/// هو خد الدوا فعلاً.
///
/// الأسامي (المجلد ومفاتيح الـJSON) مرآة للسويفت — `pending_actions_test`
/// بيقرا `AppDelegate.swift` ويقفل عليها.
class PendingAction {
  const PendingAction({required this.file, required this.action, required this.id, required this.at, this.payload});

  final File file;
  final String action;
  final int id;
  final DateTime at;
  final String? payload;

  static PendingAction? parse(File file) => parseWithReason(file).action;

  /// زي [parse] بالظبط — ومعاه **ليه** ما اتقراش، عشان سطر التشخيص. السبب
  /// نوع العطل والمفاتيح الناقصة بس؛ محتوى الملف عمره ما بيتكتب في السجل.
  static ({PendingAction? action, String? reason, bool readFailed}) parseWithReason(File file) {
    final String text;
    try {
      text = file.readAsStringSync();
    } catch (e) {
      return (action: null, reason: 'القراية وقعت (${e.runtimeType})', readFailed: true);
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return (action: null, reason: 'مش JSON object (${text.length} بايت)', readFailed: false);
      }
      final action = decoded['action'];
      final at = decoded['at'];
      if (action is! String || at is! int) {
        return (
          action: null,
          reason: 'مفاتيح ناقصة أو نوعها غلط — action=${action.runtimeType} at=${at.runtimeType}',
          readFailed: false,
        );
      }
      return (
        action: PendingAction(
          file: file,
          action: action,
          id: (decoded['id'] as num?)?.toInt() ?? -1,
          at: DateTime.fromMillisecondsSinceEpoch(at),
          payload: decoded['payload'] as String?,
        ),
        reason: null,
        readFailed: false,
      );
    } catch (e) {
      return (action: null, reason: 'مش JSON (${e.runtimeType}، ${text.length} بايت)', readFailed: false);
    }
  }

  /// اسم الملف بس — من غير المسار.
  String get name => file.uri.pathSegments.last;
}

const pendingActionsFolder = 'pending_actions';

/// الدوسات اللي عمرها ما هتتسجّل (زرار مش بتاعنا، payload بايظ، دوا اتوقف)
/// بتتنقل هنا بدل ما تتمسح — **ولا دوسة بتختفي من غير أثر**.
const badPendingFolder = 'bad';

/// تأجيل أقدم من مهلة الجهاز (٤٥ دقيقة) بقى بلا معنى — الدرجات اللي بعده
/// رنّت أو اتلغت خلاص.
const staleSnoozeAfter = graceWindow;

class PendingActionStore {
  PendingActionStore({this.directoryOverride});

  /// للاختبارات — الافتراضي مجلد التطبيق (تحت).
  final Directory? directoryOverride;

  /// **المجلد اللي سويفت بتكتب فيه، متأكَّد منه** — من سويفت نفسها (مع
  /// «ready» ومع كل «drain») أو من `path_provider` ([resolve]).
  ///
  /// الجهاز قال ليه ده لازم (٣٠ سبتمبر ٢٠٢٦، profile): على الإنجن الرئيسي
  /// لا `FAKKARNI_DOCS` ولا `HOME` كانوا في بيئة دارت، فالطابور كان بيرجّع
  /// «مفيش مجلد» — سويفت كتبت الدوسة ودارت طبّقت ٠ والدوسة ضاعت.
  static Directory? known;

  /// سويفت قالت المجلد — بيتحفظ لباقي العملية.
  static void adopt(String? folder) {
    if (folder == null || folder.isEmpty) return;
    if (known?.path == folder) return;
    known = Directory(folder);
    diag('Pending: المجلد من سويفت — $folder');
  }

  /// المجلد من `getApplicationDocumentsDirectory()` — نفس اللي سويفت بتكتب
  /// فيه (`FileManager.documentDirectory`). على iOS بس (الطابور سويفت)،
  /// إلا لو الاختبار ادّاله [documents]. عمره ما بيرمي.
  static Future<Directory?> resolve({Future<Directory> Function()? documents}) async {
    if (known != null) return known;
    if (documents == null && !Platform.isIOS) return null;
    try {
      final docs = await (documents ?? getApplicationDocumentsDirectory)();
      known = Directory('${docs.path}/$pendingActionsFolder');
      diag('Pending: المجلد من المستندات — ${known!.path}');
    } catch (e) {
      diag('Pending: مقدرناش نعرف مجلد المستندات (${e.runtimeType}) — هنجرّب البيئة');
    }
    return known;
  }

  /// المجلد: الاختبار، ثم [known]، ثم البيئة (`FAKKARNI_DOCS` أو `$HOME` على
  /// iOS) كآخر حل. null = مفيش طابور على المنصة دي.
  Directory? get directory {
    final given = directoryOverride;
    if (given != null) return given;
    final sure = known;
    if (sure != null) return sure;
    try {
      final docs = Platform.environment['FAKKARNI_DOCS'];
      if (docs != null && docs.isNotEmpty) return Directory('$docs/$pendingActionsFolder');
      if (!Platform.isIOS) return null;
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) return Directory('$home/Documents/$pendingActionsFolder');
    } catch (_) {}
    return null;
  }

  /// الأقدم الأول — ملف ما ينفعش يتقرا بيتشال (مش هيبقى ينفع بكرة).
  ///
  /// **كل قراية بتتسجّل** (تشخيص «أخدته» اللي بتضيع، ٣٠ سبتمبر ٢٠٢٦): أنهي
  /// مجلد، وكام ملف لقى، وكام اتقرا — وأي ملف اتشال بسببه. قبل كده القراية
  /// الفاضية والملف اللي ما اتقراش كانوا بيعدّوا من غير ولا سطر.
  List<PendingAction> list() {
    final dir = directory;
    if (dir == null) {
      diag('Pending: الطابور — مفيش مجلد (المنصة دي مالهاش طابور)');
      return const [];
    }
    try {
      if (!dir.existsSync()) {
        diag('Pending: الطابور — المجلد مش موجود: ${dir.path}');
        return const [];
      }
      final out = <PendingAction>[];
      var files = 0;
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        files++;
        final parsed = PendingAction.parseWithReason(f);
        if (parsed.action == null) {
          final name = f.uri.pathSegments.last;
          if (parsed.readFailed) {
            // القراية وقعت (ممكن تكون لحظية) — **الملف فاضل** للمرة الجاية
            diag('Pending: ملف ما اتقراش، فاضل للمحاولة الجاية — $name — ${parsed.reason}');
          } else {
            diag('Pending: ملف بايظ اتنقل لـ$badPendingFolder/ — $name — ${parsed.reason}');
            _quarantine(f);
          }
          continue;
        }
        out.add(parsed.action!);
      }
      diag('Pending: الطابور — مجلد=${dir.path} — ملفات=$files — اتقرا=${out.length}');
      return out..sort((a, b) => a.at.compareTo(b.at));
    } catch (e) {
      diag('Pending: قراية الطابور وقعت ($e)');
      return const [];
    }
  }

  /// بيشيل الدوسة اللي الـisolate عالجها بنفسه — عشان الفتحة الجاية ما
  /// تعيدهاش.
  void removeMatching({required String? action, required String? payload}) {
    for (final a in list()) {
      if (a.action == action && a.payload == payload) {
        diag('Pending: ملف اتشال (الصحوة عالجت الدوسة دي) — ${a.name}');
        _delete(a.file);
      }
    }
  }

  /// للـisolate: دوسته هو — **لو اتسجّلت** ([mine] done) — تتشال، والباقي
  /// يتطبّق. لو ما اتسجّلتش، ملفها بيفضل وبيتطبّق مع الباقي بالباب. سطر
  /// واحد عند النداء عشان محوّل أندرويد يفضل رفيع (`one_door_test`).
  Future<int> drainOthers({
    required String? action,
    required String? payload,
    required ActionOutcome mine,
    required TapDoor door,
  }) {
    if (mine.done) {
      removeMatching(action: action, payload: payload);
    } else {
      diag('Pending: دوسة الصحوة ما اتسجّلتش (${mine.name}) — ملفها فاضل في الطابور');
    }
    return drainPendingActions(this, door);
  }

  void _delete(File f) {
    try {
      f.deleteSync();
    } catch (_) {}
  }

  /// نقل لـ`bad/` — **مش مسح**. لو النقل نفسه وقع، الملف بيفضل مكانه.
  void _quarantine(File f) {
    try {
      final bad = Directory('${f.parent.path}/$badPendingFolder')..createSync(recursive: true);
      f.renameSync('${bad.path}/${f.uri.pathSegments.last}');
    } catch (e) {
      diag('Pending: نقل الملف لـ$badPendingFolder/ وقع (${e.runtimeType}) — فاضل مكانه');
    }
  }
}

/// بيطبّق كل اللي في الطابور على [door] (نفس باب الإشعار) ويشيله.
/// بيرجّع عدد اللي اتطبّق. عطل في واحدة ما بيوقّفش الباقي، والملف بيفضل
/// للمحاولة الجاية — **التأكيد ما بيتشالش غير بعد ما يتكتب**.
///
/// **الملف ما بيتشالش غير لما الجرعة تتسجّل فعلاً** (قرار المالك، ٣٠ سبتمبر
/// ٢٠٢٦): [ActionOutcome.done] = يتشال؛ خروج هادي = يتنقل لـ`bad/` بسطر؛
/// رمية = يفضل للمرة الجاية.
Future<int> drainPendingActions(
  PendingActionStore store,
  TapDoor door, {
  DateTime? now,
}) async {
  final clock = now ?? DateTime.now();
  var applied = 0;
  for (final a in store.list()) {
    if (a.action == NotificationActions.snooze && clock.difference(a.at) > staleSnoozeAfter) {
      diag('Pending: تأجيل قديم (${a.at}) اتشال من غير تطبيق');
      store._delete(a.file);
      continue;
    }
    try {
      final outcome = await door(a.action, a.payload);
      if (!outcome.done) {
        diag('Pending: الدوسة ما اتسجّلتش (${outcome.name}) — ${a.name} اتنقل لـ$badPendingFolder/');
        store._quarantine(a.file);
        continue;
      }
      store._delete(a.file);
      applied++;
      diag('Pending: اتطبّق ${a.action} (اتداس ${a.at}) — ${a.name} اتشال');
    } catch (e, stack) {
      diag('Pending: تطبيق ${a.action} وقع — هيتعاد الفتحة الجاية: $e\n$stack');
    }
  }
  return applied;
}

/// **«أخدته» والتطبيق عايش (في الخلفية أو قدّامه)** — سويفت بتسلّم الدوسة
/// للإنجن الرئيسي على طول، من غير الإضافة.
///
/// الإضافة (`flutter_local_notifications` 22.3.0،
/// `FlutterLocalNotificationsPlugin.m`) بتبعت أي زرار مش `foreground` لإنجن
/// فلاتر **تاني** بتقوّمه ساعتها (`startEngineIfNeeded`)، وبترجّع
/// `completionHandler()` على طول — حتى والتطبيق عايش. فالتطبيق اللي شغّال
/// ما بيعرفش، والكتابة والإلغاء معلّقين على إنجن جديد يقوم في ثواني الخلفية.
/// على الآيفون (٢٦ سبتمبر ٢٠٢٦، release): أول «أخدته» ما اتسجّلتش، إعادة
/// الـ+٥ رنّت، و«يومك» قالت «نسيتها؟».
///
/// فسويفت (`LiveActionChannel` في `AppDelegate.swift`) بتكتب الدوسة في
/// الطابور زي ما هي، ولو دارت قالت [ready] بتنده `drain` هنا **بدل** الإضافة:
/// نفس الطابور، نفس الباب، على نفس قاعدة البيانات اللي «يومك» بتسمعها.
abstract final class LiveActions {
  static const channelName = 'fakkarni/actions';
  static const MethodChannel _channel = MethodChannel(channelName);

  /// الباب الحالي — `main` بيبدّله لما الخدمات الكاملة تتبني.
  static TapDoor? door;

  /// للاختبارات.
  static PendingActionStore store = PendingActionStore();

  /// سويفت بتنده ده — بيطبّق الطابور ويرجّع عدد اللي اتطبّق.
  static Future<int> drain() async {
    final d = door;
    if (d == null) {
      diag('Live: drain — الباب لسه مش جاهز، مفيش حاجة اتطبّقت (الملف فاضل في الطابور)');
      return 0;
    }
    final n = await drainPendingActions(store, d);
    diag('Live: الإنجن الرئيسي طبّق $n من الطابور');
    return n;
  }

  /// سويفت بتبعت المجلد مع «drain» — بيتحفظ قبل ما الطابور يتقرا.
  static Future<Object?> handle(MethodCall call) async {
    if (call.method != 'drain') return null;
    final args = call.arguments;
    if (args is Map) PendingActionStore.adopt(args['folder'] as String?);
    return drain();
  }

  /// بيسجّل المعالج وبيقول لسويفت «أنا جاهز» — من هنا الدوسات بتيجي هنا.
  static Future<void> listen() async {
    _channel.setMethodCallHandler(handle);
    try {
      // سويفت بترد بالمجلد اللي بتكتب فيه
      final folder = await _channel.invokeMethod<String>('ready').timeout(const Duration(milliseconds: 500));
      PendingActionStore.adopt(folder);
    } catch (e) {
      // أندرويد والاختبارات: مفيش سويفت — الصحوة هناك isolate زي ما هي
      diag('Live: مفيش قناة سويفت ($e)');
    }
  }
}
