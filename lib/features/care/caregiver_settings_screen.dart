import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/dark_mode_toggle.dart';
import '../../core/widgets/primitives.dart';
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
        padding: EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
        children: [
          Text(
            'الإعدادات',
            style: TextStyle(
              fontFamily: F.displayFamily,
              fontSize: F.screenTitleSize,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          const SizedBox(height: F.gap),
          FCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('حسابك',
                          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                    ),
                    StatusChip(label: 'حساب تجريبي'),
                  ],
                ),
                const SizedBox(height: F.s8),
                Text(
                  'بتتابع من الموبايل ده. مفيش أدوية ولا مواعيد بتتسجّل هنا — كل حاجة جاية من موبايل والدك.',
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
                ),
                const SizedBox(height: F.s12),
                FSecondaryButton(label: _busy ? 'ثواني…' : 'تسجيل الخروج', onPressed: _busy ? null : _signOut),
              ],
            ),
          ),
          const SizedBox(height: F.s12),
          // نص الوعد التاني: التنبيه اللي بيوصل للموبايل ده. الفحص هنا
          // بيتشغّل كابن، فبيسأل عن التوكن بدل مدى التذكير.
          FSecondaryButton(
            label: 'اطمن إن التنبيه هيوصلك',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const HealthCheckScreen(isCaregiver: true),
            )),
          ),
          const SizedBox(height: F.s12),
          // **نفس مفتاح الأب، ونفس الويدجت.** الشريط العلوي بتاع «متابعة»
          // مش شريط الهيكل زي عند الأب — كل تبويب هنا ليه شريطه، و
          // «الإعدادات» مالهاش شريط أصلاً. فالصف ده هو المكان الوحيد اللي
          // بيتوصّل له من أي تبويب. الكلمة جنب الزرار عشان «مفيش زرار
          // أيقونة من غير كلمة».
          FCard(
            child: Row(
              children: [
                Expanded(
                  child: Text('الوضع الليلي',
                      style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: F.darkMode,
                  builder: (context, dark, _) => Text(
                    dark ? 'شغّال' : 'مقفول',
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  ),
                ),
                const DarkModeToggle(),
              ],
            ),
          ),
          const SizedBox(height: F.s12),
          FCard(
            child: Row(
              children: [
                Expanded(
                  child: Text('اللغة',
                      style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                ),
                Text('عربي — النسخة دي عربي بس', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
              ],
            ),
          ),
        ],
      );
}
