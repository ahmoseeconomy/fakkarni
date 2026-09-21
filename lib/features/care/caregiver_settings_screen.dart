import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/dark_mode_toggle.dart';
import 'caregiver_ui.dart';
import '../selfcheck/health_check_screen.dart';

/// «الإعدادات» عند الابن (D4) — الحساب واللغة وبس.
///
/// كل صفوف إعدادات المريض (مواعيد يومك، رمضان، نمط كبار السن، التنبيهات،
/// الملف الصحي، الطوارئ، قريب منك) بتخص مريض على الموبايل ده، والابن مش
/// مريض. صف بيفتح على حاجة مالهاش معنى أوحش من صف مش موجود.
class CaregiverSettingsScreen extends StatefulWidget {
  const CaregiverSettingsScreen({super.key});

  @override
  State<CaregiverSettingsScreen> createState() => _CaregiverSettingsScreenState();
}

class _CaregiverSettingsScreenState extends State<CaregiverSettingsScreen> {
  bool _busy = false;

  Future<void> _signOut() async {
    if (_busy) return;
    final services = AppScope.of(context);
    setState(() => _busy = true);
    // **قبل** الخروج، مش بعده — نفس ترتيب SignInScreen: مسح صف التوكن
    // محتاج الجلسة، وإلا الموبايل ده يفضل يستقبل تنبيهات عن غريب.
    await services.push?.clear();
    await services.auth?.signOut();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(F.carePad, F.careRowGap, F.carePad,
            F.carePad + MediaQuery.of(context).padding.bottom),
        children: [
          Text(
            'الإعدادات',
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.careTitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          const SizedBox(height: F.careRowGap),
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('حسابك',
                          style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                    ),
                    Text('حساب تجريبي',
                    style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark)),
                  ],
                ),
                const SizedBox(height: F.s8),
                Text(
                  'بتتابع من الموبايل ده. مفيش أدوية ولا مواعيد بتتسجّل هنا — كل حاجة جاية من موبايل والدك.',
                  style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.5),
                ),
                const SizedBox(height: F.s12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: CareTextAction(
                    label: _busy ? 'ثواني…' : 'تسجيل الخروج',
                    icon: Icons.logout,
                    onPressed: _busy ? () {} : _signOut,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: F.s12),
          // نص الوعد التاني: التنبيه اللي بيوصل للموبايل ده. الفحص هنا
          // بيتشغّل كابن، فبيسأل عن التوكن بدل مدى التذكير.
          CareCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const HealthCheckScreen(isCaregiver: true),
              )),
              child: Container(
                constraints: const BoxConstraints(minHeight: F.careTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: F.carePad),
                child: Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 18, color: F.green),
                    const SizedBox(width: F.s10),
                    Expanded(
                      child: Text('اطمن إن التنبيه هيوصلك',
                          style: TextStyle(
                              fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                    ),
                    Icon(Icons.chevron_left, size: 18, color: F.mutedDark),
                  ],
                ),
              ),
            ),
          ),
          // **نفس مفتاح الأب، ونفس الويدجت.** الشريط العلوي بتاع «متابعة»
          // مش شريط الهيكل زي عند الأب — كل تبويب هنا ليه شريطه، و
          // «الإعدادات» مالهاش شريط أصلاً. فالصف ده هو المكان الوحيد اللي
          // بيتوصّل له من أي تبويب. الكلمة جنب الزرار عشان «مفيش زرار
          // أيقونة من غير كلمة».
          CareCard(
            child: Row(
              children: [
                Expanded(
                  child: Text('الوضع الليلي',
                      style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: F.darkMode,
                  builder: (context, dark, _) => Text(
                    dark ? 'شغّال' : 'مقفول',
                    style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark),
                  ),
                ),
                const DarkModeToggle(),
              ],
            ),
          ),
          CareCard(
            child: Row(
              children: [
                Expanded(
                  child: Text('اللغة',
                      style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                ),
                Text('عربي — النسخة دي عربي بس', style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark)),
              ],
            ),
          ),
        ],
      );
}
