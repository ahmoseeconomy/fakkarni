import 'package:drift/drift.dart';

// الأنواع دي مستعملة في الملف المولّد (`part`)، واللي بيشوف استيرادات
// المكتبة الأم بس — عشان كده لازم تتستورد هنا حتى لو الملف ده مش بينده عليها.
import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';
import '../dose_state.dart';
import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// قاعدة بيانات فكرني — محلية بالكامل على جهاز المريض.
///
/// مفيش سيرفر في المعادلة دي: التذكيرات بتتجدول وبتترن على الجهاز، فالتطبيق
/// شغال من غير نت وتكلفة تشغيله صفر مهما كان عدد المستخدمين.
@DriftDatabase(
  tables: [
    Patients,
    DayRoutines,
    Medications,
    DoseSchedules,
    FixedTimings,
    DoseEvents,
    RoutineBackups,
    DevicePreferences,
    EmergencyProfile,
    Records,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // قاعدة البيانات دي فيها جداول مرضى حقيقيين. الترحيل بيعدّل في
          // مكانه وعمره ما بيمسح — مفيش «امسح وابدأ من جديد» هنا ولا في أي
          // نسخة جاية.
          //
          // إعادة بناء جدول بتحتاج المفاتيح الأجنبية مقفولة، والـPRAGMA ده
          // ما بيتغيّرش جوّه معاملة — فبنقفله برّه، ونشغّل الخطوات جوّه
          // معاملة واحدة، ونرجّعه في الآخر (وbeforeOpen بيأكّد عليه).
          await customStatement('PRAGMA foreign_keys = OFF');
          await transaction(() async {
            if (from < 2) {
              // خانة الإشعارات بتاعة المريض — شوف Patients.notificationSlot.
              await m.addColumn(patients, patients.notificationSlot);
              await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS ux_patients_notification_slot '
                'ON patients (notification_slot)',
              );
            }
            if (from < 3) {
              // نوع التوقيت: كل الصفوف القديمة مراسي، بمرساتها وإزاحتها زي
              // ما هي. المرساة والإزاحة بقوا nullable — وده بيحتاج إعادة
              // بناء الجدول.
              //
              // SQL تاريخي مجمّد عن قصد، مش تعريفات drift الحالية: الخطوة
              // دي لازم تنتج **شكل نسخة ٣** بالظبط مهما كبر الكود بعدها.
              // استخدام TableMigration هنا كان بيبني شكل النهاردة (بعمود
              // uuid) جوّه خطوة قديمة — وكسر ترقية v2 أول ما v5 وصلت.
              await customStatement(
                'CREATE TABLE dose_schedules_v3 ('
                '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
                '"medication_id" INTEGER NOT NULL REFERENCES medications (id) ON DELETE CASCADE, '
                '"timing_kind" TEXT NOT NULL DEFAULT \'anchor\', '
                '"anchor" TEXT NULL, '
                '"offset_minutes" INTEGER NULL, '
                '"repeat" TEXT NOT NULL, '
                '"start_date" TEXT NOT NULL, '
                '"duration_days" INTEGER NULL)',
              );
              await customStatement(
                'INSERT INTO dose_schedules_v3 '
                '(id, medication_id, timing_kind, anchor, offset_minutes, repeat, start_date, duration_days) '
                "SELECT id, medication_id, 'anchor', anchor, offset_minutes, repeat, start_date, duration_days "
                'FROM dose_schedules',
              );
              await customStatement('DROP TABLE dose_schedules');
              await customStatement(
                'ALTER TABLE dose_schedules_v3 RENAME TO dose_schedules',
              );
              await customStatement(
                'CREATE TABLE fixed_timings ('
                '"dose_schedule_id" INTEGER NOT NULL REFERENCES dose_schedules (id) ON DELETE CASCADE, '
                '"minute_of_day" INTEGER NOT NULL, '
                'PRIMARY KEY ("dose_schedule_id"))',
              );
            }
            if (from < 4) {
              // «الجرعة مش معروفة» — الصفوف القديمة كلها false.
              await m.addColumn(medications, medications.amountUnknown);
            }
            if (from < 5) {
              // هوية المزامنة: uuid لكل صف في كل جدول هيتزامن يوم ما.
              //
              // تلات خطوات لكل جدول، والترتيب مقصود:
              // ١) نضيف العمود بـDEFAULT '' مؤقت (عمود NOT NULL على جدول
              //    فيه صفوف لازم default)؛
              // ٢) نملأه صف صف من دارت — **كل صف بـuuid مختلف**؛ توليد
              //    واحد يتحقن في SQL كان هيدي نفس القيمة للكل؛
              // ٣) نعيد بناء الجدول على تعريف drift (يشيل الـDEFAULT
              //    المؤقت ويضيف UNIQUE) — اختبار الـSchemaVerifier بيتحقق
              //    إن الناتج مطابق حرفياً لمخطط نسخة ٥.
              for (final table in <TableInfo<Table, dynamic>>[
                patients,
                dayRoutines,
                medications,
                doseSchedules,
                fixedTimings,
                doseEvents,
              ]) {
                final name = table.actualTableName;
                // حماية لمسار قديم عدّى على خطوة أنشأت الجدول بشكله الحالي
                final existing = await customSelect(
                  "SELECT 1 FROM pragma_table_info('$name') WHERE name = 'uuid'",
                ).get();
                if (existing.isEmpty) {
                  await customStatement(
                    "ALTER TABLE $name ADD COLUMN uuid TEXT NOT NULL DEFAULT ''",
                  );
                }
                final rows = await customSelect(
                  "SELECT rowid AS r FROM $name WHERE uuid = ''",
                ).get();
                for (final row in rows) {
                  await customStatement(
                    'UPDATE $name SET uuid = ? WHERE rowid = ?',
                    [newSyncUuid(), row.read<int>('r')],
                  );
                }
                // مفيش alterTable هنا: إعادة البناء على تعريف النهاردة كانت
                // بتطلب أعمدة النسخ الجاية من جدول لسه ماوصلهاش. التطبيع
                // الوحيد بيحصل مرة واحدة في **آخر** خطوة في السلسلة.
              }
            }
          });
            if (from < 6) {
              // ساعة المزامنة: updated_at_ms مبدئياً «دلوقتي» — والصفوف كلها
              // متوسّخة (synced_at_ms فاضية) عشان أول دفعة ترفع التاريخ كله.
              final backfill = DateTime.now().millisecondsSinceEpoch;
              for (final table in <TableInfo<Table, dynamic>>[
                patients,
                dayRoutines,
                medications,
                doseSchedules,
                fixedTimings,
                doseEvents,
              ]) {
                final name = table.actualTableName;
                // خطوة v5 بتعيد بناء الجداول على تعريف النهاردة، فالأعمدة
                // ممكن تكون وصلت خلاص — نفس درس «الخطوات المجمّدة»
                final existing = await customSelect(
                  "SELECT 1 FROM pragma_table_info('$name') WHERE name = 'updated_at_ms'",
                ).get();
                if (existing.isEmpty) {
                  await customStatement(
                    'ALTER TABLE $name ADD COLUMN updated_at_ms INTEGER NOT NULL DEFAULT $backfill',
                  );
                  await customStatement(
                    'ALTER TABLE $name ADD COLUMN synced_at_ms INTEGER NULL',
                  );
                }
                // التطبيع اتنقل لآخر السلسلة (تحت) — هنا كان بيبني جدول
                // patients على تعريف النهاردة قبل ما أعمدة نسخة ٨ توصل،
                // وده كسر كل ترقية من ٥ أو أقدم أول ما v8 اتضافت.
              }
            }
            if (from < 7) {
              // وضع رمضان: النسخة الاحتياطية للروتين. SQL مجمّد بالحرف —
              // مش m.createTable — عشان الخطوة تفضل تطلّع شكل نسخة ٧
              // مهما كبر الجدول بعدين (درس خطوة v2→v3).
              await customStatement(
                'CREATE TABLE IF NOT EXISTS "routine_backups" ('
                '"patient_id" INTEGER NOT NULL REFERENCES patients (id) ON DELETE CASCADE, '
                '"wake_minutes" INTEGER NOT NULL, '
                '"breakfast_minutes" INTEGER NOT NULL, '
                '"lunch_minutes" INTEGER NOT NULL, '
                '"dinner_minutes" INTEGER NOT NULL, '
                '"sleep_minutes" INTEGER NOT NULL, '
                '"iftar_minutes" INTEGER NOT NULL, '
                '"suhoor_minutes" INTEGER NOT NULL, '
                'PRIMARY KEY ("patient_id"))',
              );
            }
            if (from < 8) {
              // الجنس والسن — محليين، nullable، والصفوف القديمة ما اتسألتش.
              // ADD COLUMN بحماية وجود: مسار قديم ممكن يكون عدّى على خطوة
              // بنت الجدول بشكل أحدث (نفس درس «الخطوات المجمّدة»).
              for (final (column, type) in [('sex', 'TEXT'), ('age', 'INTEGER')]) {
                final existing = await customSelect(
                  "SELECT 1 FROM pragma_table_info('patients') WHERE name = '$column'",
                ).get();
                if (existing.isEmpty) {
                  await customStatement('ALTER TABLE patients ADD COLUMN $column $type NULL');
                }
              }
            }
            if (from < 9) {
              // تفضيلات الجهاز (نمط كبار السن + درجتين السلّم). SQL مجمّد
              // بالحرف زي خطوة v7. من غير صف = الافتراضي، فمفيش حاجة تتملي.
              await customStatement(
                'CREATE TABLE IF NOT EXISTS "device_preferences" ('
                '"id" INTEGER NOT NULL, '
                '"elder_mode" INTEGER NOT NULL DEFAULT 0 CHECK ("elder_mode" IN (0, 1)), '
                '"rung_first_on" INTEGER NOT NULL DEFAULT 1 CHECK ("rung_first_on" IN (0, 1)), '
                '"rung_second_on" INTEGER NOT NULL DEFAULT 1 CHECK ("rung_second_on" IN (0, 1)), '
                'PRIMARY KEY ("id"))',
              );
            }
            if (from < 10) {
              // بيانات الطوارئ — SQL مجمّد بالحرف. فاضي: ولا حقل بيتملا
              // لوحده. التريجر بتاعه بيتعمل في beforeOpen زي باقي الجداول.
              await customStatement(
                'CREATE TABLE IF NOT EXISTS "emergency_profile" ('
                '"uuid" TEXT NOT NULL UNIQUE, '
                '"updated_at_ms" INTEGER NOT NULL, '
                '"synced_at_ms" INTEGER NULL, '
                '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
                '"patient_id" INTEGER NOT NULL UNIQUE REFERENCES patients (id) ON DELETE CASCADE, '
                '"blood_type" TEXT NULL, '
                '"allergies" TEXT NULL, '
                '"chronic_conditions" TEXT NULL, '
                '"contacts_json" TEXT NOT NULL DEFAULT \'[]\')',
              );
            }
            if (from < 11) {
              // الملف الصحي — SQL مجمّد بالحرف.
              await customStatement(
                'CREATE TABLE IF NOT EXISTS "records" ('
                '"uuid" TEXT NOT NULL UNIQUE, '
                '"updated_at_ms" INTEGER NOT NULL, '
                '"synced_at_ms" INTEGER NULL, '
                '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
                '"patient_id" INTEGER NOT NULL REFERENCES patients (id) ON DELETE CASCADE, '
                '"kind" TEXT NOT NULL, '
                '"title" TEXT NOT NULL, '
                '"happened_at" INTEGER NOT NULL, '
                '"doctor" TEXT NULL, '
                '"place" TEXT NULL, '
                '"notes" TEXT NULL, '
                '"attachment_path" TEXT NULL, '
                '"deleted_at" INTEGER NULL)',
              );
            }
            if (from < 6) {
              // التطبيع الوحيد في السلسلة كلها — **آخر حاجة**، بعد ما كل
              // أعمدة كل النسخ بقت موجودة فعلاً (لحد نسخة ٨). بيشيل الـDEFAULTs
              // المؤقتة بتاعة ٥ و٦ وبيضيف UNIQUE، والفاحص بيقارن الناتج بآخر
              // نسخة حرفياً. أي عمود جديد في نسخة جاية لازم يتضاف **قبل** البلوك ده.
              for (final table in <TableInfo<Table, dynamic>>[
                patients,
                dayRoutines,
                medications,
                doseSchedules,
                fixedTimings,
                doseEvents,
              ]) {
                await m.alterTable(TableMigration(table));
              }
            }
          await customStatement('PRAGMA foreign_keys = ON');
        },
        beforeOpen: (details) async {
          // من غير السطر ده SQLite بيتجاهل المفاتيح الأجنبية تماماً، ووقف
          // دوا كان هيسيب جرعاته يتيمة ورا.
          await customStatement('PRAGMA foreign_keys = ON');

          // تريجرات ساعة المزامنة — هنا مش في الترحيل عن قصد: IF NOT EXISTS
          // بيخلّيها ذاتية الشفاء بعد أي إعادة بناء جدول (alterTable بيوقّع
          // التريجرات مع الجدول القديم)، وبتتعمل للتنزيلة الجديدة برضه.
          //
          // بتتخطى لما التعديل الوحيد هو تعليم المزامنة نفسه
          // (WHEN NEW.synced_at_ms IS OLD.synced_at_ms) — من غيرها كل دفعة
          // كانت هتوسّخ اللي لسه منضّفاه، للأبد.
          for (final table in [
            'patients',
            'day_routines',
            'medications',
            'dose_schedules',
            'fixed_timings',
            'dose_events',
            'emergency_profile',
            'records',
          ]) {
            await customStatement('''
CREATE TRIGGER IF NOT EXISTS ${table}_touch_updated_at
AFTER UPDATE ON $table
WHEN NEW.synced_at_ms IS OLD.synced_at_ms
BEGIN
  UPDATE $table
     SET updated_at_ms = CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
   WHERE rowid = NEW.rowid;
END''');
          }
        },
      );
}
