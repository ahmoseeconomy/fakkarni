import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../auth/auth_service.dart';
import '../db/app_database.dart';
import '../files/attachment_store.dart';
import '../services/reminder_sink.dart';
import '../sync/medication_change_pull.dart';

/// بعد ما السيرفر قال «اتمسح» — الموبايل ده يرجع زي ما اتنزّل.
///
/// **بتتنده بعد نجاح السيرفر وبس.** لو السيرفر ما مسحش، ولا حاجة هنا
/// بتتلمس: حساب موجود على السيرفر وموبايل فاضي هو بالظبط «نص الحساب» اللي
/// المسح ممنوع يسيبه.
///
/// الترتيب:
/// ١) كل الإشعارات المعلّقة، بالرقم — **مش `cancelAll`** (ممنوعة في المشروع):
///    بنلغي اللي `pendingIds` بيقوله واحد واحد، فمفيش نطاق حد تاني بيتلمس.
/// ٢) كل جداول القاعدة — وصف مريض فاضي بنفس الرقم، لأن [patientId] في
///    الذاكرة عند المجدول وكل شاشة. الصف ده من غير جنس ولا روتين، فالجذر
///    بيقراه «مفيش مريض» ويرجع لشاشة البداية. الـuuid جديد: المريض اللي
///    اتمسح على السيرفر ما يرجعش بنفس الهوية لو ربط تاني.
/// ٣) الصور والملفات: الورق، وصور الأدوية، والملفات اللي اتصدّرت، وكاش صور
///    الدائرة.
/// ٤) `shared_preferences` كلها، وجُمل «يومك» اللي في الذاكرة.
/// ٥) الخروج — محلي، والجلسة أصلاً بقت لمستخدم مش موجود.
///
/// كل خطوة بتبلع عطلها وبتكمّل: السيرفر خلاص مسح، والباقي تنضيف.
class LocalWipe {
  LocalWipe({
    required this.db,
    required this.patientId,
    required this.sink,
    this.auth,
    this.documentsRoot,
    this.cacheRoot,
    Future<void> Function()? clearPreferences,
  }) : _clearPreferences = clearPreferences ?? _clearAllPreferences;

  final AppDatabase db;
  final int patientId;
  final ReminderSink sink;
  final AuthService? auth;

  /// للاختبارات — الافتراضي فولدرات التطبيق الحقيقية.
  final Directory? documentsRoot;
  final Directory? cacheRoot;
  final Future<void> Function() _clearPreferences;

  /// الفولدرات جوّه المستندات اللي التطبيق بيكتب فيها — ومفيش غيرها.
  static const documentFolders = [
    DirectoryAttachmentStore.folder,
    DirectoryAttachmentStore.medPhotoFolder,
    'exports',
  ];
  static const cacheFolders = ['med-photo-cache'];

  Future<void> run() async {
    await _step('الإشعارات', _cancelNotifications);
    await _step('القاعدة', _wipeDatabase);
    await _step('الملفات', _deleteFiles);
    await _step('التفضيلات', () async {
      await _clearPreferences();
      MedicationChangePuller.notices.value = const [];
    });
    await _step('الخروج', () async => auth?.signOut());
  }

  Future<void> _step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (error) {
      diag('Account: تنضيف $name بعد المسح وقع ($error)');
    }
  }

  Future<void> _cancelNotifications() async {
    for (final id in await sink.pendingIds()) {
      await sink.cancel(id);
    }
  }

  Future<void> _wipeDatabase() async {
    // المفاتيح الأجنبية بتتقفل **برّه** المعاملة — جوّاها الـPRAGMA ما بيعملش
    // حاجة (نفس درس onUpgrade)
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction(() async {
        for (final table in db.allTables) {
          await db.customStatement('DELETE FROM "${table.actualTableName}"');
        }
        await db.into(db.patients).insert(PatientsCompanion.insert(
              id: Value(patientId),
              name: 'أنا',
              notificationSlot: const Value(0),
            ));
      });
    } finally {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> _deleteFiles() async {
    final docs = documentsRoot ?? await getApplicationDocumentsDirectory();
    for (final name in documentFolders) {
      await _deleteDir(Directory(p.join(docs.path, name)));
    }
    final cache = cacheRoot ?? await getApplicationCacheDirectory();
    for (final name in cacheFolders) {
      await _deleteDir(Directory(p.join(cache.path, name)));
    }
  }

  static Future<void> _deleteDir(Directory dir) async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<void> _clearAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
