import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';

/// «نتعرّف عليك» (المخطط 21) — أول خطوة وآخرها قبل «يومك».
///
/// **صفحتين، سؤال في كل صفحة**: الاسم ← السن. بتتحفظ مرة واحدة بعد السن.
/// الصفحة الحالية جاية من برّه ([step]) عشان «رجوع» فوق يرجع صفحة، والمكتوب
/// بيفضل في الـState هنا بين الصفحات. (كان فيه صفحة «راجل ولا ست؟» بينهم —
/// اتشالت، ٢٧ سبتمبر ٢٠٢٦.)
///
/// السن اختياري: لو ما اختارش، بيتحفظ null — مش بنكتب رقم ما قالهوش.
///
/// الجزء التاني في التصميم («الروشتة لو مش مكتوب فيها ميعاد؟») مش هنا:
/// اختياره التالت «افترض من غير ما تسأل» بيكسر القاعدة ٤.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    required this.onDone,
    this.initialName,
    this.step = 0,
    this.onStep,
    this.onInteract,
    this.busy = false,
    super.key,
  });

  final String? initialName;
  final Future<void> Function({required String name, int? age}) onDone;

  /// ٠ الاسم، ١ السن.
  final int step;

  /// الحفظ شغّال — الزرار بيقول «ثواني…».
  final bool busy;

  /// «كمّل» على صفحة قبل الأخيرة بتطلب الصفحة اللي بعدها.
  final ValueChanged<int>? onStep;

  /// أي لمسة (كتابة، اختيار، بكرة) — الصوت بيسكت.
  final VoidCallback? onInteract;

  static const int steps = 2;

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

/// حالة الصفحة.
class ProfilePageState extends State<ProfilePage> {
  late final _name = TextEditingController(
    // «أنا» اللي ensurePatient بيحطّه مش اسم — الحقل يبدأ فاضي
    text: widget.initialName == 'أنا' ? '' : (widget.initialName ?? ''),
  );
  /// null لحد ما يحرّك البكرة بنفسه — السؤال اختياري، والبكرة واقفة على
  /// ٦٠ مش معناه إنه قال ٦٠.
  int? _age;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready => _name.text.trim().isNotEmpty;

  Future<void> _next() async {
    if (!_ready || _busy) return;
    widget.onInteract?.call();
    if (widget.step < ProfilePage.steps - 1) {
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onStep?.call(widget.step + 1);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onDone(name: _name.text.trim(), age: _age);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _touch() => widget.onInteract?.call();

  List<Widget> _page() => switch (widget.step) {
        0 => [
            Text(
              'حاجتين بس. لو بتظبط الموبايل لحد تاني، اكتب بياناته هو.',
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.35),
            ),
            const SizedBox(height: F.gap),
            const _Label('اسمك إيه؟'),
            TextField(
              key: const ValueKey('profile-name'),
              textInputAction: TextInputAction.done,
              controller: _name,
              onChanged: (_) {
                _touch();
                setState(() {});
              },
              onSubmitted: (_) => _next(),
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
          ],
        _ => [
            const _Label('سنّك كام؟ (لو حابب)'),
            AgeWheel(
              value: _age,
              clearLabel: 'مش عايز أقول',
              onChanged: (v) {
                _touch();
                setState(() => _age = v);
              },
            ),
            const SizedBox(height: F.gap),
            FCard(
              tone: FCardTone.warm,
              child: Text(
                'البيانات دي بتفضل على الموبايل ده — مش بتتبعت لحد.',
                style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.6),
              ),
            ),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final busy = _busy || widget.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: ValueKey('profile-step-${widget.step}'),
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap),
            children: _page(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('profile-next'),
                label: busy ? 'ثواني…' : 'كمّل',
                onPressed: _ready && !busy ? _next : null,
              ),
              const SizedBox(height: F.s8),
              ProgressDots(current: widget.step + 1, total: ProfilePage.steps),
            ],
          ),
        ),
      ],
    );
  }
}

/// **بكرة السن — من ١٨ لـ١١٠، على [FNumberWheel] المشتركة.**
///
/// كانت شرايح نطاقات كلها فوق الستين («٦٠–٦٤» … «٨٥+»): واحد عنده ٤٠ سنة
/// وبياخد دوا ضغط مكانش يلاقي نفسه. البكرة بتبدأ واقفة على [restAge]
/// **من غير ما تكتب حاجة** — [value] بيفضل null لحد ما يحرّكها بإيده،
/// لأن السؤال اختياري و«واقفة على ٦٠» مش إجابة. «مش عايز أقول» بترجّعها
/// للراحة وبتمسح القيمة. اللي هنا بس التلميح والزرار؛ البكرة نفسها هي
/// بكرة كل رقم في التطبيق.
class AgeWheel extends StatelessWidget {
  const AgeWheel({
    required this.value,
    required this.onChanged,
    required this.clearLabel,
    super.key,
  });

  /// null = لسه ما قالش.
  final int? value;
  final ValueChanged<int?> onChanged;

  /// «مش عايز أقول».
  final String clearLabel;

  static const int minAge = 18;
  static const int maxAge = 110;

  /// فين البكرة بتقف لما مفيش إجابة. **مش قيمة افتراضية** — مفيش سن
  /// بيتكتب من غير ما يتحرّك لها.
  static const int restAge = 60;

  static const double itemExtent = FNumberWheel.itemExtent;

  /// **مقاس iPhone SE هو اللي حدده**: الاسم والجنس والبكرة وسطرها و«كمّل»
  /// كلهم لازم يبانوا من غير لفّ على ٦٦٧ بكسل.
  static const double wheelHeight = FNumberWheel.defaultHeight;

  static const String hint = 'حرّك البكرة لحد سنّك';

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FNumberWheel(
            key: const ValueKey('age-wheel'),
            value: value,
            rest: restAge,
            min: minAge,
            max: maxAge,
            unit: 'سنة',
            semanticsLabel: 'السن',
            height: wheelHeight,
            onChanged: onChanged,
          ),
          const SizedBox(height: F.s4),
          // التلميح والزرار في صف واحد تحت البكرة — سطرين فوق بعض كانوا
          // بيزقّوا الزرار تحت حافة SE
          Row(
            children: [
              Expanded(
                child: Text(
                  value == null ? hint : 'سنّك ${arabicNumber(value!)} سنة',
                  key: const ValueKey('age-hint'),
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4),
                ),
              ),
              SizedBox(
                height: F.minTapTarget,
                child: TextButton(
                  onPressed: () => onChanged(null),
                  child: Text(
                    clearLabel,
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

/// نقط التقدّم — الحالية ذهبية (إنت هنا)، والباقي line.
class ProgressDots extends StatelessWidget {
  const ProgressDots({required this.current, required this.total, super.key});

  /// ١-based.
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'سؤال ${arabicNumber(current)} من ${arabicNumber(total)}',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= total; i++)
              Container(
                key: ValueKey('dot-$i'),
                width: i == current ? 28 : 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: F.s4),
                decoration: BoxDecoration(
                  color: i == current ? F.gold : F.line,
                  borderRadius: BorderRadius.circular(F.radiusChip),
                ),
              ),
          ],
        ),
      );
}
