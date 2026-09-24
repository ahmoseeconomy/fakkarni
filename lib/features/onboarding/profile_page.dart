import 'package:flutter/cupertino.dart' show CupertinoPicker, CupertinoPickerDefaultSelectionOverlay;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/patient/sex.dart';

/// «نتعرّف عليك» (المخطط 21) — أول خطوة قبل «ظبّط يومك».
///
/// الاسم، راجل ولا ست، والسن. بلغة دافية مش استمارة. الجنس هو اللي بيخلّي
/// باقي الكلام يطلع صح («بتفطر» / «بتفطري»)، فالأسئلة اللي بعدها بتتكتب بيه.
/// السن اختياري: لو ما اختارش، بيتحفظ null — مش بنكتب رقم ما قالهوش.
///
/// الجزء التاني في التصميم («الروشتة لو مش مكتوب فيها ميعاد؟») مش هنا:
/// اختياره التالت «افترض من غير ما تسأل» بيكسر القاعدة ٤.
class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.onDone, this.initialName, super.key});

  final String? initialName;
  final Future<void> Function({required String name, required Sex sex, int? age}) onDone;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final _name = TextEditingController(
    // «أنا» اللي ensurePatient بيحطّه مش اسم — الحقل يبدأ فاضي
    text: widget.initialName == 'أنا' ? '' : (widget.initialName ?? ''),
  );
  Sex? _sex;

  /// null لحد ما يحرّك البكرة بنفسه — السؤال اختياري، والبكرة واقفة على
  /// ٦٠ مش معناه إنه قال ٦٠.
  int? _age;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready => _name.text.trim().isNotEmpty && _sex != null;

  Future<void> _submit() async {
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onDone(name: _name.text.trim(), sex: _sex!, age: _age);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // الكلام بيتبع الجنس أول ما يتختار — حتى على الشاشة دي نفسها
    final say = Say(_sex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap),
            children: [
              Text(
                'تلات حاجات بس عشان نكلّمك صح. لو بتظبط الموبايل لحد تاني، اكتب بياناته هو.',
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.35),
              ),
              const SizedBox(height: F.gap),
              const _Label('اسمك إيه؟'),
              TextField(
                textInputAction: TextInputAction.done,
                controller: _name,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.words,
                style: TextStyle(fontSize: F.minBodySize, color: F.ink),
                decoration: InputDecoration(
                  hintText: 'اكتب اسمك — زي «الحاج أحمد»',
                  hintStyle: TextStyle(fontSize: F.minTextSize, color: F.placeholder),
                  filled: true,
                  fillColor: F.fieldGround,
                  contentPadding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(F.radiusCard),
                    borderSide: BorderSide(color: F.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(F.radiusCard),
                    borderSide: BorderSide(color: F.green, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: F.gap),
              const _Label('راجل ولا ست؟'),
              Row(
                children: [
                  Expanded(
                    child: AnchorChip(
                      label: 'راجل',
                      selected: _sex == Sex.m,
                      onTap: () => setState(() => _sex = Sex.m),
                    ),
                  ),
                  const SizedBox(width: F.s10),
                  Expanded(
                    child: AnchorChip(
                      label: 'ست',
                      selected: _sex == Sex.f,
                      onTap: () => setState(() => _sex = Sex.f),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: F.s10),
              _Label(say.pick('سنّك كام؟ (لو حابب)', 'سنّك كام؟ (لو حابّة)')),
              AgeWheel(
                value: _age,
                clearLabel: say.pick('مش عايز أقول', 'مش عايزة أقول'),
                onChanged: (v) => setState(() => _age = v),
              ),
              const SizedBox(height: F.gap),
              FCard(
                tone: FCardTone.warm,
                child: Text(
                  'البيانات دي بتفضل على الموبايل ده. بنستخدمها عشان الكلام يطلع مظبوط — '
                  'زي «${say.breakfastQuestion}»',
                  style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s12),
          child: FPrimaryButton(
            label: _busy ? 'ثواني…' : 'كمّل',
            onPressed: _ready && !_busy ? _submit : null,
          ),
        ),
      ],
    );
  }

}

/// **بكرة السن — من ١٨ لـ١١٠، بشكل بكرة الساعة بتاعة آبل، وعلى أندرويد كمان.**
///
/// كانت شرايح نطاقات كلها فوق الستين («٦٠–٦٤» … «٨٥+»): واحد عنده ٤٠ سنة
/// وبياخد دوا ضغط مكانش يلاقي نفسه. البكرة بتبدأ واقفة على [restAge]
/// **من غير ما تكتب حاجة** — [value] بيفضل null لحد ما يحرّكها بإيده،
/// لأن السؤال اختياري و«واقفة على ٦٠» مش إجابة. «مش عايز أقول» بترجّعها
/// للراحة وبتمسح القيمة.
///
/// `CupertinoPicker` مش `CupertinoDatePicker`: الأولانية بتاخد أولادها
/// منّنا، فالأرقام عربي والخط بمقاسنا (عكس اللي خلّى `TimeWheel` تتكتب
/// بإيدنا). الهزّة على كل نقلة: iOS بيعملها لوحده، وأندرويد بناخدها من
/// [HapticFeedback].
class AgeWheel extends StatefulWidget {
  const AgeWheel({
    required this.value,
    required this.onChanged,
    required this.clearLabel,
    super.key,
  });

  /// null = لسه ما قالش.
  final int? value;
  final ValueChanged<int?> onChanged;

  /// «مش عايز أقول» / «مش عايزة أقول» — بتيجي من [Say.pick].
  final String clearLabel;

  static const int minAge = 18;
  static const int maxAge = 110;

  /// فين البكرة بتقف لما مفيش إجابة. **مش قيمة افتراضية** — مفيش سن
  /// بيتكتب من غير ما يتحرّك لها.
  static const int restAge = 60;

  static const double itemExtent = 44;

  /// **مقاس iPhone SE هو اللي حدده**: الاسم والجنس والبكرة وسطرها و«كمّل»
  /// كلهم لازم يبانوا من غير لفّ على ٦٦٧ بكسل. ~٢٫٥ صف ظاهر، والصف
  /// المختار في النص بأرضيته.
  static const double wheelHeight = 110;

  static const String hint = 'حرّك البكرة لحد سنّك';

  @override
  State<AgeWheel> createState() => _AgeWheelState();
}

class _AgeWheelState extends State<AgeWheel> {
  late final _controller = FixedExtentScrollController(
    initialItem: (widget.value ?? AgeWheel.restAge) - AgeWheel.minAge,
  );

  /// وإحنا بنرجّع البكرة للراحة بأنفسنا، النقلة دي مش «هو حرّكها».
  bool _syncing = false;

  @override
  void didUpdateWidget(AgeWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && oldWidget.value != null) _rest();
  }

  void _rest() {
    final target = AgeWheel.restAge - AgeWheel.minAge;
    if (!_controller.hasClients || _controller.selectedItem == target) return;
    _syncing = true;
    _controller.jumpToItem(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncing = false);
  }

  void _picked(int index) {
    if (_syncing) return;
    // آبل بتهزّ لوحدها على iOS؛ على أندرويد إحنا اللي بنهزّ
    if (defaultTargetPlatform != TargetPlatform.iOS) HapticFeedback.selectionClick();
    widget.onChanged(AgeWheel.minAge + index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'السن',
          child: SizedBox(
            height: AgeWheel.wheelHeight,
            child: CupertinoPicker(
              key: const ValueKey('age-wheel'),
              scrollController: _controller,
              itemExtent: AgeWheel.itemExtent,
              // الصف المختار بيبان بأرضية هادية — نفس شكل بكرة آبل
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                background: F.green.withValues(alpha: 0.14),
              ),
              onSelectedItemChanged: _picked,
              children: [
                for (var age = AgeWheel.minAge; age <= AgeWheel.maxAge; age++)
                  Center(
                    child: Text(
                      '${arabicNumber(age)} سنة',
                      style: TextStyle(
                        fontSize: F.minBodySize + 6,
                        fontWeight: FontWeight.w600,
                        color: F.ink,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: F.s4),
        // التلميح والزرار في صف واحد تحت البكرة — سطرين فوق بعض كانوا
        // بيزقّوا الزرار تحت حافة SE
        Row(
          children: [
            Expanded(
              child: Text(
                value == null ? AgeWheel.hint : 'سنّك ${arabicNumber(value)} سنة',
                key: const ValueKey('age-hint'),
                style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
              ),
            ),
            SizedBox(
              height: F.minTapTarget,
              child: TextButton(
                onPressed: () => widget.onChanged(null),
                child: Text(
                  widget.clearLabel,
                  style: TextStyle(
                    fontSize: F.minTextSize,
                    fontWeight: FontWeight.w600,
                    color: F.mutedDark,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: Text(
          text,
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.3),
        ),
      );
}

