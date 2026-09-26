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
  batteryOptimisation,
  escalationRungsOff,
  noMedications,

  /// السيرفر رفض صف المريض (المفتاح الأجنبي أو صلاحيات الصف): الحساب اللي
  /// الموبايل ده مربوط بيه مش موجود هناك. الطابور بيقف لحد ما يربط تاني.
  accountMissing,

  /// ٠٠٢٩: صورة دوا بقالها يوم ما اترفعتش للدائرة، أو صورة من الممرض
  /// اترفضت. **للأدمن بس** — المريض ما بيشوفهاش ومفيش إشعار.
  mediaSync,

  /// مواعيد كتير (زي «كل ٤ ساعات» لكذا دوا) والتذكيرات المتجهّزة على
  /// الموبايل بتغطّي أقل من ٤٨ ساعة. **للأدمن بس** — التغطية بتتجدد لوحدها
  /// مع كل فتحة وكل تأكيد.
  lowCoverage,

  /// ٠٠٣٢ لسه ما اتشغّلتش: جدول بنمط أيام (أيام معيّنة / كل كام يوم / فترة
  /// وراحة) فاضل على الموبايل ما وصلش السحابة. التذكير شغّال عادي؛ الابن
  /// ما بيشوفش الجرعات دي. **للأدمن بس.**
  patternSync,

  /// زرار «اتكلم» أو «كلّمني» اتداس والمايك ما اشتغلش لسبب مش الإذن (المتعرّف
  /// ما اتجهّزش، اللغة، جلسة الصوت، …) في آخر ٢٤ ساعة. المريض سمع «كمّل
  /// بإيدك» مرة والزرار اختفى؛ **السبب في سجل التشخيص (`Listen:`) وللأدمن
  /// الكود ده بس.**
  listenUnavailable,
}

/// **اللي التطبيق بيصلّحه لوحده وفي صمت** — المريض عمره ما يشوف كود.
///
/// قاعدة المالك: المريض ما يشوفش مشكلة تقنية أبداً. يا التطبيق بيصلّحها
/// لوحده، يا بتتبلّغ للوحة الأدمن مع النبضة. الأكواد دي ليها إصلاح
/// آلي في `HealthAutoFix` (إعادة جدولة، تسجيل التوكن، إعادة الرفع)؛ الباقي
/// بيتسجّل وبيروح للسيرفر وبس.
const Set<HealthCode> autoFixableCodes = {
  HealthCode.reminderHorizon,
  HealthCode.remindersDropped,
  HealthCode.timezoneChanged,
  HealthCode.pushToken,
  HealthCode.staleSync,
};

/// **الاستثناء الوحيد اللي بيوصل شاشة المريض**: إذن التنبيهات مقفول.
///
/// ده مش تقني وفي إيده هو بس — سطر واحد على «يومك» بزرار بيفتح إعدادات
/// النظام، من غير كود ولا شرح. أي كود تاني يظهر للمريض هو كسر للقاعدة،
/// واختبار بيقرا الشاشات ويوقع عليه.
const Set<HealthCode> patientVisibleCodes = {HealthCode.notificationPermission};

/// اللي الزرار بيعمله. [none] معناها مفيش حاجة في إيد المستخدم — والجملة
/// ساعتها بتقول ده صراحة بدل ما تسيبه قدام حائط أحمر.
enum HealthFix {
  openNotificationSettings,
  openExactAlarmSettings,
  openBatterySettings,
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

  /// التطبيق يحاول يصلّحه لوحده؟ — كل كود ليه إصلاح آلي، مكسور أو ملاحظة:
  /// إعادة تسجيل توكن ناقص (ملاحظة لحد ما APNs تشتغل) ما بتضرش، وتأجيلها
  /// لحد ما يبقى «مكسور» معناه إن الابن يفضل من غير تنبيه يوم زيادة.
  bool get autoFixes => autoFixableCodes.contains(code);

  /// يظهر للمريض؟ — إذن التنبيهات وبس ([patientVisibleCodes]).
  bool get patientVisible => isBroken && patientVisibleCodes.contains(code);

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
    title: 'مفيش حد من عيلتك أو ممرضك مربوط',
    why: 'لو جرعة عدّت من غير تأكيد، مفيش حد هيتبلّغ. التذكير على الموبايل '
        'شغّال زي ما هو.',
    fix: HealthFix.linkCaregiver,
  );
}

