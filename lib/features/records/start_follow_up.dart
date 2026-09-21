import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/scheduling/day_routine.dart';
import '../health/scan_lab_screen.dart';
import '../scan/scan_prescription_screen.dart';

/// **تلات طرق تبدأ بيها متابعة، بالترتيب ده — واللي في الملف الأول.**
///
/// الورقة اللي اتصوّرت خلاص بياناتها معانا (الاسم والدكتور والتاريخ)، فأول
/// اختيار هو اللي بيوفّر على الراجل إعادة كتابة حاجة إحنا عارفينها. تصوير
/// جديد بعده، والكتابة بالإيد آخر حاجة — مش لأنها أقل، لأنها أتعب.
///
/// ولا واحدة فيهم بتبدأ متابعة من غير دوسة إنسان (القاعدة ٤).
enum StartFollowUpWay { fromFile, fromPhoto, byHand }

/// السجلات اللي ينفع تبدأ منها متابعة من النوع ده.
///
/// تحليل → تقارير التحاليل؛ زيارة → الروشتات (الورقة اللي فيها الدكتور
/// والعيادة وتاريخها). السجل اللي هو **نفسه** متابعة مش مصدر.
RecordKind sourceKindFor(FollowKind kind) =>
    kind == FollowKind.lab ? RecordKind.lab : RecordKind.prescription;

/// عنوان المتابعة الجديدة من سجل مصدر.
///
/// التحليل بياخد اسم التقرير زي ما هو. الزيارة بتاخد **اسم الدكتور** —
/// «متابعة زيارة د. حسام» هي الجملة اللي الراجل بيقراها بعدين، وعنوان
/// زي «روشتة — ٣ أدوية» كان هيخلّيها بلا معنى. ومن غير اسم على الورقة
/// بنقول كده بالحرف بدل ما نخترع اسم.
/// اسم المتابعة **باللي بنتابعه، مش بالورقة**.
///
/// كان بياخد عنوان الورقة بالحرف، فمتابعة كانت بتتسمّى «تقرير تحليل —
/// ٦ نتايج» — وده وصف ورقة قديمة مش وصف حاجة لسه بتحصل.
/// [followDisplayTitle] بتعمل نفس التحويل **وقت العرض** كمان، فالصفوف
/// اللي اتكتبت قبل كده بتتعرض صح من غير ما نلمسها.
String followTitleFrom(FollowKind kind, RecordRow source) => followDisplayTitle(
      kind,
      switch (kind) {
        FollowKind.lab => source.title,
        FollowKind.visit => source.doctor?.trim() ?? '',
      },
    );

/// بيسأل: تبدأ منين؟ وبيرجّع الاختيار، أو null لو قفلها.
Future<StartFollowUpWay?> askStartWay(BuildContext context, FollowKind kind) => FSheet.show<StartFollowUpWay>(
      context,
      title: kind.startLabel,
      children: [
        FPrimaryButton(
          key: const ValueKey('follow-from-file'),
          label: kind == FollowKind.lab ? 'من تقرير في الملف' : 'من روشتة في الملف',
          onPressed: () => Navigator.of(context).pop(StartFollowUpWay.fromFile),
        ),
        FSecondaryButton(
          key: const ValueKey('follow-from-photo'),
          label: kind == FollowKind.lab ? 'صوّر تقرير جديد' : 'صوّر روشتة جديدة',
          onPressed: () => Navigator.of(context).pop(StartFollowUpWay.fromPhoto),
        ),
        FSecondaryButton(
          key: const ValueKey('follow-by-hand'),
          label: 'اكتبه بإيدي',
          onPressed: () => Navigator.of(context).pop(StartFollowUpWay.byHand),
        ),
      ],
    );

/// نتيجة اختيار سجل من الملف: يا إما نبدأ منه، يا إما نفتح متابعته القايمة.
typedef PickedSource = ({int recordId, bool alreadyFollowed});

/// قايمة السجلات اللي ينفع تبدأ منها.
///
/// اللي ليه متابعة شغّالة بيبان **متابَع خلاص**، والدوسة عليه بتفتحها بدل
/// ما تبدأ تانية: ورقة واحدة بمتابعتين معناها الاتنين ناقصين، وحد يقرا
/// واحدة منهم ويفتكر إنها الصورة كاملة.
Future<PickedSource?> pickSource(BuildContext context, FollowKind kind, {DateTime? today}) async {
  final services = AppScope.of(context);
  final db = services.db;
  final sourceKind = sourceKindFor(kind);
  final rows = await (db.select(db.records)
        ..where((t) =>
            t.patientId.equals(services.patientId) &
            t.kind.equalsValue(sourceKind) &
            t.deletedAt.isNull() &
            t.checkupStage.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.happenedAt)]))
      .get();
  final followed = await services.checkups.followedSourceIds(services.patientId);
  if (!context.mounted) return null;

  return FSheet.show<PickedSource>(
    context,
    title: kind == FollowKind.lab ? 'اختار تقرير' : 'اختار روشتة',
    children: [
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: F.s8),
          child: Text(
            kind == FollowKind.lab
                ? 'لسه مفيش تقارير تحاليل في الملف. صوّر واحد، أو اكتبه بإيدك.'
                : 'لسه مفيش روشتات في الملف. صوّر واحدة، أو اكتبها بإيدك.',
            style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5),
          ),
        ),
      for (final r in rows)
        _SourceRow(record: r, alreadyFollowed: followed.contains(r.id)),
    ],
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.record, required this.alreadyFollowed});

  final RecordRow record;
  final bool alreadyFollowed;

  @override
  Widget build(BuildContext context) {
    final meta = [?record.doctor, ?record.place, arabicDate(record.happenedAt)].join(' — ');
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s8),
      child: InkWell(
        key: ValueKey('follow-source-${record.id}'),
        borderRadius: BorderRadius.circular(F.radiusCard),
        onTap: () => Navigator.of(context)
            .pop((recordId: record.id, alreadyFollowed: alreadyFollowed)),
        child: Container(
          constraints: const BoxConstraints(minHeight: F.minTapTarget),
          padding: const EdgeInsets.all(F.s12),
          decoration: BoxDecoration(
            color: F.railGround,
            borderRadius: BorderRadius.circular(F.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.title,
                textDirection: nameDirection(record.title),
                style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
              ),
              if (meta.isNotEmpty)
                Text(meta, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
              if (alreadyFollowed)
                Text(
                  'متابَع خلاص — افتح المتابعة',
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    fontWeight: FontWeight.w700,
                    color: F.greenDeep,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شاشة التصوير المناسبة للنوع، وبترجّع id السجل اللي اتأكد (أو null).
Future<int?> scanForFollowUp(BuildContext context, FollowKind kind, {DateTime? today}) async {
  final services = AppScope.of(context);
  int? saved;
  void onSaved(int id) => saved = id;
  final routine = await services.routines.getRoutine(services.patientId);
  if (!context.mounted) return null;
  await Navigator.of(context).push<void>(MaterialPageRoute<void>(
    builder: (_) => kind == FollowKind.lab
        ? ScanLabScreen(reader: services.labReader, today: today, onSaved: onSaved)
        : ScanPrescriptionScreen(
            routine: routine ?? DayRoutine.fallback,
            reader: services.prescriptionReader,
            today: today,
            onSaved: onSaved,
          ),
  ));
  return saved;
}
