import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/care/caregiver_preferences.dart';
import '../../../domain/care/follower_profile.dart';
import '../caregiver_ui.dart';

/// **أربع أسئلة بعد ما الابن يستبدل الكود** — كل واحد على شاشته، وكلهم
/// بيتخطّوا.
///
/// **الإعدادات دي بتغيّر اللي بيوصل الابن وبس.** تذكير الأب، وتوقيت سلّم
/// التصعيد، وأي حاجة على جهاز الأب — ما بتتلمسش من هنا.
///
/// والأربعة بيتعدّلوا بعدين من إعدادات الابن؛ الشاشة دي مش الباب الوحيد.
class CaregiverOnboardingScreen extends StatefulWidget {
  const CaregiverOnboardingScreen({
    required this.patientUuid,
    required this.patientName,
    required this.preferences,
    this.initial = const CaregiverPreferences(),
    this.onDone,
    super.key,
  });

  final String patientUuid;

  /// اسم الأب — بيتقال في الأسئلة عشان يبان إن دي متابعة مين.
  final String patientName;

  final CaregiverPreferencesService preferences;

  /// القيم اللي في السحابة — الشاشة دي بتفتح من الإعدادات كمان.
  final CaregiverPreferences initial;

  final VoidCallback? onDone;

  /// عدد الأسئلة — الاختبارات والعدّاد بيقروا منه.
  static const steps = 4;

  @override
  State<CaregiverOnboardingScreen> createState() => _CaregiverOnboardingScreenState();
}

class _CaregiverOnboardingScreenState extends State<CaregiverOnboardingScreen> {
  int _step = 0;
  bool _busy = false;
  late CaregiverPreferences _prefs = widget.initial;

  late final _name = TextEditingController(text: widget.initial.name ?? '');
  late final _other = TextEditingController(text: widget.initial.relationOther ?? '');

  @override
  void dispose() {
    _name.dispose();
    _other.dispose();
    super.dispose();
  }

  /// **الحفظ بعد كل خطوة، والفشل بيتقال.**
  ///
  /// لو قفل الشاشة في النص، اللي جاوبه بيفضل — والباقي بيفضل على افتراضه
  /// الآمن (كل جرعة تفوت، من غير هدوء).
  ///
  /// **وعمرها ما بتقول «تمام» والصف ما اتكتبش.** الكتابة دي مش مزامنة
  /// صامتة: الابن قاعد قدّام الشاشة مستني، ولو بلعنا العطل بيقفل وهو
  /// فاكر إن اسمه وصل لوالده وهو ما وصلش.
  Future<void> _advance({bool keep = true}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (keep) {
      try {
        // **اللي في الحقول بيدخل المسوّدة هنا**، مش مع كل حرف: الكتابة
        // بتحصل مرة عند الحفظ، فالحقل مش محتاج يعيد بناء الشاشة.
        final typed = _name.text.trim();
        final other = _other.text.trim();
        _prefs = _prefs.copyWith(
          name: typed.isEmpty ? null : typed,
          relationOther: other.isEmpty ? null : other,
        );
        await widget.preferences.save(widget.patientUuid, _prefs);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = saveFailedMessage;
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (_step + 1 < CaregiverOnboardingScreen.steps) {
        _step++;
      } else {
        _done = true;
      }
    });
    if (_done) widget.onDone?.call();
  }