/// توكن الدفع — **على موبايل الابن بس**.
///
/// على موبايل المريض التوكن مالوش علاقة بالسلّم: التنبيه بيروح لموبايل
/// الابن، فغيابه هنا مش عيب وعرضه بيبقى ضوضا.
///
/// **ملاحظة، مش مكسور — طول ما APNs لسه ما اتظبطش** (الدين ٣: محتاج
/// حساب Apple Developer مدفوع). الفرق مش تهوين: صف أحمر دايم مالوش زرار
/// بيموّت معنى الأحمر نفسه — الابن بيشوفه كل يوم، بيتعلّم يعدّي عليه،
/// وبعدين بيعدّي على واحد حقيقي. الأحمر لازم يفضل معناه «حاجة اتغيّرت
/// النهارده وتقدر تتصرف فيها».
///
/// **يرجع `broken` أول ما APNs تشتغل** — ساعتها غياب التوكن يبقى عطل
/// في جهاز بعينه، مش حالة معروفة في المنتج كله.
HealthFinding? checkPushToken(HealthSnapshot s) {
  if (!s.isCaregiver || s.hasPushToken) return null;
  return const HealthFinding(
    code: HealthCode.pushToken,
    severity: Severity.note,
    title: 'تنبيه الجرعة الفايتة لسه ما بيوصلش على الآيفون',
    why: 'النسخة دي لسه ما بتبعتش تنبيه على الآيفون. لو جرعة عدّت من غير '
        'تأكيد، هتلاقي التنبيه مستنيك جوّه التطبيق في «متابعة» — بس '
        'الموبايل مش هيرن لوحده.',
    fix: HealthFix.none,
  );
}

/// الحساب مش موجود على السيرفر — الطابور واقف لحد ما يربط تاني.
///
/// مش «مزامنة واقفة»: ده رفض من السيرفر نفسه (المفتاح الأجنبي أو صلاحيات
/// الصف)، وإعادة المحاولة للأبد كانت بتضيّع بطارية وما بتوصّل حاجة. رسالة
/// واحدة واضحة، وزرارها هو الربط.
HealthFinding? checkAccountMissing(HealthSnapshot s) {
  if (!s.syncBlockedForAccount) return null;
  return const HealthFinding(
    code: HealthCode.accountMissing,
    severity: Severity.broken,
    title: 'الحساب ده مش موجود على السيرفر — لازم تربط تاني',
    why: 'اللي أكّدته محفوظ على الموبايل، بس مش بيتبعت لحد ما تربط الموبايل '
        'تاني من «دائرة الرعاية».',
    fix: HealthFix.linkCaregiver,
  );
}

