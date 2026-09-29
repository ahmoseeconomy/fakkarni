import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/dark_mode_toggle.dart';
import 'dart:async';

import '../../data/care/caregiver_preferences.dart';
import '../../data/care/caregiver_remote.dart';
import '../../domain/care/follower_profile.dart';
import 'onboarding/caregiver_onboarding_screen.dart';
import 'caregiver_ui.dart';
import '../billing/family_plan_screen.dart';
import '../nurse/nurse_reminders.dart';
import '../selfcheck/health_check_screen.dart';
import '../account/delete_account_screen.dart';
import '../../core/widgets/legal_links_row.dart';

/// «الإعدادات» عند الابن (D4) — الحساب واللغة وبس.
///
/// كل صفوف إعدادات المريض (مواعيد يومك، رمضان، نمط كبار السن، التنبيهات،
/// الملف الصحي، الطوارئ، قريب منك) بتخص مريض على الموبايل ده، والابن مش
/// مريض. صف بيفتح على حاجة مالهاش معنى أوحش من صف مش موجود.
class CaregiverSettingsScreen extends StatefulWidget {
  const CaregiverSettingsScreen({
    this.patient,
    this.nurseReminders = false,
    this.onNurseRemindersChanged,
    this.nursePatients = const [],
    this.onNurseDoseRemindersChanged,
    super.key,
  });

  /// ٢٤ سبتمبر ٢٠٢٦: حساب الممرض بيشوف «فكّرني بمواعيده» هنا. المتابع لأ.
  final bool nurseReminders;
  final VoidCallback? onNurseRemindersChanged;

  /// 0035: لكل مريض بيتابعه كممرض — «نبهني بمواعيد الدوا» و«نبهني لو مافيش
  /// تأكيد»، في السحابة (الثاني السيرفر بيقراه).
  final List<CaregiverPatient> nursePatients;
  final void Function(String patientUuid, bool on)? onNurseDoseRemindersChanged;

  /// المريض المربوط — منه الـuuid اللي التفضيلات متعلّقة بيه.
  /// null قبل ما أول صورة توصل: الصف ساعتها ما بيظهرش.
  final CaregiverPatient? patient;

  @override
  State<CaregiverSettingsScreen> createState() => _CaregiverSettingsScreenState();
}

class _CaregiverSettingsScreenState extends State<CaregiverSettingsScreen> {
  bool _busy = false;

