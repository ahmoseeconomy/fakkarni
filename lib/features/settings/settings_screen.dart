import '../voice/voice_settings_screen.dart';
import '../voice/help_button.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
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
import '../selfcheck/health_check_screen.dart';
import '../../data/files/paper_share.dart';
import '../billing/family_plan_screen.dart';
import '../medication/refill_actions.dart';
import 'followers_screen.dart';
import '../../core/widgets/legal_links_row.dart';
import '../account/delete_account_screen.dart';
import 'diagnostics_log_screen.dart';
import 'notifications_screen.dart';
import '../emergency/emergency_info_screen.dart';
import '../nearby/nearby_screen.dart';
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
/// اللي الابن المربوط بيشوفه بالظبط (D5.2) — سطر واحد صادق تحت «دائرة
/// الرعاية». لو السحابة بقت بتشيل حاجة جديدة، السطر ده بيتغيّر معاها في نفس
/// الجولة. مش بيقول «مش مربوط» ولا «مربوط» — الموبايل ده ما يعرفش ده بيقين.
const caregiverCanSee =
    'لو ربطت حد من عيلتك، هيشوفوا: أدويتك ومواعيدها، جرعاتك، قياسات السكر، '
    'الملف الصحي والتحاليل، أسئلة الدكتور، وفصيلة الدم والحساسية والأمراض المزمنة. '
    'مش هيشوفوا أرقام الطوارئ ولا الصور، ومش هيقدروا يغيّروا أي حاجة. '
    'الممرض أو المرافق بيشوف نفس ده، وبيأكّد الجرعة بدالك، ويعدّل الأدوية والمواعيد لو سمحتله — '
    'وبيشوف صور الورق بس لو فتحت «شارك صور الورق مع الممرض».';

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
          padding: EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
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
              hint: 'سلّم التذكير، وإمتى عيلتك أو ممرضك بيتبلّغوا',
              onTap: () => _open(const NotificationsScreen()),
            ),
            _ElderModeRow(settings: services.preferences),
            if (services.voice case final voice?)
              _Row(
                key: const ValueKey('settings-voice'),
                icon: Icons.record_voice_over_outlined,
                label: 'الرفيق الصوتي',
                hint: 'بيقولّك الشاشة بتعمل إيه، وملخص يومك الصبح',
                value: voice.enabled ? 'شغّال' : 'مقفول',
                onTap: () => _open(VoiceSettingsScreen(voice: voice)),
              ),
            // «الملف الصحي» تبويب في الدوك — بابين لأوضة واحدة بيخلّي
            // المستخدم يشك إنهم حاجتين مختلفتين.
            _Row(
              icon: Icons.local_pharmacy_outlined,
              label: 'قريب منك',
              hint: 'صيدليات ودكاترة من OpenStreetMap',
              onTap: () => _open(const NearbyScreen()),
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
              hint: 'اربط حد من عيلتك أو ممرضك',
              value: user == null ? 'مش مربوط' : 'مربوط',
              onTap: () => _open(SignInScreen(
                auth: services.auth,
                caregiver: services.caregiver,
                push: services.push,
              )),
            ),
            // «صيدليتي» — الرقم اللي «اطلبه من الصيدلية» بيفتح واتساب عليه
            _Row(
              icon: Icons.local_pharmacy_outlined,
              label: 'صيدليتي',
              hint: 'اسمها ورقم الواتساب — عشان تطلب الدوا لما يقرب يخلص',
              onTap: () => editPharmacy(context),
            ),
            if (services.subscription case final sub?)
              _Row(
                icon: Icons.family_restroom_outlined,
                label: 'اشتراك العيلة',
                hint: 'اشتراك واحد ليك ولعيلتك أو ممرضك — التذكير مجاني للأبد',
                onTap: () async {
                  final patient = await services.routines.getPatient(services.patientId);
                  if (!context.mounted) return;
                  _open(FamilyPlanScreen(service: sub, patientName: patient?.name ?? 'أنا'));
                },
              ),
            // ٠٠٢٦: صور الورق بتفضل هنا إلا لو هو قرّر يشاركها مع ممرضينه
            if (user != null && services.papers != null)
              _SharePapersRow(service: services.papers!, patientId: services.patientId),
            // ٠٠٢٣: مين بيتابعك وبيقدر يعمل إيه — للمريض المربوط وبس
            if (user != null && services.careAdmin != null)
              _Row(
                icon: Icons.manage_accounts_outlined,
                label: 'عيلتك أو ممرضك',
                help: 'help_family',
                hint: 'الدور والصلاحيات لكل واحد، وشيل اللي مش عايزه',
                onTap: () async {
                  final patient = await services.routines.getPatient(services.patientId);
                  if (patient == null || !context.mounted) return;
                  _open(FollowersScreen(admin: services.careAdmin!, patientUuid: patient.uuid));
                },
              ),
            // D5.2: الوصول اتوسّع — الأب يعرفه مننا، مش بالصدفة.
            Padding(
              key: const ValueKey('caregiver-sees'),
              padding: const EdgeInsets.fromLTRB(F.s4, 0, F.s4, F.s12),
              child: Text(
                caregiverCanSee,
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.6),
              ),
            ),
            const LegalLinksRow(),
            const _Row(
              icon: Icons.translate_outlined,
              label: 'اللغة',
              hint: 'النسخة دي عربي بس',
              value: 'عربي',
              onTap: null,
            ),
            // قسم المطوّر — **مش موجود في نسخة المتجر**. سكّة صحوة شاشة
            // القفل مالهاش مصحّح متوصّل، فالسجل ده هو الشاهد الوحيد
            // عليها، ونسخة profile هي الوحيدة اللي بتشغّلها أصلاً.
            if (!kReleaseMode) ...[
              const SizedBox(height: F.gap),
              const FSectionHead('للمطوّر'),
              const SizedBox(height: F.s8),
              _Row(
                icon: Icons.bug_report_outlined,
                label: 'سجل التشخيص',
                hint: 'اللي حصل في آخر صحوة — من سويفت ومن دارت',
                onTap: () => _open(const DiagnosticsLogScreen()),
              ),
              // شاشة الفحص للمطوّر بس — المريض ما يشوفش مشكلة تقنية أبداً
              // (قرار المالك): اللي يتصلّح بيتصلّح لوحده، والباقي للأدمن.
              _Row(
                icon: Icons.health_and_safety_outlined,
                label: 'اطمن إن التذكير هيشتغل',
                hint: 'نتيجة الفحص بأكواده — للمطوّر',
                onTap: () => _open(const HealthCheckScreen()),
              ),
            ],
            if (user != null) ...[
              const SizedBox(height: F.gap),
              FSecondaryButton(
                label: 'تسجيل الخروج',
                onPressed: _busy ? null : () => _signOut(services),
              ),
              const SizedBox(height: F.s8),
              Text(
                'الأدوية والتذكيرات بتفضل على الموبايل زي ما هي — الخروج بيفكّ الربط بس.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
              ),
              // Apple 5.1.1(v): المسح من جوّه التطبيق — صفحته بتقول بالظبط إيه اللي بيتمسح
              if (services.accountDeletion != null) ...[
                const SizedBox(height: F.gap),
                FSecondaryButton(
                  key: const ValueKey('settings-delete-account'),
                  label: 'امسح حسابي',
                  onPressed: _busy
                      ? null
                      : () => _open(const DeleteAccountScreen(who: DeletingAs.patient)),
                ),
              ],
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
              color: F.cardGround,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(F.radiusCard),
                side: BorderSide(color: on ? F.gold : F.line, width: on ? 2 : 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FSwitch(
                      key: const ValueKey('elder-mode'),
                      label: 'نمط كبار السن',
                      subtitle: 'كارت جرعة واحد، خط أكبر، وتبويبتين بس',
                      value: on,
                      onChanged: widget.settings.setElderMode,
                    ),
                    const Align(alignment: AlignmentDirectional.centerEnd, child: HelpButton('help_elder_mode')),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// «شارك صور الورق مع الممرض» — **مقفول افتراضياً**. مفتوح: صور الروشتات
/// والتحاليل بتترفع لمكان خاص ممرضينه بس يقروه (المتابع لأ). قفله بيمسح
/// اللي اترفع.
class _SharePapersRow extends StatefulWidget {
  const _SharePapersRow({required this.service, required this.patientId});

  final PaperShareService service;
  final int patientId;

  @override
  State<_SharePapersRow> createState() => _SharePapersRowState();
}

class _SharePapersRowState extends State<_SharePapersRow> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    PaperShareService.isEnabled().then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s10),
        child: Material(
          color: F.cardGround,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusCard),
            side: BorderSide(color: F.line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s4),
            child: FSwitch(
              key: const ValueKey('share-papers'),
              label: 'شارك صور الورق مع الممرض',
              subtitle: _on
                  ? 'الممرض بيشوف صور روشتاتك وتحاليلك — المتابعين من عيلتك لأ'
                  : 'صور الورق على موبايلك بس — الممرض بيشوف الورقة من غير صورتها',
              value: _on,
              onChanged: (on) async {
                setState(() => _on = on);
                await widget.service.setEnabled(on, patientId: widget.patientId);
              },
            ),
          ),
        ),
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
                  style: TextStyle(
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
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
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
    this.help,
    super.key,
  });

  /// جملة «ساعدني» عن الصف ده (الكتالوج) — null = من غير زرار.
  final String? help;

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
        color: disabled ? F.railGround : F.cardGround,
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
                    color: attention ? F.gold : F.railGround,
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
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                      ),
                    ],
                  ),
                ),
                if (help case final id?) ...[
                  const SizedBox(width: F.s8),
                  HelpButton(id),
                ],
                if (value != null) ...[
                  const SizedBox(width: F.s8),
                  Text(
                    value!,
                    style: TextStyle(
                      fontSize: F.minTextSize,
                      fontWeight: FontWeight.w700,
                      // الحافة الذهبي هي المعنى؛ الكلمة غامقة تتقري (ذهبي على أبيض ≈ ٢:١)
                      color: attention ? F.ink : (disabled ? F.mutedDark : F.green),
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
