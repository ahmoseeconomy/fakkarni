import '../escalation/escalation_ladder.dart';
import 'health_snapshot.dart';

/// **درجتين وبس.** راجل عنده ٧٢ سنة مش هيفرز تلات مستويات: يا الوعد
/// مكسور، يا ملاحظة. أي درجة تالتة بتخلّي الاتنين بلا معنى.
enum Severity { broken, note }

/// كود ثابت لكل فحص — بيتبعت للسيرفر كمان، فاسمه عقد مش تفصيلة.
enum HealthCode {
  reminderHorizon,
  remindersDropped,
  notificationPermission,
  pendingBandFull,
  timezoneChanged,
  noCaregiver,
  pushToken,
  staleSync,
  exactAlarms,
  aiKeyMissing,
  escalationRungsOff,
  noMedications,
}

/// اللي الزرار بيعمله. [none] معناها مفيش حاجة في إيد المستخدم — والجملة
/// ساعتها بتقول ده صراحة بدل ما تسيبه قدام حائط أحمر.
enum HealthFix {
  openNotificationSettings,
  openExactAlarmSettings,
  rescheduleNow,
  syncNow,
  linkCaregiver,
  none,
}

class HealthFinding {
  const HealthFinding({
    required this.code,
    required this.severity,
    required this.title,
    required this.why,
    required this.fix,
  });

  final HealthCode code;
  final Severity severity;

  /// إيه اللي حاصل — بالعامية، من غير أسماء دوال ولا أكواد.
  final String title;

  /// معناه إيه بالنسبة له هو.
  final String why;

  final HealthFix fix;

  bool get isBroken => severity == Severity.broken;
}

/// التذكير بيقف عند [brokenHorizon] → مكسور، وعند [noteHorizon] → ملاحظة.
///
/// الرقمين اختيار عرض مش طب: أربع وعشرين ساعة هي «بكرة هيسكت»، وتلات
/// أيام هي «فيه وقت تفتح التطبيق».
const Duration brokenHorizon = Duration(hours: 24);
const Duration noteHorizon = Duration(hours: 72);

/// صف متوسّخ أقدم من مهلة السيرفر = إنذار كذب على الابن.
///
/// مرآة لـ[serverGraceWindow]: الأب أكّد، الصف ما طلعش، وعند +٦٠ السيرفر
/// بيلاقي الجرعة لسه `pending` وبيصحّي الابن على حبة اتاخدت خلاص.
const Duration dirtyRowLimit = serverGraceWindow;

/// آخر رفع ناجح أقدم من كده = السحابة بقت بايتة.
///
/// نفس ٢٤ ساعة بتاعة «آخر تحديث من موبايل والدك» اللي بتولّع ذهبي عند
/// الابن — نفس الحقيقة، والاتنين لازم يقولوها في نفس الوقت.
const Duration syncSilenceLimit = Duration(hours: 24);

/// الجهاز ماسك تذكيرات لحد إمتى؟
///
/// **الرقم بييجي من `pending()` مش من الخطة.** الخطة هي اللي احنا
/// فاكرينه؛ الـpending هو اللي iOS ماسكه بجد، والفرق بينهم هو بالظبط صنف
/// العيب اللي بيسكت لحد ما مريض يفوّت جرعة (الدين ٠ج).
HealthFinding? checkReminderHorizon(HealthSnapshot s) {
  if (s.isCaregiver || s.activeDoseCount == 0) return null;
  final until = s.horizonUntil;
  if (until == null) {
    return const HealthFinding(
      code: HealthCode.reminderHorizon,
      severity: Severity.broken,
      title: 'مفيش أي تذكير متجهّز على الموبايل',
      why: 'الأدوية متسجّلة، بس الموبايل مش ماسك ولا تذكير — يعني مش هيرن.',
      fix: HealthFix.rescheduleNow,
    );
  }
  final left = until.difference(s.now);
  if (left <= brokenHorizon) {
    return HealthFinding(
      code: HealthCode.reminderHorizon,
      severity: Severity.broken,
      title: 'التذكير هيقف قريّب',
      why: left.isNegative
          ? 'آخر تذكير متجهّز عدّى معاده. من غير ما تفتح التطبيق، مش هيرن تاني.'
          : 'التذكيرات المتجهّزة بتخلص خلال أقل من يوم، وبعدها الموبايل هيسكت.',
      fix: HealthFix.rescheduleNow,
    );
  }
  if (left <= noteHorizon) {
    return const HealthFinding(
      code: HealthCode.reminderHorizon,
      severity: Severity.note,
      title: 'التذكير متجهّز لكام يوم بس',
      why: 'كل ما تفتح التطبيق أو تأكّد جرعة، المدة بتتمدّ لوحدها.',
      fix: HealthFix.rescheduleNow,
    );
  }
  return null;
}