  /// اللي هو كتبه عن نفسه — منه سطر الترحيب. null لحد ما يوصل، ومن غيره
  /// الترحيب بيبقى من غير اسم بدل ما نخترع واحد.
  FollowerProfile? _me;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadMe()));
  }

  @override
  void didUpdateWidget(CaregiverSettingsScreen old) {
    super.didUpdateWidget(old);
    // **الشاشة جوّه `IndexedStack`**، يعني بتتبني قبل ما أول صورة توصل
    // والمريض لسه `null`. من غير السطر ده الترحيب بيفضل من غير اسم
    // للأبد — قراية واحدة في `initState` بتحصل بدري أوي.
    if (old.patient?.uuid != widget.patient?.uuid) unawaited(_loadMe());
  }

  Future<void> _loadMe() async {
    final service = AppScope.of(context).caregiverPreferences;
    final patient = widget.patient;
    if (service == null || patient == null) return;
    try {
      final row = await service.load(patient.uuid);
      if (mounted) setState(() => _me = row.profile);
    } catch (_) {
      // أوفلاين — «أهلاً بيك» من غير اسم. مفيش حاجة بتتعطّل.
    }
  }

  /// بيفتح نفس شاشة الأسئلة، متعبّية باللي في السحابة.
  ///
  /// بيقرا الصف الأول: شاشة بتفتح فاضية على واحد جاوب قبل كده بتخلّيه
  /// يفتكر إن اللي كتبه راح.
  Future<void> _openPreferences() async {
    final scope = AppScope.of(context);
    final service = scope.caregiverPreferences;
    final patient = widget.patient;
    if (service == null || patient == null || _busy) return;
    setState(() => _busy = true);
    CaregiverPreferences? current;
    try {
      current = await service.load(patient.uuid);
    } catch (_) {
      // القراءة فشلت — بنفتح على الافتراضي بدل ما نمنعه. الحفظ هو اللي
      // بيتكلّم لو فشل، وده اللي بيهم.
      current = const CaregiverPreferences();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => CaregiverOnboardingScreen(
        patientUuid: patient.uuid,
        patientName: patient.name,
        preferences: service,
        initial: current!,
        onDone: () => Navigator.of(context).maybePop(),
      ),
    ));
    // رجع من الأسئلة — الاسم ممكن يكون اتغيّر، فالترحيب بيتقرا تاني.
    await _loadMe();
  }

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
          if (widget.nurseReminders) ...[
            _NurseRemindersRow(onChanged: widget.onNurseRemindersChanged),
            const SizedBox(height: F.s12),
            for (final p in widget.nursePatients) ...[
              _NursePatientPrefs(
                patient: p,
                onDoseRemindersChanged: (on) {
                  widget.onNurseDoseRemindersChanged?.call(p.uuid, on);
                  widget.onNurseRemindersChanged?.call();
                },
              ),
              const SizedBox(height: F.s12),
            ],
          ],
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // **سطر الترحيب باسمه** — أول حاجة في كارت حسابه.
                // الاسم بيتقرا من اللي هو كتبه في الأسئلة، والصلة بتتضاف
                // للابن والبنت بس (صيغتهم مؤكّدة).
                Text(
                  welcomeLine(_me, widget.patient?.name ?? ''),
                  key: const ValueKey('care-welcome'),
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.careTitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: F.s8),
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
                // Apple 5.1.1(v): المسح من جوّه التطبيق — للمتابع والممرض كمان،
                // دايماً ظاهر؛ من غير خدمة سحابة = الموبايل ده بس
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: CareTextAction(
                    key: const ValueKey('care-delete-account'),
                    label: 'امسح حسابي',
                    icon: Icons.person_remove_outlined,
                    onPressed: _busy
                        ? () {}
                        : () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => DeleteAccountScreen(
                                who: (widget.patient?.isNurse ?? false)
                                    ? DeletingAs.nurse
                                    : DeletingAs.follower,
                                linked: AppScope.of(context).accountDeletion != null,
                                patientName: widget.patient?.name ?? '',
                              ),
                            )),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: F.s12),
          // اشتراك العيلة: اشتراك واحد على المريض المتابَع، وأي حد في
          // الدائرة يقدر يدفعه — فالابن ليه نفس الباب اللي عند أبوه.
          if (AppScope.of(context).subscription case final sub? when widget.patient != null) ...[
            CareCard(
              padding: EdgeInsets.zero,
              child: InkWell(
                key: const ValueKey('care-settings-plan'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => FamilyPlanScreen(
                    service: sub,
                    patientName: widget.patient!.name,
                    coveredNames: [if (_me?.name.trim().isNotEmpty ?? false) _me!.name.trim()],
                  ),
                )),
                child: Container(
                  constraints: const BoxConstraints(minHeight: F.careTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: F.carePad),
                  child: Row(
                    children: [
                      Icon(Icons.family_restroom_outlined, size: 18, color: F.green),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: Text('اشتراك العيلة',
                            style: TextStyle(
                                fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                      ),
                      Icon(Icons.chevron_left, size: 18, color: F.mutedDark),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: F.s12),
          ],
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
          // **المدخل (ج): نفس الشاشة، متعبّية من السحابة.**
          //
          // الأسئلة الأربعة مش حاجة بتتسأل مرة وتخلص: الاسم بيتغيّر،
          // وساعات الهدوء بتتغيّر مع الشغل. الصف بيتقرا الأول فالشاشة
          // بتفتح على اللي هو كاتبه، مش فاضية.
          if (AppScope.of(context).caregiverPreferences != null)
            CareCard(
              padding: EdgeInsets.zero,
              child: InkWell(
                key: const ValueKey('care-settings-onboarding'),
                onTap: _busy ? null : _openPreferences,
                child: Container(
                  constraints: const BoxConstraints(minHeight: F.careTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: F.carePad),
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 18, color: F.green),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: Text('بياناتك وتنبيهاتك',
                            style: TextStyle(
                                fontSize: F.careBodySize,
                                fontWeight: FontWeight.w700,
                                color: F.ink)),
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
                const SizedBox(width: F.s8),
                // بتلفّ على الضيق بدل ما تعصر «اللغة» لحرف في السطر
                Flexible(
                  child: Text('عربي — النسخة دي عربي بس',
                      textAlign: TextAlign.end, style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark)),
                ),
              ],
            ),
          ),
          const LegalLinksRow(fontSize: F.careTextSize, minHeight: F.careTapTarget),
        ],
      );
}


