import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_native_contact_picker/model/contact.dart';

import 'contact_picker.dart';

/// **الملف الوحيد في التطبيق اللي بيستورد حزمة جهات الاتصال** — زي قاعدة
/// `supabase_*` / `firebase_*`: الـSDK في ملف واحد ورا واجهة، والباقي شايف
/// [ContactPicker] بس. اختبار بيقرا `lib/` ويقع لو الاستيراد ظهر في مكان تاني.
///
/// الحزمة دي مختارة عشان **مفيهاش طريق يعدّد دفتر العناوين**: بتفتح شاشة
/// النظام (CNContactPickerViewController على iOS، ACTION_PICK على أندرويد)
/// وبترجّع اللي الشخص دوس عليه. يعني «بنقرا واحدة وبس» مش وعد بنحافظ عليه
/// بالانضباط — مفيش API تاني من أصله، ومفيش إذن جهات اتصال بيتطلب.
class NativeContactPicker implements ContactPicker {
  const NativeContactPicker();

  @override
  Future<PickedContact?> pickOne() async {
    final Contact? picked;
    try {
      // `selectPhoneNumber` مش `selectContact`: لو الجهة ليها كذا رقم، هو
      // اللي بيقول أنهي رقم — ما بنختارش عنه. الاتنين متنفّذين على
      // الجهازين (اتقروا من سورس الحزمة، مش من الوصف).
      picked = await FlutterNativeContactPicker().selectPhoneNumber();
    } on PlatformException {
      throw const ContactPickerDenied();
    } on MissingPluginException {
      throw const ContactPickerDenied();
    }
    if (picked == null) return null; // قفلها من غير ما يختار

    final phone = picked.selectedPhoneNumber ?? picked.phoneNumbers?.firstOrNull;
    final name = picked.fullName?.trim() ?? '';
    // جهة من غير رقم مالهاش لازمة هنا — الشاشة دي عن حد تتصل بيه.
    if (phone == null || phone.trim().isEmpty) return null;
    return PickedContact(name: name, phone: phone.trim());
  }
}
