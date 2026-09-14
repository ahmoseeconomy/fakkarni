import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/fa_mark.dart';
import '../../core/widgets/primitives.dart';
import '../../data/auth/auth_service.dart';
import '../../domain/scheduling/day_routine.dart';
import '../link/sign_in_screen.dart';
import '../routine/edit_routine_screen.dart';
import '../routine/ramadan_screen.dart';
import 'notifications_screen.dart';
import '../emergency/emergency_info_screen.dart';
import '../records/health_file_screen.dart';
import '../../data/repositories/preferences_repository.dart';

/// «الإعدادات» (المخطط 33) — بس الصفوف اللي وراها حاجة حقيقية.
///
/// كارت الحساب بيقول الحقيقة: «حساب تجريبي» طول ما الدخول مجهول (دين
/// تقني ٢)، و«مش مربوط» لو مفيش جلسة أصلاً. «نمط كبار السن» و«التنبيهات»
/// دخلوا في D3.3 (تفضيلات الجهاز)، و«معلومات الطوارئ» في D3.4. الاسم والسن
/// والتصدير مش هنا — مالهمش باك إند، وصف بيفتح على فراغ أسوأ من صف مش موجود.
/// «اللغة: عربي» معروض ومعطّل.
///
/// الخروج بيمسح توكن الإشعارات **قبل** الجلسة — نفس ترتيب شاشة الربط:
/// مسح الصف محتاج الجلسة اللي بتملكه.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _patientName;
  DayRoutine? _routine;
  bool _ramadanOn = false;
  bool _busy = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  Future<void> _reload() async {
    final services = AppScope.of(context);
    final patient = await services.routines.getPatient(services.patientId);
    final routine = await services.routines.getRoutine(services.patientId);
    final ramadan = await services.routines.ramadanTimes(services.patientId);
    if (!mounted) return;
    setState(() {
      _patientName = patient?.name;
      _routine = routine;
      _ramadanOn = ramadan != null;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _reload();
  }

  Future<void> _signOut(AppServices services) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // قبل الخروج مش بعده — مسح صف التوكن محتاج الجلسة الحالية
      await services.push?.clear();
      await services.auth?.signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final routine = _routine;

    return StreamBuilder<FakkarniUser?>(
      stream: services.auth?.authState,
      initialData: services.auth?.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s30 * 2),
          children: [
            const Text(
              'الإعدادات',
              style: TextStyle(
                fontFamily: F.displayFamily,
                fontSize: F.screenTitleSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
              ),
            ),
            const SizedBox(height: F.s12),
            _AccountCard(name: _patientName ?? 'أنا', user: user),
            const SizedBox(height: F.gap),
            _Row(
              icon: Icons.wb_sunny_outlined,
              label: 'مواعيد يومك',
              hint: 'الصحيان والأكل والنوم — كل الجرعات بتترتّب عليهم',
              value: routine == null ? null : _hm(routine.breakfast),
              onTap: routine == null ? null : () => _open(EditRoutineScreen(routine: routine)),
            ),
            _Row(
              icon: Icons.nightlight_outlined,
              label: 'وضع رمضان',
              hint: _ramadanOn ? 'جدولك على السحور والمغرب' : 'الفطار يبقى المغرب والعشا السحور',
              value: _ramadanOn ? 'شغّال' : 'مقفول',
              attention: _ramadanOn,
              onTap: () => _open(const RamadanScreen()),
            ),
            _Row(
              icon: Icons.notifications_outlined,
              label: 'التنبيهات',
              hint: 'سلّم التذكير، وإمتى ابنك بيتبلّغ',
              onTap: () => _open(const NotificationsScreen()),
            ),
            _ElderModeRow(settings: services.preferences),
            _Row(
              icon: Icons.folder_outlined,
              label: 'الملف الصحي',
              hint: 'الزيارات والتحاليل والأشعة والروشتات',
              onTap: () => _open(const HealthFileScreen()),
            ),
            _Row(
              icon: Icons.medical_information_outlined,
              label: 'معلومات الطوارئ',
              hint: 'فصيلة الدم، الحساسية، وجهات الاتصال',
              onTap: () => _open(const EmergencyInfoScreen()),
            ),
            _Row(
              icon: Icons.people_outline,
              label: 'دائرة الرعاية',
              hint: 'اربط ابنك أو بنتك عشان يتابعوك',
              value: user == null ? 'مش مربوط' : 'مربوط',
              onTap: () => _open(SignInScreen(
                auth: services.auth,
                caregiver: services.caregiver,
                push: services.push,
              )),
            ),
            const _Row(
              icon: Icons.translate_outlined,
              label: 'اللغة',
              hint: 'النسخة دي عربي بس',
              value: 'عربي',
              onTap: null,
            ),
            if (user != null) ...[
              const SizedBox(height: F.gap),
              FSecondaryButton(
                label: 'تسجيل الخروج',
                onPressed: _busy ? null : () => _signOut(services),
              ),
              const SizedBox(height: F.s8),
              const Text(
                'الأدوية والتذكيرات بتفضل على الموبايل زي ما هي — الخروج بيفكّ الربط بس.',
                style: TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.5),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _hm(MinuteOfDay t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '${_ar(h)}:${_ar(m)} ${t.hour < 12 ? 'ص' : 'م'}';
  }

  static String _ar(Object v) => v.toString().replaceAllMapped(
        RegExp('[0-9]'),
        (m) => String.fromCharCode(0x660 + int.parse(m.group(0)!)),
      );
}

/// «نمط كبار السن» — مفتاح على طول، مش صف بيفتح شاشة: التغيير بيبان
/// فوراً في التبويبات تحت. شغّال = ذهبي (الحالة اللي إنت عليها).
class _ElderModeRow extends StatefulWidget {
  const _ElderModeRow({required this.settings});

  final PreferencesRepository settings;

  @override
  State<_ElderModeRow> createState() => _ElderModeRowState();
}

class _ElderModeRowState extends State<_ElderModeRow> {
  late final Stream<DeviceSettings> _stream = widget.settings.watch();

  @override
  Widget build(BuildContext context) => StreamBuilder<DeviceSettings>(
        stream: _stream,
        builder: (context, snap) {
          final on = snap.data?.elderMode ?? false;
          return Padding(
            padding: const EdgeInsets.only(bottom: F.s10),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(F.radiusCard),
                side: BorderSide(color: on ? F.gold : F.line, width: on ? 2 : 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s4),
                child: FSwitch(
                  key: const ValueKey('elder-mode'),
                  label: 'نمط كبار السن',
                  subtitle: 'كارت جرعة واحد، خط أكبر، وتبويبتين بس',
                  value: on,
                  onChanged: widget.settings.setElderMode,
                ),
              ),
            ),
          );
        },
      );
}

/// كارت الحساب: علامة ف على بلاطة، الاسم، وشريحة الحالة بالحقيقة.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.name, required this.user});

  final String name;
  final FakkarniUser? user;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = user == null
        ? ('مش مربوط', StatusTone.neutral)
        : user!.isAnonymous
            ? ('حساب تجريبي', StatusTone.neutral)
            : ('مربوط', StatusTone.ok);
    return FCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: F.greenDeep,
              borderRadius: BorderRadius.circular(F.radiusTile),
            ),
            alignment: Alignment.center,
            child: const FaMark(size: 36),
          ),
          const SizedBox(width: F.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
                const SizedBox(height: F.s4),
                Text(
                  user == null
                      ? 'التطبيق كامل من غير حساب — الربط بس محتاجه'
                      : user!.isAnonymous
                          ? 'دخول تجريبي على الجهاز ده'
                          : (user!.email ?? ''),
                  style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: F.s8),
          StatusChip(label: label, tone: tone),
        ],
      ),
    );
  }
}

/// صف إعداد: أيقونة، عنوان، سطر شرح، وقيمة على الجنب. null onTap = معطّل.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.value,
    this.attention = false,
  });

  final IconData icon;
  final String label;
  final String hint;
  final String? value;
  final bool attention;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: F.s10),
      child: Material(
        color: disabled ? F.ivoryPale : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(F.radiusCard),
          side: BorderSide(color: attention ? F.gold : F.line, width: attention ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radiusCard),
          child: Container(
            constraints: const BoxConstraints(minHeight: F.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: attention ? F.gold : F.ivoryWarm,
                    borderRadius: BorderRadius.circular(F.radiusTile),
                  ),
                  child: Icon(icon, size: 24, color: disabled ? F.mutedLight : F.ink),
                ),
                const SizedBox(width: F.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: F.minBodySize,
                          fontWeight: FontWeight.w700,
                          color: disabled ? F.mutedDark : F.ink,
                        ),
                      ),
                      Text(
                        hint,
                        style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.4),
                      ),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: F.s8),
                  Text(
                    value!,
                    style: TextStyle(
                      fontSize: F.minTextSize,
                      fontWeight: FontWeight.w700,
                      color: attention ? F.gold : (disabled ? F.mutedDark : F.green),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
