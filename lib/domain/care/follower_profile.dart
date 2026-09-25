// **مين بيتابع، وإمتى يوصله الكلام** — دارت نقية.
//
// الإعدادات دي بتغيّر **اللي بيوصل الابن وبس**. تذكير الأب، وسلّم التصعيد،
// وأي حاجة على جهاز الأب — ما بتتلمسش من هنا خالص.

/// صلة القرابة زي ما الابن اختارها.
enum FollowerRelation {
  son('ابن'),
  daughter('بنت'),

  /// حاجة تانية — النص بيكتبه هو، وإحنا ما بنخمّنوش.
  other('حد تاني');

  const FollowerRelation(this.label);

  final String label;

  static FollowerRelation? fromStored(String? stored) =>
      stored == null ? null : values.asNameMap()[stored];
}

/// اللي الأب بيقراه عن متابع واحد.
class FollowerProfile {
  const FollowerProfile({required this.name, this.relation, this.relationOther});

  final String name;
  final FollowerRelation? relation;

  /// نص «حد تاني» زي ما كتبه — null لو ما كتبش.
  final String? relationOther;

  /// «محمد ابنك» / «سارة بنتك» / «محمد (خاله)» / «محمد».
  ///
  /// **الصيغة بتمشي مع الصلة**، مش مع الاسم: الاسم ما بيقولش ولد ولا بنت،
  /// والتخمين من الاسم غلط في ناس حقيقيين.
  String get title => switch (relation) {
        FollowerRelation.son => '$name ابنك',
        FollowerRelation.daughter => '$name بنتك',
        FollowerRelation.other when (relationOther?.trim().isNotEmpty ?? false) =>
          '$name (${relationOther!.trim()})',
        _ => name,
      };

  /// الفعل المتّفق مع الصلة — «بيتابعك» / «بتتابعك».
  String get follows => relation == FollowerRelation.daughter ? 'بتتابعك' : 'بيتابعك';

  /// السطر الكامل لمتابع واحد: «محمد ابنك بيتابعك».
  String get sentence => '$title $follows';
}

/// سطر «مين بيتابعك» على شاشة الأب.
///
/// واحد بياخد جملته كاملة بصيغتها؛ أكتر من واحد بيتعدّوا بأسمائهم وصلاتهم،
/// والفعل بيبقى جمع — «بيتابعوك».
String followersLine(List<FollowerProfile> followers) => switch (followers.length) {
      0 => 'مفيش حد من عيلتك أو ممرضك لسه — ضيفه من هنا',
      1 => followers.single.sentence,
      _ => 'بيتابعوك: ${followers.map((f) => f.title).join('، ')}',
    };

// ------------------------------------------------------------ ساعات الهدوء
//
// **الهدوء للمواعيد والملخصات بس** (قرار المالك، ٢٢ سبتمبر ٢٠٢٦). جرعة
// فايتة بتوصل الابن في أي وقت — تأجيلها لحد الصبح هو بالظبط الحاجة اللي
// السلّم موجود عشان يمنعها، و«اهدى إلا لو مهم» كان معناه ده لما اتضح إن
// مفيش علامة «مهم» أصلاً.

/// نافذة هدوء على موبايل الابن — بالدقايق من نص الليل.
class QuietHours {
  const QuietHours({required this.fromMinute, required this.toMinute});

  /// ٠..١٤٣٩.
  final int fromMinute;
  final int toMinute;

  /// **النافذة اللي بدايتها هي نهايتها مرفوضة**: يا يوم كامل هدوء (يعني
  /// مفيش إشعارات خالص — نفس فخ «إعداد معناه الصمت») يا مفيش نافذة أصلاً.
  /// الاتنين الغامضين دول بيتقالوا بـnull، مش بقيمة.
  bool get isValid => fromMinute != toMinute;

  /// بتلفّ حوالين نص الليل؟ («من ١١ بالليل لـ٧ الصبح»)
  bool get wraps => toMinute < fromMinute;

  int _minuteOf(DateTime at) => at.hour * 60 + at.minute;

  bool contains(DateTime at) {
    if (!isValid) return false;
    final m = _minuteOf(at);
    return wraps ? (m >= fromMinute || m < toMinute) : (m >= fromMinute && m < toMinute);
  }

  /// آخر النافذة اللي [at] واقعة فيها.
  ///
  /// **الوقت بيتبني بالمنشئ مش بـ`add(Duration)`** — مصر بتغيّر الساعة،
  /// والمنشئ بيشتغل بساعة الحيطة.
  DateTime endAfter(DateTime at) {
    final sameDay = DateTime(at.year, at.month, at.day, 0, toMinute);
    // نافذة بتلفّ وإحنا لسه في نصّها الأول (قبل نص الليل) → النهاية بكرة.
    if (wraps && _minuteOf(at) >= fromMinute) {
      return DateTime(at.year, at.month, at.day + 1, 0, toMinute);
    }
    return sameDay;
  }
}

/// **الإشعار الهادي بيتأجّل لآخر النافذة، ما بيتلغيش.**
///
/// «اتحجز» مش «اتشال»: الابن لازم يعرف إن في ميعاد بكرة، بس مش الساعة
/// اتنين بالليل.
DateTime heldUntil(DateTime at, QuietHours? quiet) =>
    quiet != null && quiet.contains(at) ? quiet.endAfter(at) : at;

/// السطر اللي بيتقال على شاشة ساعات الهدوء — **وعلى الإعدادات بعدين**.
///
/// مصدر واحد: الوعد ده لازم يبقى نفس الكلام في كل مكان بيتقال فيه، وإلا
/// واحد منهم بيوعد بحاجة التاني ما بيعملهاش.
const String quietHoursPromise =
    'أي جرعة تفوت هتوصلك في أي وقت — الهدوء للمواعيد والملخصات بس.';

/// **سطر الترحيب في حساب المتابع** — «أهلاً يا محمد — ابن الحاج أحمد».
///
/// الاسم بيتقال زي ما هو كتبه. والصلة بتتضاف **للابن والبنت وبس**: دول
/// اللي صيغتهم مؤكّدة («ابن فلان» / «بنت فلان»). «حد تاني» نصّه حر —
/// «أخوه» مثلاً — وتركيبه في جملة عن المريض بيطلّع عربي غلط، فبنكتفي
/// بالاسم. **مفيش تخمين، ومفيش اسم مخترع**: من غير اسم، ترحيب من غير اسم.
String welcomeLine(FollowerProfile? profile, String patientName) {
  final name = profile?.name.trim() ?? '';
  if (name.isEmpty) return 'أهلاً بيك';
  return switch (profile!.relation) {
    FollowerRelation.son => 'أهلاً يا $name — ابن $patientName',
    FollowerRelation.daughter => 'أهلاً يا $name — بنت $patientName',
    _ => 'أهلاً يا $name',
  };
}
