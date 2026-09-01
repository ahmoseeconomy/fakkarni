import 'package:drift/drift.dart';

// الأنواع دي مستعملة في الملف المولّد (`part`)، واللي بيشوف استيرادات
// المكتبة الأم بس — عشان كده لازم تتستورد هنا حتى لو الملف ده مش بينده عليها.
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 5;

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
                // إعادة البناء على تعريف drift الحالي — بيشيل الـDEFAULT
                // المؤقت وبيضيف UNIQUE، والفاحص بيتأكد إن الناتج نسخة ٥ حرفياً
                await m.alterTable(TableMigration(table));
              }
            }
          });
          await customStatement('PRAGMA foreign_keys = ON');
        },
        beforeOpen: (details) async {
          // من غير السطر ده SQLite بيتجاهل المفاتيح الأجنبية تماماً، ووقف
          // دوا كان هيسيب جرعاته يتيمة ورا.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