/// اللي اتجدول ≠ اللي الجهاز ماسكه.
///
/// iOS بيمسك ٦٤ إشعار معلّق وبيرمي اللي زيادة **في صمت** — لا خطأ ولا
/// تحذير. لو الرقمين اتفرّقوا، فيه جرعات اتبنت وعمرها ما هترن.
HealthFinding? checkRemindersDropped(HealthSnapshot s) {
  if (s.isCaregiver || s.plannedDoseCount == 0) return null;
  if (s.pendingDoseCount >= s.plannedDoseCount) return null;
  return const HealthFinding(
    code: HealthCode.remindersDropped,
    severity: Severity.broken,
    title: 'فيه تذكيرات اتجهّزت والموبايل ما مسكهاش',
    why: 'الموبايل بيمسك عدد محدود من التنبيهات، واللي زيادة بيقع من غير ما '
        'يقول. يعني فيه جرعات مش هترن.',
    fix: HealthFix.rescheduleNow,
  );
}

HealthFinding? checkNotificationPermission(HealthSnapshot s) =>
    switch (s.permission) {
      NotificationPermission.denied => const HealthFinding(
          code: HealthCode.notificationPermission,
          severity: Severity.broken,
          title: 'إذن التنبيهات مقفول',
          why: 'من غير الإذن ده الموبايل مش هيعرض أي تذكير خالص.',
          fix: HealthFix.openNotificationSettings,
        ),
      NotificationPermission.provisional => const HealthFinding(
          code: HealthCode.notificationPermission,
          severity: Severity.broken,
          title: 'التنبيهات بتوصل من غير صوت',
          why: 'التذكير بينزل في مركز الإشعارات من غير ما يرن — يعني تقدر '
              'تعدّي عليه من غير ما تاخد بالك.',
          fix: HealthFix.openNotificationSettings,
        ),
      NotificationPermission.granted || NotificationPermission.unknown => null,
    };

/// السقف قرّب — التذكيرات الأخيرة في اليوم بتقع في صمت.
HealthFinding? checkPendingBandFull(HealthSnapshot s) {
  if (s.platform != HealthPlatform.ios) return null;
  if (s.pendingCount < s.pendingLimit - 2) return null;
  return const HealthFinding(
    code: HealthCode.pendingBandFull,
    severity: Severity.note,
    title: 'الموبايل قرّب على أقصى عدد تنبيهات',
    why: 'التذكيرات الأبعد ممكن ما تتجهّزش. الأقرب في مأمن.',
    fix: HealthFix.rescheduleNow,
  );
}

/// المنطقة الزمنية اتغيّرت بعد ما التذكيرات اتبنت.
HealthFinding? checkTimezoneChanged(HealthSnapshot s) {
  final built = s.scheduledTimezone;
  if (built == null || built.isEmpty || s.deviceTimezone.isEmpty) return null;
  if (built == s.deviceTimezone) return null;
  return const HealthFinding(
    code: HealthCode.timezoneChanged,
    severity: Severity.broken,
    title: 'توقيت الموبايل اتغيّر',
    why: 'التذكيرات المتجهّزة اتبنت على التوقيت القديم، فممكن ترن في '
        'معاد غلط.',
    fix: HealthFix.rescheduleNow,
  );
}

/// محدش مربوط — آخر درجة في السلّم مش بتوصل لحد.
HealthFinding? checkNoCaregiver(HealthSnapshot s) {
  if (s.isCaregiver || s.hasCaregiver) return null;
  return const HealthFinding(
    code: HealthCode.noCaregiver,
    severity: Severity.note,
    title: 'مفيش حد مربوط يتابعك',
    why: 'لو جرعة عدّت من غير تأكيد، مفيش حد هيتبلّغ. التذكير على الموبايل '
        'شغّال زي ما هو.',
    fix: HealthFix.linkCaregiver,
  );
}