  String? _error;

  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return Scaffold(
      appBar: careAppBar('متابعة ${widget.patientName}'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    F.carePad, F.careRowGap, F.carePad, F.carePad),
                children: [
                  Text(
                    'سؤال ${arabicNumber(_step + 1)} من ${arabicNumber(CaregiverOnboardingScreen.steps)}',
                    key: const ValueKey('onboarding-step'),
                    style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark),
                  ),
                  const SizedBox(height: F.s6),
                  switch (_step) {
                    0 => _NameStep(
                        name: _name,
                        other: _other,
                        relation: _prefs.relation,
                        onRelation: (r) => setState(() => _prefs = _prefs.copyWith(relation: r)),
                      ),
                    1 => const _AlertScopeStep(),
                    2 => _QuietStep(
                        quiet: _prefs.quietHours,
                        onPick: (from, to) => setState(() => _prefs = from == null
                            ? _prefs.copyWith(clearQuiet: true)
                            : _prefs.copyWith(quietFromMinute: from, quietToMinute: to)),
                      ),
                    _ => const _InviteStep(),
                  },
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(F.carePad),
              child: Column(
                children: [
                  // **العطل بيفضل قدّامه مع زرار يعيد** — مش بيعدّي، ومش
                  // بيتحوّل لـ«تمام».
                  if (_error case final message?) ...[
                    CarePanel(
                      key: const ValueKey('onboarding-error'),
                      text: message,
                      action: 'حاول تاني',
                      onAction: _busy ? () {} : () => _advance(),
                    ),
                    const SizedBox(height: F.s6),
                  ],
                  SizedBox(
                    height: F.careTapTarget,
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('onboarding-next'),
                      onPressed: _busy ? null : () => _advance(),
                      style: FilledButton.styleFrom(
                        backgroundColor: F.green,
                        foregroundColor: F.onDark,
                        textStyle: const TextStyle(
                            fontSize: F.careBodySize, fontWeight: FontWeight.w700),
                      ),
                      child: Text(
                        _step + 1 == CaregiverOnboardingScreen.steps ? 'تمام' : 'كمّل',
                      ),
                    ),
                  ),
                  // **كل سؤال بيتخطّى.** الافتراضي آمن، والإعدادات بتفتح
                  // نفس الشاشة بعدين — فمفيش سؤال بيحبسه.
                  if (_step + 1 < CaregiverOnboardingScreen.steps)
                    CareTextAction(
                      key: const ValueKey('onboarding-skip'),
                      label: 'تخطّى',
                      onPressed: _busy ? () {} : () => _advance(keep: _step != 0),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ ١ — مين
class _NameStep extends StatelessWidget {
  const _NameStep({
    required this.name,
    required this.other,
    required this.relation,
    required this.onRelation,
  });

  final TextEditingController name;
  final TextEditingController other;
  final FollowerRelation? relation;
  final ValueChanged<FollowerRelation> onRelation;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('اسمك وصلتك بيه'),
          const _Sub('والدك هيشوف الاسم ده على موبايله، عشان يعرف مين بيتابعه.'),
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('follower-name'),
                  controller: name,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(fontSize: F.careBodySize, color: F.ink),
                  decoration: _deco('اسمك'),
                ),
                const SizedBox(height: F.carePad),
                Text('صلتك بيه',
                    style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark)),
                const SizedBox(height: F.s6),
                Wrap(
                  spacing: F.s8,
                  runSpacing: F.s8,
                  children: [
                    for (final r in FollowerRelation.values)
                      _Chip(
                        key: ValueKey('relation-${r.name}'),
                        label: r.label,
                        selected: relation == r,
                        onTap: () => onRelation(r),
                      ),
                  ],
                ),
                if (relation == FollowerRelation.other) ...[
                  const SizedBox(height: F.carePad),
                  TextField(
                    key: const ValueKey('relation-other-text'),
                    controller: other,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(fontSize: F.careBodySize, color: F.ink),
                    decoration: _deco('يعني إيه؟ زي: أخوه، جوز بنته'),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
}

// --------------------------------------------------------- ٢ — إمتى يتنبّه
class _AlertScopeStep extends StatelessWidget {
  const _AlertScopeStep();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('عايز نبهك إمتى؟'),
          CareCard(
            key: const ValueKey('alert-scope'),
            border: F.green,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 20, color: F.green),
                    const SizedBox(width: F.s8),
                    Expanded(
                      child: Text('أي جرعة تفوت',
                          style: TextStyle(
                              fontSize: F.careBodySize,
                              fontWeight: FontWeight.w700,
                              color: F.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: F.s6),
                Text(
                  // **ليه اختيار واحد بس، مكتوب قدّامه.** «الأدوية المهمة
                  // بس» كانت بتفترض علامة «مهم» على الدوا، والعلامة دي
                  // اتشالت عن قصد: اختيار إن دوا مهم وتاني لأ حكم طبي.
                  // فمفيش حاجة يتفلتر عليها، و«المهمة بس» كان معناه
                  // «مفيش تنبيهات» — إعداد بيسكت في صمت.
                  'كل دوا عند والدك بيتنبّه عليه. مفيش «دوا مهم» و«دوا عادي» — '
                  'ده حكم طبي مش بتاعنا، وتقسيمه كان معناه إن حاجات تعدّي '
                  'من غير ما تعرف.',
                  style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      );
}

// ------------------------------------------------------- ٣ — ساعات الهدوء
class _QuietStep extends StatelessWidget {
  const _QuietStep({required this.quiet, required this.onPick});

  final QuietHours? quiet;
  final void Function(int? from, int? to) onPick;

  /// اختيارات جاهزة — والرابع بيفتح ساعة النظام.
  static const presets = [
    (label: 'من ١٢ بالليل لـ٧ الصبح', from: 0, to: 7 * 60),
    (label: 'من ١٠ بالليل لـ٨ الصبح', from: 22 * 60, to: 8 * 60),
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('ساعات هدوء؟'),
          const _Sub('اختياري — ولو سيبتها، كل حاجة هتوصلك في وقتها.'),
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Chip(
                  key: const ValueKey('quiet-none'),
                  label: 'مفيش هدوء',
                  selected: quiet == null,
                  onTap: () => onPick(null, null),
                ),
                for (final p in presets) ...[
                  const SizedBox(height: F.s8),
                  _Chip(
                    key: ValueKey('quiet-${p.from}'),
                    label: p.label,
                    selected: quiet?.fromMinute == p.from && quiet?.toMinute == p.to,
                    onTap: () => onPick(p.from, p.to),
                  ),
                ],
              ],
            ),
          ),
          // **الوعد مكتوب على الشاشة، من مصدر واحد.**
          CareCard(
            key: const ValueKey('quiet-promise'),
            border: F.gold,
            child: Text(
              quietHoursPromise,
              style: TextStyle(
                  fontSize: F.careTextSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                  height: 1.6),
            ),
          ),
          Text(
            'اللي بيتأجّل بيوصلك أول ما الهدوء يخلص — مش بيتلغي.',
            style: TextStyle(fontSize: F.careMicroSize, color: F.mutedDark, height: 1.5),
          ),
        ],
      );
}

// ------------------------------------------------------- ٤ — حد تاني معاك
class _InviteStep extends StatelessWidget {
  const _InviteStep();

  /// أقصى عدد متابعين لمريض واحد.
  static const followerCap = 5;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Title('فيه حد تاني يتابع معاك؟'),
          CareCard(
            key: const ValueKey('invite-request'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  // **الطلب بيروح للأب، والكود ما بيتعملش من هنا.** دي
                  // بياناته الصحية هو: حد جديد ما بيشوفش حاجة غير لما
                  // والدك يوافق على موبايله. الموافقة نفسها جولة لوحدها.
                  'هنبعت طلب لوالدك يوافق عليه. لحد ما يوافق، الشخص ده '
                  'مش هيشوف أي حاجة — دي بياناته هو.',
                  style: TextStyle(fontSize: F.careBodySize, color: F.ink, height: 1.6),
                ),
                const SizedBox(height: F.s8),
                Text(
                  'أقصى عدد يتابعوه: ${arabicNumber(followerCap)}. '
                  'لو العدد كمل، لازم واحد يخرج قبل ما حد جديد يدخل.',
                  style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.5),
                ),
              ],
            ),
          ),
          // **بيتقال دلوقتي عشان محدش يتفاجئ بعدين** (قرار «Pricing»،
          // ٢٢ سبتمبر ٢٠٢٦): كل متابع بيدفع اشتراكه هو.
          CareCard(
            key: const ValueKey('invite-pricing'),
            border: F.careAccentSkipped,
            child: Text(
              followerPaysLine,
              style: TextStyle(fontSize: F.careTextSize, color: F.ink, height: 1.6),
            ),
          ),
        ],
      );
}

