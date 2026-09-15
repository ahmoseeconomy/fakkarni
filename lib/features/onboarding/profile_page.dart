import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/patient/sex.dart';
import '../medication/dose_editor.dart' show MinuteStepper;

/// «نتعرّف عليك» (المخطط 21) — أول خطوة قبل «ظبّط يومك».
///
/// الاسم، راجل ولا ست، والسن. بلغة دافية مش استمارة. الجنس هو اللي بيخلّي
/// باقي الكلام يطلع صح («بتفطر» / «بتفطري»)، فالأسئلة اللي بعدها بتتكتب بيه.
/// السن اختياري: لو ما اختارش، بيتحفظ null — مش بنكتب رقم ما قالهوش.
///
/// الجزء التاني في التصميم («الروشتة لو مش مكتوب فيها ميعاد؟») مش هنا:
/// اختياره التالت «افترض من غير ما تسأل» بيكسر القاعدة ٤.
class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.onDone, this.initialName, this.forSomeoneElse = false, super.key});

  final String? initialName;

  /// D4 «بظبّط لحد تاني»: الأسئلة عن المريض مش عن اللي ماسك التليفون. أول
  /// سؤال محايد (الجنس لسه ما اتختارش)، والباقي بالغايب بعد اختياره.
  final bool forSomeoneElse;
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
  int? _age;
  bool _busy = false;

  static const _ranges = [
    (label: '٦٠–٦٤', mid: 62),
    (label: '٦٥–٧٤', mid: 70),
    (label: '٧٥–٨٤', mid: 80),
    (label: '٨٥+', mid: 85),
  ];

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
    final say = Say(_sex, aboutSomeoneElse: widget.forSomeoneElse);
    final other = widget.forSomeoneElse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap),
            children: [
              Text(
                other
                    ? 'تلات حاجات بس عشان التطبيق يكلّم والدك أو والدتك صح.'
                    : 'تلات حاجات بس عشان نكلّمك صح. لو بتظبط الموبايل لحد تاني، اكتب بياناته هو.',
                style: TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.6),
              ),
              const SizedBox(height: F.gap),
              _Label(other ? 'اسم والدك أو والدتك إيه؟' : 'اسمك إيه؟'),
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: F.minBodySize, color: F.ink),
                decoration: InputDecoration(
                  hintText: other ? 'زي «الحاج أحمد» أو «الحاجة فاطمة»' : 'اكتب اسمك — زي «الحاج أحمد»',
                  hintStyle: const TextStyle(fontSize: F.minTextSize, color: F.placeholder),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(F.radiusCard),
                    borderSide: const BorderSide(color: F.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(F.radiusCard),
                    borderSide: const BorderSide(color: F.green, width: 2),
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
              const SizedBox(height: F.gap),
              _Label(switch ((other, _sex)) {
                (false, _) => say.pick('سنّك كام؟ (لو حابب)', 'سنّك كام؟ (لو حابّة)'),
                (true, null) => 'السن كام؟ (لو تعرف)',
                (true, _) => say.pick('سنّه كام؟ (لو تعرف)', 'سنّها كام؟ (لو تعرف)'),
              }),
              Wrap(
                spacing: F.s8,
                runSpacing: F.s8,
                children: [
                  for (final r in _ranges)
                    AnchorChip(
                      label: r.label,
                      selected: _age != null && _rangeOf(_age!) == r.label,
                      onTap: () => setState(() => _age = r.mid),
                    ),
                ],
              ),
              if (_age != null) ...[
                const SizedBox(height: F.s10),
                MinuteStepper(
                  value: _age!,
                  step: 1,
                  min: 18,
                  max: 110,
                  unit: 'سنة',
                  onChanged: (v) => setState(() => _age = v),
                ),
              ],
              const SizedBox(height: F.gap),
              FCard(
                tone: FCardTone.warm,
                child: Text(
                  'البيانات دي بتفضل على الموبايل ده. بنستخدمها عشان الكلام يطلع مظبوط — '
                  'زي «${say.breakfastQuestion}»',
                  style: const TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.6),
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

  static String _rangeOf(int age) => switch (age) {
        < 65 => '٦٠–٦٤',
        < 75 => '٦٥–٧٤',
        < 85 => '٧٥–٨٤',
        _ => '٨٥+',
      };
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: Text(
          text,
          style: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
        ),
      );
}