/// توكن الدفع — **على موبايل الابن بس**.
///
/// على موبايل المريض التوكن مالوش علاقة بالسلّم: التنبيه بيروح لموبايل
/// الابن، فغيابه هنا مش عيب وعرضه بيبقى ضوضا.
HealthFinding? checkPushToken(HealthSnapshot s) {
  if (!s.isCaregiver || s.hasPushToken) return null;
  return const HealthFinding(
    code: HealthCode.pushToken,
    severity: Severity.broken,
    title: 'تنبيه الجرعة الفايتة مش هيوصل للموبايل ده',
    why: 'الموبايل ده لسه ما اتسجّلش عند الخدمة اللي بتبعت التنبيه. '
        'هتلاقي التنبيه جوّه التطبيق في «متابعة» لما تفتحه.',
    fix: HealthFix.none,
  );
}

/// صف قاعد على الموبايل والسيرفر مستني.
HealthFinding? checkStaleSync(HealthSnapshot s) {
  if (!s.cloudConfigured || !s.signedIn || !s.hasCaregiver) return null;

  final oldest = s.oldestDirtyAt;
  if (oldest != null && s.now.difference(oldest) > dirtyRowLimit) {
    return const HealthFinding(
      code: HealthCode.staleSync,
      severity: Severity.broken,
      title: 'فيه تأكيدات لسه ما وصلتش',
      why: 'الجرعات اللي أكّدتها لسه على الموبايل، فممكن اللي بيتابعك يتبلّغ '
          'إنك ما أخدتهاش وإنت أخدتها.',
      fix: HealthFix.syncNow,
    );
  }

  final last = s.lastSyncedAt;
  if (last != null && s.now.difference(last) > syncSilenceLimit) {
    return const HealthFinding(
      code: HealthCode.staleSync,
      severity: Severity.broken,
      title: 'الموبايل ما بعتش حاجة من أكتر من يوم',
      why: 'اللي بيتابعك بيشوف بيانات قديمة، ومش هيتبلّغ لو جرعة عدّت.',
      fix: HealthFix.syncNow,
    );
  }
  return null;
}

HealthFinding? checkExactAlarms(HealthSnapshot s) {
  if (s.platform != HealthPlatform.android || s.exactAlarmsAllowed) return null;
  return const HealthFinding(
    code: HealthCode.exactAlarms,
    severity: Severity.broken,
    title: 'الموبايل مش مسموح له ينبّه في معاد بالظبط',
    why: 'التذكير ممكن يتأخّر ساعات عن معاد الجرعة.',
    fix: HealthFix.openExactAlarmSettings,
  );
}

HealthFinding? checkAiKey(HealthSnapshot s) {
  if (s.aiKeyPresent) return null;
  return const HealthFinding(
    code: HealthCode.aiKeyMissing,
    severity: Severity.note,
    title: 'تصوير الروشتة مش شغّال في النسخة دي',
    why: 'تقدر تكتب الدوا بإيدك عادي، وكل التذكيرات شغّالة زي ما هي.',
    fix: HealthFix.none,
  );
}

/// الدرجتين مقفولين — السلّم المحلي اتشال، وفاضل السيرفر بس عند +٦٠.
HealthFinding? checkEscalationRungs(HealthSnapshot s) {
  if (s.isCaregiver || s.rungFirstOn || s.rungSecondOn) return null;
  return const HealthFinding(
    code: HealthCode.escalationRungsOff,
    severity: Severity.note,
    title: 'تنبيهات المتابعة بعد الجرعة مقفولة',
    why: 'لو نسيت جرعة، الموبايل مش هيفكّرك تاني بعدها.',
    fix: HealthFix.openNotificationSettings,
  );
}

/// **من غير الفحص ده، السطر الأخضر بيكدب.**
///
/// موبايل مفيهوش ولا دوا بيعدّي كل الفحوص — وبيقول «كله تمام» عن وعد
/// مش موجود أصلاً.
HealthFinding? checkNoMedications(HealthSnapshot s) {
  if (s.isCaregiver || s.activeDoseCount > 0) return null;
  return const HealthFinding(
    code: HealthCode.noMedications,
    severity: Severity.note,
    title: 'لسه مفيش أدوية متسجّلة',
    why: 'مفيش حاجة تترن دلوقتي. ضيف دوا من زرار «ضيف» وهنفكّرك بيه في '
        'معاده.',
    fix: HealthFix.none,
  );
}
