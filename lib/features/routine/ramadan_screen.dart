import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/ramadan.dart';
import '../onboarding/time_wheel.dart';

/// «وضع رمضان» — شاشة واحدة: مفتاح وساعتين.
///
/// ده مكان ما المراسي بتدفع تمنها: الأب بيقول «رمضان» مرة واحدة، وكل
/// جرعة «قبل الفطار» بتروح قبل الإفطار من نفسها. الأصل بيتحفظ بالحرف
/// وبيرجع لما يقفل — المستودع هو اللي بيضمن ده، الشاشة بتسأل بس.
class RamadanScreen extends StatefulWidget {
  const RamadanScreen({super.key});

  @override
  State<RamadanScreen> createState() => _RamadanScreenState();
}

class _RamadanScreenState extends State<RamadanScreen> {
  bool _loaded = false;

  /// الحالة المحفوظة وقت الفتح — عشان نعرف الحفظ بيفتح ولا بيقفل ولا بيعدّل.
  bool _wasOn = false;
  bool _on = false;
  RamadanTimes _times = RamadanTimes.cairoDefaults;

  /// عجلة واحدة مفتوحة في المرة، زي «عدّل يومك».
  _Meal? _wheelFor;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final services = AppScope.of(context);
    services.routines.ramadanTimes(services.patientId).then((saved) {
      if (!mounted) return;
      setState(() {
        _wasOn = saved != null;
        _on = _wasOn;
        _times = saved ?? RamadanTimes.cairoDefaults;
      });
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    if (_on) {
      await services.routines.enterRamadan(services.patientId, _times);
    } else if (_wasOn) {
      await services.routines.leaveRamadan(services.patientId);
    }
    // نفس ما بيحصل بعد «عدّل يومك»: جرعات المراسي بتاخد أرقام جديدة،
    // والساعات الثابتة بترجع بنفس أرقامها.
    await services.scheduler.rescheduleAll();

    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'وضع رمضان',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(F.gap),
                children: [
                  const Text(
                    'في رمضان الفطار بيبقى على المغرب والعشا على السحور. '
                    'شغّله مرة واحدة وكل جرعة مربوطة بالأكل هتتحرك لوحدها — '
                    'ولما رمضان يخلص، اقفله ويومك يرجع زي ما كان بالظبط.',
                    style: TextStyle(
                      fontSize: F.minTextSize,
                      color: F.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: F.gap),
                  _ToggleCard(
                    on: _on,
                    onChanged: (v) => setState(() => _on = v),
                  ),
                  if (_on) ...[
                    const SizedBox(height: 12),
                    _TimeCard(
                      question: 'بتفطر الساعة كام؟',
                      value: _times.iftar,
                      wheelOpen: _wheelFor == _Meal.iftar,
                      onChanged: (v) =>
                          setState(() => _times = _times.copyWith(iftar: v)),
                      onToggleWheel: () => setState(() => _wheelFor =
                          _wheelFor == _Meal.iftar ? null : _Meal.iftar),
                    ),
                    const SizedBox(height: 12),
                    _TimeCard(
                      question: 'بتتسحّر الساعة كام؟',
                      value: _times.suhoor,
                      wheelOpen: _wheelFor == _Meal.suhoor,
                      onChanged: (v) =>
                          setState(() => _times = _times.copyWith(suhoor: v)),
                      onToggleWheel: () => setState(() => _wheelFor =
                          _wheelFor == _Meal.suhoor ? null : _Meal.suhoor),
                    ),
                    const SizedBox(height: 12),
                    // العُرف مكتوب بالكلام — مش مخبّي في الكود
                    const Text(
                      'جرعات الغدا هتتحرك مع الفطار، والنوم هيتحسب بعد '
                      'السحور بساعة. الساعات الثابتة ما بتتحركش.',
                      style: TextStyle(
                        fontSize: F.minTextSize,
                        color: F.muted,
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(F.gap),
              child: SizedBox(
                width: double.infinity,
                height: F.primaryButtonHeight,
                child: FilledButton(
                  onPressed: _saving || !_loaded ? null : _save,
                  child: const Text('احفظ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Meal { iftar, suhoor }

/// المفتاح — صف واحد كبير، الكلمة عليه، ٥٦+ للمس. الذهبي = «إنت هنا».
class _ToggleCard extends StatelessWidget {
  const _ToggleCard({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(F.radius),
        side: BorderSide(color: on ? F.gold : F.line, width: on ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => onChanged(!on),
        borderRadius: BorderRadius.circular(F.radius),
        child: Padding(
          padding: const EdgeInsets.all(F.gap),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  on ? 'وضع رمضان شغّال' : 'وضع رمضان مقفول',
                  style: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
              ),
              Switch(
                value: on,
                onChanged: onChanged,
                activeTrackColor: F.gold,
                activeThumbColor: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// نفس كارت «عدّل يومك» من غير الاقتراحات: السؤال، الساعة، والعجلة.
class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.question,
    required this.value,
    required this.wheelOpen,
    required this.onChanged,
    required this.onToggleWheel,
  });

  final String question;
  final MinuteOfDay value;
  final bool wheelOpen;
  final ValueChanged<MinuteOfDay> onChanged;
  final VoidCallback onToggleWheel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(F.radius),
        border: Border.all(color: F.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  question,
                  style: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
              ),
              Text(
                arabicTime(DateTime(2026, 1, 1, value.hour, value.minute)),
                style: const TextStyle(
                  fontSize: F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.greenDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: F.minTapTarget,
            child: OutlinedButton(
              onPressed: onToggleWheel,
              child: Text(
                wheelOpen ? 'تمام كده' : 'غيّر الساعة',
                style: const TextStyle(
                  fontSize: F.minTextSize + 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (wheelOpen) ...[
            const SizedBox(height: 8),
            TimeWheel(value: value, onChanged: onChanged),
          ],
        ],
      ),
    );
  }
}