/// «فكّرني بمواعيده» — مفتوح افتراضياً. صف بكلمة جنبه («شغّال»/«مقفول»)
/// زي الوضع الليلي، مش Switch. القفل بيلغي تذكيرات الممرض كلها على الموبايل
/// ده — ومفيش أي تذكير للمريض على الموبايل ده أصلاً يتلمس.
class _NurseRemindersRow extends StatefulWidget {
  const _NurseRemindersRow({this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<_NurseRemindersRow> createState() => _NurseRemindersRowState();
}

class _NurseRemindersRowState extends State<_NurseRemindersRow> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    NurseReminders.isEnabled().then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  @override
  Widget build(BuildContext context) => CareCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          key: const ValueKey('nurse-remind-toggle'),
          onTap: () async {
            final next = !_on;
            setState(() => _on = next);
            await NurseReminders.setEnabled(next);
            widget.onChanged?.call();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: F.careTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s8),
            child: Row(
              children: [
                Icon(Icons.alarm_outlined, size: 18, color: F.green),
                const SizedBox(width: F.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('فكّرني بمواعيده',
                          style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                      Text('الموبايل ده بيرن في ميعاد كل جرعة',
                          style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark)),
                    ],
                  ),
                ),
                Text(_on ? 'شغّال' : 'مقفول',
                    key: const ValueKey('nurse-remind-state'),
                    style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: _on ? F.green : F.mutedDark)),
              ],
            ),
          ),
        ),
      );
}

/// مفتاحين لكل مريض (0035)، في السحابة عشان يعيشوا بعد إعادة التنصيب وعشان
/// السيرفر يقرا التاني. الافتراضي مفتوح؛ فشل القراية بيسيب الافتراضي.
class _NursePatientPrefs extends StatefulWidget {
  const _NursePatientPrefs({required this.patient, required this.onDoseRemindersChanged});

  final CaregiverPatient patient;
  final void Function(bool on) onDoseRemindersChanged;

  @override
  State<_NursePatientPrefs> createState() => _NursePatientPrefsState();
}

class _NursePatientPrefsState extends State<_NursePatientPrefs> {
  CaregiverPreferences _prefs = const CaregiverPreferences();
  String? _line;
  bool _loaded = false;

  CaregiverPreferencesService? get _service => AppScope.maybeOf(context)?.caregiverPreferences;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _service?.load(widget.patient.uuid).then((p) {
      if (mounted) setState(() => _prefs = p);
    }).catchError((_) {});
  }

  Future<void> _save(CaregiverPreferences next, {bool dose = false}) async {
    final before = _prefs;
    setState(() {
      _prefs = next;
      _line = null;
    });
    if (dose) widget.onDoseRemindersChanged(next.nurseDoseReminders);
    try {
      await _service?.save(widget.patient.uuid, next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefs = before;
        _line = 'ما اتحفظش — جرّب تاني.';
      });
      if (dose) widget.onDoseRemindersChanged(before.nurseDoseReminders);
    }
  }

  Widget _row({required Key key, required String title, required String sub, required bool on, required VoidCallback onTap}) => InkWell(
        key: key,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: F.careTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: F.carePad, vertical: F.s8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                    Text(sub, style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark)),
                  ],
                ),
              ),
              Text(on ? 'شغّال' : 'مقفول',
                  style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w700, color: on ? F.green : F.mutedDark)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    return CareCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(F.carePad, F.s10, F.carePad, 0),
            child: Text(p.name, style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w800, color: F.ink)),
          ),
          _row(
            key: ValueKey('nurse-dose-reminders-${p.uuid}'),
            title: 'نبهني بمواعيد الدوا',
            sub: 'الموبايل ده بيرن في ميعاد كل جرعة',
            on: _prefs.nurseDoseReminders,
            onTap: () => _save(_prefs.copyWith(nurseDoseReminders: !_prefs.nurseDoseReminders), dose: true),
          ),
          _row(
            key: ValueKey('nurse-unconfirmed-alert-${p.uuid}'),
            title: 'نبهني لو مافيش تأكيد',
            sub: 'بعد نص ساعة من غير تأكيد — قبل ما العيلة تتبلّغ',
            on: _prefs.nurseUnconfirmedAlert,
            onTap: () => _save(_prefs.copyWith(nurseUnconfirmedAlert: !_prefs.nurseUnconfirmedAlert)),
          ),
          if (_line != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(F.carePad, 0, F.carePad, F.s8),
              child: Text(_line!, style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark)),
            ),
        ],
      ),
    );
  }
}
