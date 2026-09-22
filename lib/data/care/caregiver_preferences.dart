import '../../domain/care/follower_profile.dart';

/// تفضيلات المتابع — **صف واحد لكل (متابع، مريض)، في السحابة**.
///
/// ليه السحابة مش drift: جهاز الابن مالوش نسخة محلية من أي حاجة (قاعدة
/// ٣.٥)، والتفضيلات دي لازم تعيش بعد إعادة التنصيب ولازم **الأب** يقرا
/// منها الاسم والصلة. drift هنا كان هيبقى نسخة تانية تختلف في صمت.
class CaregiverPreferences {
  const CaregiverPreferences({
    this.name,
    this.relation,
    this.relationOther,
    this.alertScope = AlertScope.everyMissedDose,
    this.quietFromMinute,
    this.quietToMinute,
  });

  /// اسمه زي ما كتبه — الأب بيقراه. null = لسه ما اتسألش أو تخطّى.
  final String? name;
  final FollowerRelation? relation;
  final String? relationOther;

  final AlertScope alertScope;

  /// نافذة الهدوء بالدقايق — الاتنين null يعني مفيش هدوء.
  final int? quietFromMinute;
  final int? quietToMinute;

  QuietHours? get quietHours {
    final from = quietFromMinute, to = quietToMinute;
    if (from == null || to == null) return null;
    final window = QuietHours(fromMinute: from, toMinute: to);
    // نافذة بدايتها = نهايتها مش نافذة (شوف [QuietHours.isValid]).
    return window.isValid ? window : null;
  }

  FollowerProfile? get profile => name == null || name!.trim().isEmpty
      ? null
      : FollowerProfile(name: name!.trim(), relation: relation, relationOther: relationOther);

  CaregiverPreferences copyWith({
    String? name,
    FollowerRelation? relation,
    String? relationOther,
    AlertScope? alertScope,
    int? quietFromMinute,
    int? quietToMinute,
    bool clearQuiet = false,
  }) =>
      CaregiverPreferences(
        name: name ?? this.name,
        relation: relation ?? this.relation,
        relationOther: relationOther ?? this.relationOther,
        alertScope: alertScope ?? this.alertScope,
        quietFromMinute: clearQuiet ? null : (quietFromMinute ?? this.quietFromMinute),
        quietToMinute: clearQuiet ? null : (quietToMinute ?? this.quietToMinute),
      );
}

/// إمتى يتنبّه.
///
/// **قيمة واحدة النهارده، والعمود موجود عشان التانية**: «الأدوية المهمة
/// بس» كانت بتفترض علامة «مهم» على الدوا، والعلامة دي **اتشالت عن قصد**
/// في ٢ سبتمبر ٢٠٢٦ (القاعدة ٦ — اختيار إن دوا «مهم» حكم طبي). من غيرها
/// الاختيار التاني معناه «مفيش تنبيهات خالص»، وده إعداد بيسكت في صمت.
///
/// العمود والفلتر والرسالة كلهم مبنيين ومتختبرين، فاليوم اللي تبقى فيه
/// العلامة موجودة، فتح الاختيار التاني سطر واحد. شوف «Pricing» و«تفضيلات
/// المتابع» في CLAUDE.md.
enum AlertScope {
  /// أي جرعة تفوت.
  everyMissedDose;

  static AlertScope fromStored(String? stored) =>
      values.asNameMap()[stored] ?? AlertScope.everyMissedDose;
}

/// بابها الوحيد — الابن بيقرا ويكتب صفّه هو، والأب بيقرا الاسم والصلة بس.
abstract interface class CaregiverPreferencesService {
  /// تفضيلات المتابع الحالي مع المريض ده — الافتراضي لو مفيش صف.
  Future<CaregiverPreferences> load(String patientUuid);

  Future<void> save(String patientUuid, CaregiverPreferences preferences);

  /// **اللي الأب بيقراه**: الاسم والصلة بس، لكل اللي بيتابعوه.
  ///
  /// مفيش ساعات هدوء ولا نطاق تنبيه هنا — دي حاجة الابن، والأب مالوش
  /// دعوة بيها. الحد ده متفروض على السيرفر بدالة بترجّع العمودين دول
  /// وبس، مش بسياسة صف (سياسات بوستجرس على الصف مش على العمود).
  Future<List<FollowerProfile>> followers(String patientUuid);
}
