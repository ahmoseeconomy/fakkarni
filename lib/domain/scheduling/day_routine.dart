import '../wording/rule_wording.dart';

/// مراسي اليوم.
///
/// الروشتة بتتكلم بالمراسي دي — «قبل الفطار»، «قبل النوم» — مش بالساعة.
/// عشان كده التطبيق بيسأل المستخدم عن يومه مرة واحدة، وبعدها أي روشتة
/// بتترتّب على الروتين ده لوحدها.
enum DayAnchor {
  wake,
  breakfast,
  lunch,
  dinner,
  sleep;

  /// الاسم المعروض للمستخدم بالعربي — من `domain/wording` عشان جانب الابن
  /// يقول نفس الكلمة من غير ما يستورد الجدولة.
  String get label => anchorWords[name]!;
}

/// الإزاحة الافتراضية «قبل» مرساة — عرف تشغيلي بيتعدّل، مش توجيه طبي.
///
/// ٣٠ دقيقة قبل الأكل، و**١٥ قبل النوم** (القاعدة السادسة في CLAUDE.md).
/// مكان واحد عشان القارئ والمحرر ما يختلفوش تاني.
int defaultOffsetBefore(DayAnchor anchor) =>
    anchor == DayAnchor.sleep ? 15 : 30;

/// وقت في اليوم، متخزّن كدقائق من منتصف الليل (0 → 1439).
class MinuteOfDay implements Comparable<MinuteOfDay> {
  const MinuteOfDay(this.minutes)
      : assert(minutes >= 0 && minutes < 1440, 'لازم تكون بين 0 و 1439');

  /// مُنشئ مريح: `MinuteOfDay.hm(7, 30)` يعني ٧:٣٠.
  factory MinuteOfDay.hm(int hour, [int minute = 0]) =>
      MinuteOfDay(hour * 60 + minute);

  final int minutes;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  @override
  int compareTo(MinuteOfDay other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) =>
      other is MinuteOfDay && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// روتين يوم المريض — بيتسأل مرة واحدة في عمر الحساب.
///
/// اليوم عندنا بيبدأ من **الصحيان** مش من منتصف الليل. وده اللي بيخلي
/// النوم الساعة ١ صباحاً يتحسب على اليوم الصح بدل ما يرجع لورا.
class DayRoutine {
  const DayRoutine({
    required this.wake,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.sleep,
    this.unset = const {},
  });

  final MinuteOfDay wake;
  final MinuteOfDay breakfast;
  final MinuteOfDay lunch;
  final MinuteOfDay dinner;
  final MinuteOfDay sleep;

  /// **المراسي اللي المستخدم ما حدّدهاش** — الروتين بقى اختياري.
  ///
  /// المرساة اللي هنا لسه ليها رقم في [at] — بس الرقم ده **مكان راحة**
  /// مش إجابة: المحرّك عمره ما يجدول جرعة عليه ([ScheduleEngine]
  /// بيتخطّاها)، والمحرّر ما بيعرضهاش غير بعد ما يسأل عن ميعادها. الصحيان
  /// وهو مش متحدد بيفضل بيحدد **حدود اليوم بس** (جرعة ثابتة الساعة ١ ص
  /// بتتحسب على يوم امبارح) — وده ما بيحرّكش ولا دقيقة من أي دوا.
  final Set<DayAnchor> unset;

  bool isSet(DayAnchor anchor) => !unset.contains(anchor);

  /// كل المراسي متحددة — الروتين الكامل اللي كل الحسابات القديمة اتكتبت له.
  bool get isComplete => unset.isEmpty;

  /// المستخدم حدّد [anchor] بإيده على [time].
  DayRoutine withAnchor(DayAnchor anchor, MinuteOfDay time) => DayRoutine(
        wake: anchor == DayAnchor.wake ? time : wake,
        breakfast: anchor == DayAnchor.breakfast ? time : breakfast,
        lunch: anchor == DayAnchor.lunch ? time : lunch,
        dinner: anchor == DayAnchor.dinner ? time : dinner,
        sleep: anchor == DayAnchor.sleep ? time : sleep,
        unset: {for (final a in unset) if (a != anchor) a},
      );

  /// الروتين الافتراضي لما المستخدم يختار «مش متأكد».
  /// مش تخمين طبي — مجرد نقطة بداية المستخدم بيعدّلها.
  ///
  /// القيم من README (D2.6): الصحيان ٦:٣٠ · الفطار ٧:٣٠ · الغدا ٢:٠٠ ·
  /// العشا ٨:٠٠ · النوم ١١:٣٠. المصدر الوحيد للافتراضي — «مش متأكد» في
  /// الأسئلة وإعادة الجدولة من غير روتين بيقروا من هنا.
  static final DayRoutine fallback = DayRoutine(
    wake: MinuteOfDay.hm(6, 30),
    breakfast: MinuteOfDay.hm(7, 30),
    lunch: MinuteOfDay.hm(14),
    dinner: MinuteOfDay.hm(20),
    sleep: MinuteOfDay.hm(23, 30),
  );

  /// روتين ما اتحددش منه ولا مرساة — اللي بيتحفظ لما المستخدم يعدّي كل
  /// الأسئلة بـ«مش دلوقتي». نفس أرقام [fallback] كأماكن راحة، **وكلها
  /// معلّمة إنها مش بتاعته**.
  static final DayRoutine none = fallback.copyWith(unset: DayAnchor.values.toSet());

  MinuteOfDay at(DayAnchor anchor) => switch (anchor) {
        DayAnchor.wake => wake,
        DayAnchor.breakfast => breakfast,
        DayAnchor.lunch => lunch,
        DayAnchor.dinner => dinner,
        DayAnchor.sleep => sleep,
      };

  /// كام دقيقة بين الصحيان والمرساة دي.
  ///
  /// أي مرساة وقتها أبكر من الصحيان معناها إنها بتاعة اليوم اللي بعده —
  /// زي النوم الساعة ١ ص لواحد بيصحى ٧ ص (بيرجّع 1080 = ١٨ ساعة).
  int minutesFromDayStart(DayAnchor anchor) =>
      (at(anchor).minutes - wake.minutes + 1440) % 1440;

  DayRoutine copyWith({
    MinuteOfDay? wake,
    MinuteOfDay? breakfast,
    MinuteOfDay? lunch,
    MinuteOfDay? dinner,
    MinuteOfDay? sleep,
    Set<DayAnchor>? unset,
  }) =>
      DayRoutine(
        wake: wake ?? this.wake,
        breakfast: breakfast ?? this.breakfast,
        lunch: lunch ?? this.lunch,
        dinner: dinner ?? this.dinner,
        sleep: sleep ?? this.sleep,
        unset: unset ?? this.unset,
      );

  /// روتينين بنفس الخمس مواعيد **ونفس اللي مش متحدد** هما نفس الروتين —
  /// ده اللي بيخلّي «رجّع الأصل بالحرف» جملة تتختبر.
  @override
  bool operator ==(Object other) =>
      other is DayRoutine &&
      other.wake == wake &&
      other.breakfast == breakfast &&
      other.lunch == lunch &&
      other.dinner == dinner &&
      other.sleep == sleep &&
      other.unset.length == unset.length &&
      other.unset.containsAll(unset);

  @override
  int get hashCode => Object.hash(wake, breakfast, lunch, dinner, sleep, unset.length);

  @override
  String toString() => 'DayRoutine(صحيان $wake، فطار $breakfast، '
      'غدا $lunch، عشا $dinner، نوم $sleep'
      '${unset.isEmpty ? '' : '، مش متحدد: ${unset.map((a) => a.name).join('،')}'})';
}
