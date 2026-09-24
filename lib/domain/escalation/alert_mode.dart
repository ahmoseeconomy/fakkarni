/// نوع التنبيه — قد إيه التذكير بيرجع يرنّ لحد ما حد يتصرّف.
///
/// **مش درجة على السلّم ومش بيلمسه**: الدرجتين +١٥ و+٣٠ ومهلة السيرفر
/// وإشعار الابن زي ما هم في التلاتة. اللي بيتغيّر هو الإعادات المحلية
/// بس — نفس التذكير تاني، على موبايل المريض.
library;

enum AlertMode {
  /// التذكير الأصلي وبس — مفيش إعادة.
  once(every: Duration.zero, count: 0),

  /// +٥ و+١٠ و+١٥ — السلوك اللي كان (والافتراضي).
  repeating(every: Duration(minutes: 5), count: 3),

  /// كل ٣ دقايق لحد ما يأكّد أو يأجّل — بسقف ١٠ عشان ميزانية iOS.
  continuous(every: Duration(minutes: 3), count: 10);

  const AlertMode({required this.every, required this.count});

  /// المسافة بين كل إعادة واللي بعدها — من معاد الجرعة الأصلي.
  final Duration every;

  /// أقصى عدد إعادات لتذكير واحد.
  final int count;

  /// الافتراضي لما المستخدم ما اختارش — «يتكرر».
  static const AlertMode standard = repeating;

  /// أكتر عدد إعادات في أي نوع — عرض نطاقات الأرقام بيتحدد منه.
  static int get maxCount => values.map((m) => m.count).reduce((a, b) => a > b ? a : b);

  /// الأقوى بين كذا نوع — تذكير واحد فيه دواءين بنوعين بياخد الأكتر إلحاحاً.
  static AlertMode strongest(Iterable<AlertMode> modes) =>
      modes.fold(once, (a, b) => b.count > a.count ? b : a);

  /// الاسم المخزّن — الحروف دي هي اللي في العمود، فما تتغيّرش.
  String get storageName => name;

  static AlertMode? fromStorage(String? name) {
    if (name == null) return null;
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }

  String get label => switch (this) {
        once => 'مرة واحدة',
        repeating => 'يتكرر',
        continuous => 'مستمر',
      };

  String get hint => switch (this) {
        once => 'التذكير بيرن مرة، وبعدها سلّم التذكير زي ما هو',
        repeating => 'بيرجع يرن بعد ٥ و١٠ و١٥ دقيقة لو ما أكّدتش',
        continuous => 'بيرجع يرن كل ٣ دقايق لحد ما تأكّد أو تأجّل — لحد نص ساعة',
      };
}
