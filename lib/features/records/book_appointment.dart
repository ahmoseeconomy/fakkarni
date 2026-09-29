import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/widgets/f_sheet.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/places/specialty.dart';
import '../../domain/scheduling/minute_of_day.dart';
import 'health_file_screen.dart' show NewAppointmentBody, NewAppointmentResult;

/// ورقة «ميعاد جديد» **متعبّية** — والحفظ من زرارها، بنفس الدالة اللي زرار
/// «السجل» بيعدّي منها (`bookAppointment`): الميعاد في الملف وإشعار امبارحه
/// وإشعار يومه. **ده كل اللي «الحجز» بيعمله**: مفيش أي حاجة بتتبعت للعيادة.
///
/// [doctor] دكتور **حقيقي** — من دكاترة المريض أو من «القريب مني». بيتسجّل
/// على الميعاد لو الاسم فضل زي ما هو؛ لو اتغيّر في الورقة، الاسم الجديد بتاع
/// المريض والدكتور ما بيتكتبش جنبه.
Future<bool> openBookAppointment(
  BuildContext context, {
  required DateTime today,
  FollowKind kind = FollowKind.visit,
  String? name,
  DateTime? day,
  MinuteOfDay? time,
  String? doctor,
  Specialty? specialty,
}) async {
  final services = AppScope.maybeOf(context);
  if (services == null) return false;
  final result = await FSheet.show<NewAppointmentResult>(
    context,
    title: 'ميعاد جديد',
    children: [
      NewAppointmentBody(
        today: DateTime(today.year, today.month, today.day),
        allowFromPaper: false,
        initialKind: kind,
        initialName: name,
        initialDay: day,
        initialTime: time,
        initialSpecialty: specialty,
      ),
    ],
  );
  if (result == null) return false;
  await services.checkups.bookAppointment(
    patientId: services.patientId,
    kind: result.kind,
    title: result.title,
    day: result.day,
    today: today,
    time: result.time,
    // الدكتور بيتسجّل لو الاسم فضل زي ما هو — التخصص جنبه ما بيغيّرش ده
    doctor: doctor != null && (result.name ?? '') == (name ?? '').trim() ? doctor : null,
  );
  await services.refreshAppointments(now: today);
  return true;
}
