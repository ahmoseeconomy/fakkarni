// المتابعات (جولة ٢٤) — دارت نقية.
//
// نوعين: **متابعة تحليل** (اللي كانت موجودة من D3.7) و**متابعة زيارة**.
// الاتنين بيمشوا بنفس الطريقة — مراحل الإنسان بيقدّمها بإيده، ومرحلة
// بتسأل عن ميعادها بتجدول تذكير واحد — بس مراحلهم مختلفة، لأن الزيارة
// مش تحليل.
//
// **ومفيش «دورة» في ولا كلمة للمستخدم** (القاعدة المكتوبة في CLAUDE.md،
// واختبار بيقراها): الاسم «متابعة».

import 'checkup.dart';

/// مرحلة في متابعة — تحليل كانت أو زيارة.
///
/// الواجهة دي هي اللي بتخلّي الخدمة والشاشة يشتغلوا على النوعين من غير
/// `switch` في كل سطر. [CheckupStage] و[VisitStage] بينفّذوها.
abstract interface class FollowStage {
  String get label;

  /// المرحلة دي بتسأل عن تاريخ؟ والسؤال نفسه — null = مالهاش ميعاد.
  ///
  /// **وبرضه ما بنفترضش المرحلة بتاخد قد إيه** (القاعدة ٦): الإنسان بيقول،
  /// وساعتها بس بيبقى فيه تذكير.
  String? get dateQuestion;

  /// رقم المرحلة زي ما بيتخزّن في `records.checkup_stage` (بيبدأ من ١).
  int get number;

  bool get asksForDate;
}

/// مراحل متابعة الزيارة — **وبس**.
///
/// تلاتة، لأن دي اللي الزيارة بتعيشها فعلاً: اتحجزت، تمت، وبعدها متابعة.
/// ما اخترعناش تحضير ولا انتظار ولا مراجعة — الزيارة مش تحليل، ونسخ
/// مراحل التحليل هنا كان هيخترع إجراء الراجل مش بيعيشه.
enum VisitStage implements FollowStage {
  booked('الزيارة اتحجزت', dateQuestion: 'الزيارة إمتى؟'),
  done('الزيارة تمت'),
  followUp('المتابعة');

  const VisitStage(this.label, {this.dateQuestion});

  @override
  final String label;

  @override
  final String? dateQuestion;

  @override
  bool get asksForDate => dateQuestion != null;

  @override
  int get number => index + 1;

  static VisitStage? fromNumber(int? n) =>
      n == null || n < 1 || n > values.length ? null : values[n - 1];

  VisitStage? get next => index + 1 < values.length ? values[index + 1] : null;
  VisitStage? get previous => index > 0 ? values[index - 1] : null;

  static List<VisitStage> get dated => [for (final s in values) if (s.asksForDate) s];
}

/// نوع المتابعة — بيتخزّن في `records.follow_kind`.
enum FollowKind {
  /// متابعة تحليل (D3.7). **الصفوف القديمة كلها دي**: قبل الجولة دي مكانش
  /// فيه نوع تاني أصلاً، فـnull في العمود معناها `lab` — مش تخمين، دي
  /// الحقيقة الوحيدة اللي كانت موجودة.
  lab('تحليل', 'متابعة التحليل', 'تابع تحليل'),

  visit('زيارة', 'متابعة الزيارة', 'تابع زيارة');

  const FollowKind(this.word, this.screenTitle, this.startLabel);

  /// الكلمة اللي بتتحط في السطور: «متابعة **زيارة** د. حسام واقفة».
  final String word;

  final String screenTitle;
  final String startLabel;

  /// الاسم اللي بيتخزّن في العمود. null في القاعدة = [FollowKind.lab].
  static FollowKind fromStored(String? stored) =>
      values.asNameMap()[stored] ?? FollowKind.lab;

  List<FollowStage> get stages => switch (this) {
        FollowKind.lab => CheckupStage.values,
        FollowKind.visit => VisitStage.values,
      };

  List<FollowStage> get datedStages => [for (final s in stages) if (s.asksForDate) s];

  FollowStage? stageFromNumber(int? n) =>
      n == null || n < 1 || n > stages.length ? null : stages[n - 1];

  FollowStage? nextAfter(FollowStage s) =>
      s.number < stages.length ? stages[s.number] : null;

  FollowStage? beforeStage(FollowStage s) => s.number > 1 ? stages[s.number - 2] : null;

  /// خانة المرحلة في نطاق الإشعارات — ترتيبها بين اللي بتسأل عن تاريخ.
  ///
  /// الصف الواحد نوع واحد بس، فخانة ٠ بتاعة «حجز المعمل» في متابعة تحليل
  /// وبتاعة «الزيارة اتحجزت» في متابعة زيارة — ومستحيل يتلاقوا على نفس
  /// الصف. الرقم النهائي مشتق من (الصف، الخانة) زي ما هو.
  int slotOf(FollowStage stage) {
    final slot = datedStages.indexOf(stage);
    if (slot < 0) throw ArgumentError.value(stage, 'stage', 'المرحلة دي ما بتسألش عن تاريخ');
    return slot;
  }
}

/// تذكير مرحلة [owner] لسه له لازمة والمتابعة واقفة عند [current]؟
///
/// التحليل قواعده في [stageReminderStillUseful]. الزيارة أبسط: ميعاد
/// الزيارة بيموت أول ما الزيارة تتم — بعدها هو زنّ على حاجة حصلت.
bool followReminderStillUseful(FollowKind kind, FollowStage owner, FollowStage current) =>
    switch (kind) {
      FollowKind.lab => stageReminderStillUseful(owner as CheckupStage, current as CheckupStage),
      FollowKind.visit => current.number <= owner.number,
    };

/// المتابعة واقفة عند مرحلة بتسأل عن ميعاد ومفيش ميعاد، وعدّى
/// [checkupStalledAfter]. نفس الحساب للنوعين — هي واقعة عن الشاشة، مش
/// عن الجسم ولا عن العيادة.
bool followIsStalled({
  required FollowStage stage,
  required DateTime? stageSince,
  required DateTime? stageDate,
  required DateTime now,
}) {
  if (!stage.asksForDate || stageDate != null || stageSince == null) return false;
  return !now.isBefore(stageSince.add(checkupStalledAfter));
}
