/// «امسح حسابي» (Apple 5.1.1(v)) — الواجهة. الـSDK في
/// `supabase_account_deletion.dart` وبس، زي باقي خدمات السحابة.
library;

/// نتيجة طلب المسح من السيرفر — تلاتة وبس، عشان الشاشة تقول جملة محددة.
enum DeletionOutcome {
  /// الحساب وكل بياناته على السيرفر اتمسحوا، والمستخدم نفسه اتشال.
  deleted,

  /// مفيش نت — **ولا حاجة اتمسحت**، لا هنا ولا هناك.
  offline,

  /// السيرفر وقع في النص. الحساب لسه موجود، والإعادة آمنة.
  failed,
}

abstract interface class AccountDeletionRemote {
  Future<DeletionOutcome> deleteAccount();
}

/// الكلمة اللي الدالة بتستناها في الجسم — طلب من غير تأكيد صريح بيترفض.
const deleteAccountConfirm = 'delete-my-account';