/// **الجملة الوحيدة اللي بتقول مين بيدفع** — قرار المالك ٢٢ سبتمبر ٢٠٢٦.
///
/// مكتوبة مرة واحدة عشان شاشتين ما يوعدوش بحاجتين.
/// **الجملة اللي بتظهر لما الحفظ يفشل** — مصدر واحد للشاشة وللاختبار.
const String saveFailedMessage =
    'مقدرناش نحفظ دلوقتي. اتأكد إنك متوصّل بالنت وحاول تاني.';

const String followerPaysLine =
    'لما الاشتراك يشتغل، كل واحد بيتابع بيدفع اشتراكه هو — والدك بيدفع بتاعه، '
    'وإنت بتدفع بتاعك.';

// --------------------------------------------------------------- قطع صغيرة
InputDecoration _deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: F.careTextSize, color: F.mutedDark),
      filled: true,
      fillColor: F.fieldGround,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.careRadius)),
    );

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s6),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.careTitleSize,
            fontWeight: FontWeight.w700,
            color: F.ink,
          ),
        ),
      );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.careRowGap),
        child: Text(
          text,
          style: TextStyle(fontSize: F.careTextSize, color: F.mutedDark, height: 1.5),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, super.key});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(F.careRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: F.careTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: F.carePad),
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(
            color: selected ? F.railGround : F.cardGround,
            borderRadius: BorderRadius.circular(F.careRadius),
            border: Border.all(color: selected ? F.green : F.line, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 18, color: selected ? F.green : F.mutedDark),
              const SizedBox(width: F.s8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: F.careTextSize,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: F.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
