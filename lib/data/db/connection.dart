import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

/// **الملف ده بيتفتح من أكتر من isolate في نفس اللحظة.**
///
/// التطبيق بيفتحه في `main` وبيشغّل `rescheduleAll` وهو بيقوم؛ وضغطة
/// «أخدته» على شاشة القفل بتصحّى isolate تاني خالص بيفتح **نفس الملف**
/// وبيكتب فيه. الاتنين ممكن يبقوا شغالين في نفس الثانية بالظبط — ودي
/// مش حالة نادرة، دي الحالة العادية: الضغطة على الإشعار هي نفسها اللي
/// بتفتح التطبيق.
///
/// من غير البراغماتين اللي تحت، اللي بيخسر السباق بيقع في اللحظة:
///
///   SqliteException(5): database is locked, causing statement: BEGIN IMMEDIATE
///
/// وفي الـisolate ده كان بيضيع في صمت — المريض بيشوف الإشعار بيختفي
/// وبيفتكر إنه أكّد، والجرعة ما اتسجلتش.
void prepareDatabase(Database database) {
  // WAL: القارئ ما بيقفلش على الكاتب. التطبيق بيقرا «يومك» في نفس اللحظة
  // اللي الـisolate بيسجّل فيها الجرعة، وفي الوضع الافتراضي (DELETE) ده
  // تعارض. مود الـjournal بيتكتب في هيدر الملف نفسه فبيفضل ثابت، لكن
  // بنطلبه هنا برضه عشان أول فتحة بعد تنزيل جديد تبقى صح.
  database.execute('pragma journal_mode = WAL;');

  // **ده السطر اللي بيصلّح الباج فعلاً.**
  //
  // WAL بيحل تعارض القراءة والكتابة، مش تعارض **كاتبين**. كاتب واحد بس
  // في المرة، والتاني لازم يستنى — والافتراضي في SQLite إنه ما يستناش
  // خالص: بيرمي `database is locked` على طول. الرقم ده بيقول له
  // «استنى لحد ٥ ثواني قبل ما تيأس»، وكتاباتنا ميلي ثانية مش أكتر.
  //
  // البراغما دي **لكل اتصال**، مش محفوظة في الملف — فلازم تتطبّق في كل
  // isolate بيفتح القاعدة. عشان كده هي هنا، في المكان اللي كله بيعدّي
  // منه، مش في `main` ولا في المعالج.
  database.execute('pragma busy_timeout = 5000;');
}

/// بيفتح ملف قاعدة بيانات بنفس الإعداد بتاع التطبيق بالظبط.
///
/// مكشوفة عشان الاختبارات تفتح **بنفس الشكل** اللي الجهاز بيفتح بيه —
/// اختبار بيفتح بطريقة أسهل بيثبت حاجة تانية غير اللي بتحصل فعلاً.
QueryExecutor openDatabaseFile(File file) =>
    // `setup` بتتبعت لـisolate تاني، فلازم تفضل **دالة عليا** ما بتشيلش
    // معاها أي حالة (موثّق في drift/native.dart).
    NativeDatabase.createInBackground(file, setup: prepareDatabase);

/// ملف قاعدة البيانات جوه مساحة التطبيق الخاصة.
QueryExecutor openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return openDatabaseFile(File(p.join(dir.path, 'fakkarni.sqlite')));
    });
