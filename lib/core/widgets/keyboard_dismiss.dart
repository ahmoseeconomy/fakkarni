import 'package:flutter/material.dart';

/// **الكيبورد بيتقفل من مكان واحد — مش من كل شاشة.**
///
/// العطل اللي عمل ده (آيفون حقيقي): «بيانات الطوارئ» بتحفظ وبتعمل `pop`
/// وهي سايبة التركيز على حقل النص. الحقل بيروح مع الشاشة، والكيبورد
/// بيفضل مفتوح على «يومك» — **من غير أي حقل يقفله بيه**. وأوحش من كده:
/// الكيبورد المرفوع بيزقّ الدوك لفوق، فـ«ضيف» و«القريب مني» بيقعدوا
/// **فوق** «تأكيد الجرعة» — وراجل عنده ٧٢ سنة مادّ إيده للتأكيد بيدوس
/// «ضيف».
///
/// **وإصلاح الشاشة الواحدة كان هيسيب الفورم اللي بعدها مكسور.** قبل
/// الجولة دي كان فيه `unfocus` واحدة في التطبيق كله (`glucose_screen`)،
/// يعني كل شاشة تانية كانت ممكن تسرّب كيبورد. فالعلاج في الجذر:
///  * [FakkarniNavigatorObserver] — تركيز بيتسلّم عند كل `push` و`pop`،
///    فمفيش شاشة تقدر تورّث كيبوردها للّي بعدها مهما نسيت.
///  * [KeyboardDismiss] — دوسة برّه أي حقل بتقفل الكيبورد.
///  * وكل حقل في التطبيق له `textInputAction`، فالكيبورد نفسه دايماً
///    فيه باب خروج (اختبار بيقفل على دي).

/// بيسلّم التركيز عند كل تغيير مسار.
///
/// `didPush` كمان مش `didPop` بس: شاشة بتفتح شاشة تانية وهي كاتبة (زي
/// «ضيف دوا» وهي بتفتح محرر الجرعة) بتسيب الكيبورد مفتوح فوق الشاشة
/// الجديدة بنفس الطريقة.
class FakkarniNavigatorObserver extends NavigatorObserver {
  void _release() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _release();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _release();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _release();
}

/// دوسة على أي مكان مش حقل بتقفل الكيبورد.
///
/// `translucent` عشان الدوسة تعدّي للّي تحتها برضه؛ ولو فيه زرار تحت
/// الصبع، هو اللي بيكسب في ساحة الإيماءات (الأعمق بيكسب) وده ما بيتندهش.
/// يعني الودجت دي ما بتاكلش ولا دوسة على حاجة شغّالة.
class KeyboardDismiss extends StatelessWidget {
  const KeyboardDismiss({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      );
}

/// الكيبورد مرفوع دلوقتي؟
///
/// **الدوك والزراير العايمة بتختفي وهو مرفوع.** مش تجميل: الدوك بيترفع
/// معاه ويقعد فوق المحتوى، والزراير العايمة بتغطّي الزرار الأساسي.
///
/// **وبتتقرا من مصدرين، ودي مش حزام وحمّالة.** `MediaQuery.viewInsetsOf`
/// هي اللي بتخلّي الودجت تتبني تاني أول ما الكيبورد يتحرّك — من غيرها
/// مفيش حاجة تقول للشاشة تعيد البناء. بس `Scaffold` وهو
/// `resizeToAvoidBottomInset` **بيصفّر الـinset لجسمه** عشان يزقّ
/// المحتوى بنفسه، فأي شاشة جوّه الشِل بتشوف صفر وهي مغطّاة بالكيبورد.
/// الرقم الخام من `View` هو الحقيقة في الحالة دي، وإعادة البناء بتيجي
/// من الشِل اللي فوقها (هو معتمد على `MediaQuery` أصلاً).
bool keyboardIsUp(BuildContext context) {
  if (MediaQuery.viewInsetsOf(context).bottom > 0) return true;
  final view = View.maybeOf(context);
  return view != null && view.viewInsets.bottom > 0;
}
