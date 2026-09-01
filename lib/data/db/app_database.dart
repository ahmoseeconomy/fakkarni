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
  int get schemaVersion => 4;

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
              // ما هي. المرساة والإزاحة بقوا nullable عشان الساعة الثابتة،
              // وده بيحتاج إعادة بناء الجدول — drift بينقل الصفوف بنفسه.
              await m.addColumn(doseSchedules, doseSchedules.timingKind);
              await m.alterTable(TableMigration(doseSchedules));
              await m.createTable(fixedTimings);
            }
            if (from < 4) {
              // «الجرعة مش معروفة» — الصفوف القديمة كلها false.
              await m.addColumn(medications, medications.amountUnknown);
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