/// صف قاعد على الموبايل والسيرفر مستني.
///
/// **بالكلام العادي**: مين اللي مستني، وإن اللي أكّده هيوصل لوحده أول ما
/// النت يرجع — والزرار للمستعجل بس. لما الحساب نفسه مش موجود، الرسالة
/// دي بتسكت و[checkAccountMissing] هي اللي بتتكلم.
HealthFinding? checkStaleSync(HealthSnapshot s) {
  if (!s.cloudConfigured || !s.signedIn || !s.hasCaregiver) return null;
  if (s.syncBlockedForAccount) return null;

  final who = s.caregiverName == null ? 'للي بيتابعك' : 'لـ${s.caregiverName}';
  const why = 'أول ما النت يرجع هتتبعت لوحدها. لو مستعجل، دوس «ابعتها دلوقتي».';

  final oldest = s.oldestDirtyAt;
  if (oldest != null && s.now.difference(oldest) > dirtyRowLimit) {
    return HealthFinding(
      code: HealthCode.staleSync,
      severity: Severity.broken,
      title: 'التأكيدات لسه ما وصلتش $who',
      why: why,
      fix: HealthFix.syncNow,
    );
  }

  final last = s.lastSyncedAt;
  if (last != null && s.now.difference(last) > syncSilenceLimit) {
    return HealthFinding(
      code: HealthCode.staleSync,
      severity: Severity.broken,
      title: 'الموبايل ما بعتش حاجة $who من أكتر من يوم',
      why: why,
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

/// **أشهر سبب إن تذكير دوا ما يرنش على أندرويد.**
///
/// ملاحظة مش مكسور: التذكير بيرن فعلاً في الحالة العادية، والقيد بيضرب
/// لما الموبايل يقعد من غير استعمال — وده بالظبط حال راجل بينام.
///
/// القراية من النظام (`isIgnoringBatteryOptimizations`)، والزرار بيفتح
/// قايمة الإعدادات — **مش** الحوار المباشر، اللي بيطلب إذن مقيّد على
/// Google Play. وفيه حاجة الفحص ده ما بيشوفهاش: قوايم «التشغيل
/// التلقائي» بتاعة شاومي وأوپو وهواوي قفل تاني برّه العلم ده تماماً،
/// فجهاز ممكن يعدّي الفحص ويفضل بيتقفل.
HealthFinding? checkBatteryOptimisation(HealthSnapshot s) {
  if (s.platform != HealthPlatform.android) return null;
  // [BatteryState.unknown] بيعدّي هنا عن قصد: مش هنحط صف أحمر على شاشة
  // مريض لأن قناة ما ردّتش. الفرق بين «تمام» و«ما بصّناش» بيتسجّل في
  // النبضة، مكانه الصح.
  if (s.batteryState != BatteryState.restricted) return null;
  return const HealthFinding(
    code: HealthCode.batteryOptimisation,
    severity: Severity.note,
    title: 'توفير البطارية ماسك التطبيق',
    why: 'ممكن يأخّر التذكير أو يمنعه لما الموبايل يقعد من غير استعمال — '
        'زي وقت النوم بالظبط.',
    fix: HealthFix.openBatterySettings,
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
/// أقل تغطية مقبولة قبل ما الأدمن يتبلّغ.
const Duration lowCoverageLimit = Duration(hours: 48);

/// **الخطة اتقصّت والتغطية أقل من ٤٨ ساعة** — بتروح للأدمن مع النبضة وبس.
/// لو الخطة ما اتقصّتش (كل اللي في النافذة اتجدول) مفيش حاجة ناقصة، حتى لو
/// آخر تذكير قريب — دوا بيخلص بكرة مش «تغطية قليلة».
HealthFinding? checkLowCoverage(HealthSnapshot s) {
  if (s.isCaregiver || !s.planTruncated) return null;
  final until = s.horizonUntil;
  if (until == null || until.difference(s.now) >= lowCoverageLimit) return null;
  return const HealthFinding(
    code: HealthCode.lowCoverage,
    severity: Severity.broken,
    title: 'التذكيرات المتجهّزة بتغطّي أقل من يومين',
    why: 'مواعيد كتير في اليوم — كل فتحة أو تأكيد بيمدّها لوحدها.',
    fix: HealthFix.none,
  );
}

/// جدول بنمط أيام السحابة رفضته — بيتبلّغ للأدمن.
HealthFinding? checkPatternSync(HealthSnapshot s) {
  if (s.patternRejectedSince == null) return null;
  return const HealthFinding(
    code: HealthCode.patternSync,
    severity: Severity.broken,
    title: 'جدول بأيام معيّنة ما وصلش للدائرة',
    why: 'التذكير شغّال على الموبايل؛ الرفع بيتعاد لوحده.',
    fix: HealthFix.none,
  );
}

/// صور الأدوية واقفة (٠٠٢٩) — بتروح للوحة الأدمن مع النبضة وبس.
HealthFinding? checkMediaSync(HealthSnapshot s) {
  final stuck = s.mediaProblemSince;
  final rejected = s.mediaRejectedAt;
  final recentReject = rejected != null && s.now.difference(rejected) < const Duration(hours: 24);
  if (stuck == null && !recentReject) return null;
  return HealthFinding(
    code: HealthCode.mediaSync,
    severity: Severity.broken,
    title: stuck != null ? 'صورة دوا ما وصلتش للدائرة' : 'صورة من الدائرة ما اتقبلتش',
    why: 'الموبايل بيعيد المحاولة لوحده.',
    fix: HealthFix.none,
  );
}

/// المايك ما اشتغلش (٢٦ سبتمبر ٢٠٢٦) — للأدمن مع النبضة وبس.
HealthFinding? checkListenUnavailable(HealthSnapshot s) {
  final at = s.listenProblemSince;
  if (at == null || s.now.difference(at) >= const Duration(hours: 24)) return null;
  return const HealthFinding(
    code: HealthCode.listenUnavailable,
    severity: Severity.broken,
    title: 'المايك ما اشتغلش',
    why: 'زرار الكلام اتداس والتعرّف على الكلام ما بدأش. المريض كمّل بإيده، '
        'والسبب مكتوب في سجل التشخيص.',
    fix: HealthFix.none,
  );
}

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
