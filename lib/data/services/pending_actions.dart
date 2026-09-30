import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/diagnostics.dart';
import '../../domain/escalation/escalation_ladder.dart' show graceWindow;
import '../../core/notifications/notification_service.dart' show NotificationActions;

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
  static ({PendingAction? action, String? reason}) parseWithReason(File file) {
    final String text;
    try {
      text = file.readAsStringSync();
    } catch (e) {
      return (action: null, reason: 'القراية وقعت (${e.runtimeType})');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return (action: null, reason: 'مش JSON object (${text.length} بايت)');
      final action = decoded['action'];
      final at = decoded['at'];
      if (action is! String || at is! int) {
        return (
          action: null,
          reason: 'مفاتيح ناقصة أو نوعها غلط — action=${action.runtimeType} at=${at.runtimeType}',
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
      );
    } catch (e) {
      return (action: null, reason: 'مش JSON (${e.runtimeType}، ${text.length} بايت)');
    }
  }

  /// اسم الملف بس — من غير المسار.
  String get name => file.uri.pathSegments.last;
}

const pendingActionsFolder = 'pending_actions';

/// تأجيل أقدم من مهلة الجهاز (٤٥ دقيقة) بقى بلا معنى — الدرجات اللي بعده
/// رنّت أو اتلغت خلاص.
const staleSnoozeAfter = graceWindow;

class PendingActionStore {
  PendingActionStore({this.directoryOverride});

  /// للاختبارات — الافتراضي مجلد التطبيق (تحت).
  final Directory? directoryOverride;

  /// المجلد من غير أي قناة: `FAKKARNI_DOCS` (سويفت بتحطها عند الإطلاق)،
  /// وإلا `$HOME/Documents` على iOS. null = مفيش طابور على المنصة دي.
  Directory? get directory {
    final given = directoryOverride;
    if (given != null) return given;
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
          diag('Pending: ملف اتشال (ما اتقراش) — ${f.uri.pathSegments.last} — ${parsed.reason}');
          _delete(f);
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

  /// للـisolate: دوسته هو اتعالجت خلاص — تتشال، والباقي يتطبّق. سطر واحد
  /// عند النداء عشان محوّل أندرويد يفضل رفيع (`one_door_test`).
  Future<int> drainOthers({
    required String? action,
    required String? payload,
    required Future<void> Function(String? action, String? payload) door,
  }) {
    removeMatching(action: action, payload: payload);
    return drainPendingActions(this, door);
  }

  void _delete(File f) {
    try {
      f.deleteSync();
    } catch (_) {}
  }
}

/// بيطبّق كل اللي في الطابور على [door] (نفس باب الإشعار) ويشيله.
/// بيرجّع عدد اللي اتطبّق. عطل في واحدة ما بيوقّفش الباقي، والملف بيفضل
/// للمحاولة الجاية — **التأكيد ما بيتشالش غير بعد ما يتكتب**.
Future<int> drainPendingActions(
  PendingActionStore store,
  Future<void> Function(String? action, String? payload) door, {
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
      await door(a.action, a.payload);
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
  static Future<void> Function(String? action, String? payload)? door;

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

  static Future<Object?> handle(MethodCall call) async => switch (call.method) {
        'drain' => drain(),
        _ => null,
      };

  /// بيسجّل المعالج وبيقول لسويفت «أنا جاهز» — من هنا الدوسات بتيجي هنا.
  static Future<void> listen() async {
    _channel.setMethodCallHandler(handle);
    try {
      await _channel.invokeMethod<void>('ready').timeout(const Duration(milliseconds: 500));
    } catch (e) {
      // أندرويد والاختبارات: مفيش سويفت — الصحوة هناك isolate زي ما هي
      diag('Live: مفيش قناة سويفت ($e)');
    }
  }
}
