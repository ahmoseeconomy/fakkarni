// **مولّد من `ios/Runner/GoogleService-Info.plist` — متكتبش بالإيد.**
//
// ليه ملف دارت مش الـplist جوّه الحزمة: ضمّ ملف للحزمة محتاج تعديل
// `project.pbxproj`، وده ملف **عمره ما بيتكوميت** (قاعدة التسليم). فالتهيئة
// على iOS بتاخد القيم دي صراحةً (`Firebase.initializeApp(options:)`) —
// نفس قيم الـplist بالظبط، و`ios_push_setup_test` مرآة بتقارنهم حرف بحرف.
// دي بيانات تعريف مش أسرار — زي `android/app/google-services.json` المتكوميت.
import 'package:firebase_core/firebase_core.dart';

const firebaseIosOptions = FirebaseOptions(
  apiKey: 'AIzaSyB-W0CMJSs1RlEiffKmdsTL3XbfEHRir5I',
  appId: '1:13438968334:ios:b82aaad36cd349804ed25f',
  messagingSenderId: '13438968334',
  projectId: 'fakkarni-5704c',
  storageBucket: 'fakkarni-5704c.firebasestorage.app',
  iosBundleId: 'com.fakrny.app',
);
